#!/usr/bin/env python3
"""
PRVIO iOS Localization Audit Tool
Scans Swift source files and .strings files to report:
  1. Keys present in ro.lproj missing from other languages
  2. SwiftUI localization anti-patterns in Swift files
  3. Summary statistics

Usage: python3 localization_audit.py [--fix-report]
"""

import re
import os
import sys
import json
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).parent.parent
SOURCES = ROOT / "Sources"
RESOURCES = ROOT / "Resources"
LANGS = ["ro", "en", "fr", "nl", "de"]

# ─── 1. Parse .strings files ────────────────────────────────────────────────

def parse_strings(path: Path) -> dict[str, str]:
    """Parse a .strings file, return {key: value}."""
    result = {}
    if not path.exists():
        return result
    content = path.read_text(encoding="utf-8")
    # Remove block comments
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    # Remove line comments
    content = re.sub(r'//[^\n]*', '', content)
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"', content):
        key = m.group(1).replace('\\"', '"')
        val = m.group(2).replace('\\"', '"')
        result[key] = val
    return result

def load_all_strings() -> dict[str, dict[str, str]]:
    data = {}
    for lang in LANGS:
        p = RESOURCES / f"{lang}.lproj" / "Localizable.strings"
        data[lang] = parse_strings(p)
    return data

# ─── 2. Scan Swift files for anti-patterns ──────────────────────────────────

ANTI_PATTERNS = [
    # Text with .uppercased() — breaks key lookup
    (r'Text\(([^)]+)\.uppercased\(\)\)', "Text(.uppercased()) — breaks key lookup"),
    # Text with .lowercased() — breaks key lookup
    (r'Text\(([^)]+)\.lowercased\(\)\)', "Text(.lowercased()) — breaks key lookup"),
    # Text with .capitalized — breaks key lookup
    (r'Text\(([^)]+)\.capitalized\b', "Text(.capitalized) — breaks key lookup"),
    # navigationTitle with String variable (not a literal)
    (r'\.navigationTitle\(([a-z][a-zA-Z0-9_.]+(?:\.(?!rawValue)[a-zA-Z0-9_]+)*)\)',
     ".navigationTitle(stringVar) — use LocalizedStringKey"),
    # Ternary in Text producing String (both arms are string literals)
    (r'Text\((?:[a-zA-Z0-9_.()!= ]+)\s*\?\s*"[^"]+"\s*:\s*"[^"]+"(?!\s*as\s*LocalizedStringKey)\)',
     "Text(ternary ? \"A\" : \"B\") — ternary produces String, not LocalizedStringKey"),
    # Label with String variable (common anti-pattern)
    (r'Label\("([^"]+)",\s*systemImage:\s*"([^"]+)"\)', None),  # labels with literals are OK
]

TERNARY_TEXT_PATTERN = re.compile(
    r'Text\((?!LocalizedStringKey)(?:[a-zA-Z0-9_.!= ()]+)\s*\?\s*"([^"]+)"\s*:\s*"([^"]+)"\)'
)

UPPERCASED_TEXT = re.compile(r'Text\(([a-zA-Z0-9_.]+)\.uppercased\(\)\)')
LOWERCASED_TEXT = re.compile(r'Text\(([a-zA-Z0-9_.]+)\.lowercased\(\)\)')
CAPITALIZED_TEXT = re.compile(r'Text\(([a-zA-Z0-9_.]+)\.capitalized\b')
NAV_TITLE_VAR = re.compile(r'\.navigationTitle\(([a-z][a-zA-Z0-9_.]+)\)')
STRING_PARAM_TEXT = re.compile(r'Text\(([a-z][a-zA-Z0-9_.]+(?:\.(?!rawValue)[a-zA-Z0-9_]+)*)\)')

def is_likely_data_string(var_name: str) -> bool:
    """Heuristic: skip vars that are clearly user data, not UI labels."""
    data_indicators = [
        'name', 'title', 'email', 'phone', 'address', 'city', 'country',
        'notes', 'note', 'description', 'query', 'text', 'message',
        'carrier', 'tracking', 'brand', 'model', 'serial', 'location',
        'prefix', 'value', 'sym', 'formatted', 'display'
    ]
    low = var_name.lower()
    return any(ind in low for ind in data_indicators)

def scan_swift_file(path: Path) -> list[dict]:
    issues = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except Exception:
        return issues

    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        # Skip comments
        if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue

        # .uppercased() in Text
        if m := UPPERCASED_TEXT.search(line):
            var = m.group(1)
            if not var.startswith('"'):
                issues.append({
                    "file": str(path.relative_to(ROOT)),
                    "line": i,
                    "pattern": ".uppercased() in Text()",
                    "code": stripped[:120],
                    "fix": f"Use Text({var}).textCase(.uppercase)"
                })

        # .lowercased() in Text (on display text - not data processing)
        if m := LOWERCASED_TEXT.search(line):
            var = m.group(1)
            if not var.startswith('"') and 'displayName' in var:
                issues.append({
                    "file": str(path.relative_to(ROOT)),
                    "line": i,
                    "pattern": ".lowercased() on displayName in Text()",
                    "code": stripped[:120],
                    "fix": f"Remove .lowercased(), let localization handle casing"
                })

        # .capitalized in Text
        if m := CAPITALIZED_TEXT.search(line):
            var = m.group(1)
            issues.append({
                "file": str(path.relative_to(ROOT)),
                "line": i,
                "pattern": ".capitalized in Text()",
                "code": stripped[:120],
                "fix": f"Use Text(LocalizedStringKey({var})) or add key to .strings"
            })

        # Ternary producing String in Text
        if m := TERNARY_TEXT_PATTERN.search(line):
            if 'LocalizedStringKey' not in line:
                issues.append({
                    "file": str(path.relative_to(ROOT)),
                    "line": i,
                    "pattern": "Ternary String in Text()",
                    "code": stripped[:120],
                    "fix": 'Wrap: Text(LocalizedStringKey(cond ? "A" : "B")) or use computed LocalizedStringKey property'
                })

    return issues

def scan_all_swift() -> list[dict]:
    issues = []
    for swift_file in SOURCES.rglob("*.swift"):
        issues.extend(scan_swift_file(swift_file))
    return issues

# ─── 3. Find missing keys across languages ──────────────────────────────────

def find_missing_keys(strings_data: dict) -> dict[str, list[str]]:
    ro_keys = set(strings_data["ro"].keys())
    missing = {}
    for lang in LANGS:
        if lang == "ro":
            continue
        lang_keys = set(strings_data[lang].keys())
        missing[lang] = sorted(ro_keys - lang_keys)
    return missing

# ─── 4. Find strings in .strings but potentially missing from Swift ──────────

def find_all_string_literals_in_swift() -> set[str]:
    """Extract all string literals passed to Text() from Swift files."""
    literals = set()
    pattern = re.compile(r'Text\("((?:[^"\\]|\\.)*)"\)')
    for swift_file in SOURCES.rglob("*.swift"):
        try:
            content = swift_file.read_text(encoding="utf-8")
            for m in pattern.finditer(content):
                literals.add(m.group(1))
        except Exception:
            pass
    return literals

# ─── 5. Main report ──────────────────────────────────────────────────────────

def main():
    print("=" * 70)
    print("PRVIO iOS Localization Audit")
    print("=" * 70)

    # Load strings
    strings_data = load_all_strings()
    ro_count = len(strings_data["ro"])
    print(f"\n📚 Strings per language:")
    for lang in LANGS:
        count = len(strings_data[lang])
        gap = ro_count - count
        gap_str = f" (-{gap} from ro)" if gap > 0 else " ✓"
        print(f"  {lang}: {count} keys{gap_str}")

    # Missing keys
    missing = find_missing_keys(strings_data)
    print(f"\n🔴 Missing keys (in ro but not in other languages):")
    total_missing = 0
    for lang, keys in missing.items():
        total_missing += len(keys)
        print(f"\n  [{lang}] {len(keys)} missing keys:")
        for key in keys[:50]:  # Show first 50
            ro_val = strings_data["ro"].get(key, "???")
            print(f"    • \"{key}\" (ro: \"{ro_val[:60]}\")")
        if len(keys) > 50:
            print(f"    ... and {len(keys) - 50} more")

    # Swift anti-patterns
    print(f"\n🟡 Swift localization anti-patterns:")
    swift_issues = scan_all_swift()
    by_pattern = defaultdict(list)
    for issue in swift_issues:
        by_pattern[issue["pattern"]].append(issue)

    for pattern, issues in sorted(by_pattern.items(), key=lambda x: -len(x[1])):
        print(f"\n  [{len(issues)}x] {pattern}:")
        for issue in issues[:10]:
            print(f"    {issue['file']}:{issue['line']}")
            print(f"      {issue['code'][:100]}")
        if len(issues) > 10:
            print(f"    ... and {len(issues) - 10} more")

    print(f"\n{'=' * 70}")
    print(f"SUMMARY:")
    print(f"  Missing translation keys: {total_missing}")
    print(f"  Swift anti-pattern issues: {len(swift_issues)}")
    print(f"  Files with issues: {len(set(i['file'] for i in swift_issues))}")
    print(f"{'=' * 70}")

    # JSON output for CI
    report = {
        "missing_keys": {lang: {k: strings_data["ro"][k] for k in keys}
                         for lang, keys in missing.items()},
        "swift_issues": swift_issues,
        "stats": {
            "total_missing_keys": total_missing,
            "total_swift_issues": len(swift_issues),
        }
    }
    out = ROOT / "scripts" / "localization_report.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False))
    print(f"\n📄 Full report saved to: scripts/localization_report.json")

    return 1 if (total_missing > 0 or len(swift_issues) > 0) else 0

if __name__ == "__main__":
    sys.exit(main())
