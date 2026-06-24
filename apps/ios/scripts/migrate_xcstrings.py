#!/usr/bin/env python3
"""
PRVIO iOS Full Localization Migration to .xcstrings
====================================================
Phase 1 — Parse all 5 .strings files
Phase 2 — Scan 240 Swift files for every UI string literal
Phase 3 — Find literals missing from the strings catalog
Phase 4 — Write Localizable.xcstrings (merged, single source of truth)
Phase 5 — Print comprehensive audit report
"""

import json
import re
import sys
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).parent.parent
SOURCES = ROOT / "Sources"
WIDGETS = ROOT / "Widgets"
RESOURCES = ROOT / "Resources"
LANGS = ["ro", "en", "fr", "nl", "de"]
SOURCE_LANG = "ro"
OUTPUT = RESOURCES / "Localizable.xcstrings"

# ─────────────────────────────────────────────────────────────────────────────
# 1. PARSE EXISTING .strings FILES
# ─────────────────────────────────────────────────────────────────────────────

def unescape(s: str) -> str:
    """Convert escaped .strings encoding → Python string."""
    return (s
            .replace('\\n', '\n')
            .replace('\\t', '\t')
            .replace('\\"', '"')
            .replace('\\\\', '\\'))


def parse_strings(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    text = re.sub(r'//[^\n]*', '', text)
    result = {}
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"', text):
        key = unescape(m.group(1))
        val = unescape(m.group(2))
        result[key] = val
    return result


def load_all_strings() -> dict[str, dict[str, str]]:
    data = {}
    for lang in LANGS:
        p = RESOURCES / f"{lang}.lproj" / "Localizable.strings"
        data[lang] = parse_strings(p)
        print(f"  [{lang}] {len(data[lang])} keys loaded")
    return data

# ─────────────────────────────────────────────────────────────────────────────
# 2. SCAN SWIFT FILES
# ─────────────────────────────────────────────────────────────────────────────

# Patterns: every construct that uses LocalizedStringKey implicitly in SwiftUI
_UI_PATTERNS = [
    # Text("…")
    r'\bText\("((?:[^"\\]|\\.)*)"\)',
    # .navigationTitle("…")
    r'\.navigationTitle\("((?:[^"\\]|\\.)*)"\)',
    r'\.navigationBarTitle\("((?:[^"\\]|\\.)*)"\)',
    # Button("…")
    r'\bButton\("((?:[^"\\]|\\.)*)"[,)\s]',
    # Label("…", systemImage:)
    r'\bLabel\("((?:[^"\\]|\\.)*)",\s*systemImage:',
    # Section("…")
    r'\bSection\("((?:[^"\\]|\\.)*)"[,)\s]',
    # TextField/SecureField("placeholder", …)
    r'\bTextField\("((?:[^"\\]|\\.)*)"[,)\s]',
    r'\bSecureField\("((?:[^"\\]|\\.)*)"[,)\s]',
    # Toggle("label", isOn:)
    r'\bToggle\("((?:[^"\\]|\\.)*)",\s*isOn:',
    # Picker("label", selection:)
    r'\bPicker\("((?:[^"\\]|\\.)*)",\s*selection:',
    # Menu("label")
    r'\bMenu\("((?:[^"\\]|\\.)*)"[,)\s]',
    # Link("label", destination:)
    r'\bLink\("((?:[^"\\]|\\.)*)",\s*destination:',
    # .alert("title"  / confirmationDialog("title"
    r'\.alert\("((?:[^"\\]|\\.)*)"',
    r'\bconfirmationDialog\("((?:[^"\\]|\\.)*)"',
    # Accessibility
    r'\.accessibilityLabel\("((?:[^"\\]|\\.)*)"',
    r'\.accessibilityHint\("((?:[^"\\]|\\.)*)"',
    r'\.accessibilityValue\("((?:[^"\\]|\\.)*)"',
    r'\.help\("((?:[^"\\]|\\.)*)"',
    # ShareLink("label", …)
    r'\bShareLink\("((?:[^"\\]|\\.)*)"[,)\s]',
    # .badge("…")
    r'\.badge\("((?:[^"\\]|\\.)*)"',
    # .placeholder("…")
    r'\.placeholder\("((?:[^"\\]|\\.)*)"',
    # .submitLabel hint strings
    r'\.toolbarRole\("((?:[^"\\]|\\.)*)"',
    # swipeAction labels: Label("Delete"…), Label("Done"…)
    r'\bLabel\("((?:[^"\\]|\\.)*)",\s*systemImage:',
]

_COMPILED = [re.compile(p) for p in _UI_PATTERNS]

# Strings that look like identifiers / system names / pure symbols — not user text
_SKIP_PATTERN = re.compile(
    r'^[a-z][a-zA-Z0-9._]+$'          # pure camelCase identifier
    r'|^[A-Z][a-zA-Z0-9._]*\.[a-z]'   # Type.property
    r'|^[a-z_]+\([^)]*\)$'            # function()
    r'|^[a-z]+\.[a-z]'                # module.symbol
    r'|^\w+:\s*\d'                     # "key: 123"
    r'|^[-+*/=<>!?@#$%^&|]'           # operators / symbols
)

# Strings that are clearly not user-facing
_NON_UI_KEYS = {
    "", " ", "  ",
    "DEBUG", "nil", "null", "true", "false",
    "com.", "group.",
}

# Keys that are SwiftUI system or programmatic (not for translation)
_SYSTEM_PREFIXES = (
    "com.", "group.", "supabase", "http", "https",
    "SELECT", "INSERT", "UPDATE", "DELETE",
    "yyyy", "MM", "dd", "HH", "mm", "ss",  # date formats
)


def is_translatable(s: str) -> bool:
    """True if the string is likely a user-facing, translatable string."""
    if not s or len(s) < 2:
        return False
    if s in _NON_UI_KEYS:
        return False
    if s.startswith(_SYSTEM_PREFIXES):
        return False
    # Pure numbers
    if re.match(r'^\d+\.?\d*$', s):
        return False
    # Pure symbol / icon name
    if re.match(r'^[a-z]+\.[a-z.]+$', s) and '.' in s:
        # SF Symbol names like "checkmark.circle.fill"
        return False
    # Very likely an SF Symbol identifier
    if re.match(r'^[a-z][a-z0-9.]*\.(fill|circle|square|slash|badge|arrow|chevron|plus|minus|xmark|checkmark)$', s):
        return False
    # Supabase table/column names
    if '_' in s and s == s.lower():
        return False
    # URL fragments
    if '/' in s or '://' in s:
        return False
    return True


def scan_swift_ui_strings(directories: list[Path]) -> dict[str, list[str]]:
    """Returns {literal: [file:line, ...]}"""
    found: dict[str, list[str]] = defaultdict(list)

    for directory in directories:
        for swift_file in sorted(directory.rglob("*.swift")):
            try:
                lines = swift_file.read_text(encoding="utf-8").splitlines()
            except Exception:
                continue

            for lineno, line in enumerate(lines, 1):
                stripped = line.strip()
                # Skip comments
                if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
                    continue
                # Skip preview code blocks
                if "PreviewProvider" in line or "#Preview" in line:
                    continue

                for pat in _COMPILED:
                    for m in pat.finditer(line):
                        raw = m.group(1)
                        literal = unescape(raw)
                        if not is_translatable(literal):
                            continue
                        ref = f"{swift_file.relative_to(ROOT)}:{lineno}"
                        found[literal].append(ref)

    return dict(found)

# ─────────────────────────────────────────────────────────────────────────────
# 3. BUILD Localizable.xcstrings
# ─────────────────────────────────────────────────────────────────────────────

def build_xcstrings(strings_data: dict[str, dict[str, str]]) -> dict:
    """Build .xcstrings JSON from per-language dicts."""
    all_keys: set[str] = set()
    for lang_data in strings_data.values():
        all_keys.update(lang_data.keys())

    strings_dict: dict[str, dict] = {}
    for key in sorted(all_keys, key=str.casefold):
        locs: dict[str, dict] = {}
        for lang in LANGS:
            val = strings_data[lang].get(key)
            if val is not None:
                locs[lang] = {
                    "stringUnit": {
                        "state": "translated",
                        "value": val
                    }
                }
        # If source language (ro) has the key, mark others as needs_review if absent
        if SOURCE_LANG in locs:
            for lang in LANGS:
                if lang != SOURCE_LANG and lang not in locs:
                    # Copy source value and mark state as needs_review
                    locs[lang] = {
                        "stringUnit": {
                            "state": "needs_review",
                            "value": strings_data[SOURCE_LANG][key]
                        }
                    }
        strings_dict[key] = {"localizations": locs} if locs else {}

    return {
        "sourceLanguage": SOURCE_LANG,
        "strings": strings_dict,
        "version": "1.0"
    }

# ─────────────────────────────────────────────────────────────────────────────
# 4. FIND MISSING KEYS
# ─────────────────────────────────────────────────────────────────────────────

def find_missing(
    swift_literals: dict[str, list[str]],
    strings_data: dict[str, dict[str, str]]
) -> dict[str, list[str]]:
    """Find literals used in Swift but absent from ro.lproj."""
    ro_keys = set(strings_data[SOURCE_LANG].keys())
    missing = {}
    for literal, refs in swift_literals.items():
        if literal not in ro_keys:
            missing[literal] = refs
    return missing

# ─────────────────────────────────────────────────────────────────────────────
# 5. ADD MISSING KEYS TO .xcstrings dict
# ─────────────────────────────────────────────────────────────────────────────

def inject_missing_into_xcstrings(xcstrings: dict, missing: dict[str, list[str]]) -> int:
    """Inject missing Swift literals into xcstrings dict. Returns count added."""
    added = 0
    for literal in missing:
        if literal in xcstrings["strings"]:
            continue
        # Add with source=literal for all languages (needs review)
        xcstrings["strings"][literal] = {
            "comment": "AUTO: found in Swift, needs translation",
            "localizations": {
                lang: {
                    "stringUnit": {
                        "state": "needs_review",
                        "value": literal
                    }
                }
                for lang in LANGS
            }
        }
        added += 1
    return added

# ─────────────────────────────────────────────────────────────────────────────
# 6. FIND KEYS MISSING TRANSLATIONS ACROSS LANGUAGES
# ─────────────────────────────────────────────────────────────────────────────

def find_untranslated(xcstrings: dict) -> dict[str, list[str]]:
    """Find keys where non-source languages have needs_review state."""
    untranslated: dict[str, list[str]] = defaultdict(list)
    for key, entry in xcstrings["strings"].items():
        locs = entry.get("localizations", {})
        for lang in LANGS:
            if lang == SOURCE_LANG:
                continue
            loc = locs.get(lang, {})
            unit = loc.get("stringUnit", {})
            if unit.get("state") in ("needs_review", "new") or lang not in locs:
                untranslated[key].append(lang)
    return dict(untranslated)

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("=" * 72)
    print("PRVIO iOS Full Localization Audit & .xcstrings Migration")
    print("=" * 72)

    # ── Phase 1: Load existing .strings ──────────────────────────────────────
    print("\n[ Phase 1 ] Loading existing .strings files…")
    strings_data = load_all_strings()
    ro_count = len(strings_data[SOURCE_LANG])

    # ── Phase 2: Scan Swift files ─────────────────────────────────────────────
    print("\n[ Phase 2 ] Scanning Swift files for UI string literals…")
    dirs = [d for d in [SOURCES, WIDGETS] if d.exists()]
    swift_literals = scan_swift_ui_strings(dirs)
    swift_count = len(swift_literals)
    print(f"  Found {swift_count} unique translatable string literals across Swift files")

    # ── Phase 3: Build .xcstrings ─────────────────────────────────────────────
    print("\n[ Phase 3 ] Building Localizable.xcstrings…")
    xcstrings = build_xcstrings(strings_data)
    print(f"  Base: {len(xcstrings['strings'])} keys from .strings files")

    # ── Phase 4: Inject missing keys ──────────────────────────────────────────
    print("\n[ Phase 4 ] Injecting missing keys found in Swift…")
    missing = find_missing(swift_literals, strings_data)
    newly_added = inject_missing_into_xcstrings(xcstrings, missing)
    print(f"  Missing from catalog: {len(missing)} literals")
    print(f"  Injected into .xcstrings: {newly_added}")

    # Sort strings dict by key
    xcstrings["strings"] = dict(
        sorted(xcstrings["strings"].items(), key=lambda x: x[0].casefold())
    )

    # ── Phase 5: Write .xcstrings ─────────────────────────────────────────────
    print(f"\n[ Phase 5 ] Writing {OUTPUT.relative_to(ROOT)}…")
    OUTPUT.write_text(
        json.dumps(xcstrings, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )
    total_keys = len(xcstrings["strings"])
    print(f"  Wrote {total_keys} total keys")

    # ── Phase 6: Untranslated analysis ────────────────────────────────────────
    print("\n[ Phase 6 ] Analyzing translation coverage…")
    untranslated = find_untranslated(xcstrings)
    by_lang: dict[str, int] = defaultdict(int)
    for key, langs in untranslated.items():
        for lang in langs:
            by_lang[lang] += 1

    # ── REPORT ────────────────────────────────────────────────────────────────
    print()
    print("=" * 72)
    print("AUDIT REPORT")
    print("=" * 72)
    print(f"  Swift files scanned:              {sum(1 for d in dirs for _ in d.rglob('*.swift'))}")
    print(f"  UI string literals found (Swift): {swift_count}")
    print(f"  Keys in source (ro):              {ro_count}")
    print(f"  Keys already localized:           {ro_count - len(missing)}")
    print(f"  Keys missing from catalog:        {len(missing)}")
    print(f"  Total keys in .xcstrings:         {total_keys}")
    print()
    print("  Translation coverage per language:")
    for lang in LANGS:
        if lang == SOURCE_LANG:
            print(f"    [{lang}] {total_keys}/{total_keys} (source language)")
        else:
            gap = by_lang.get(lang, 0)
            translated = total_keys - gap
            pct = 100 * translated / total_keys if total_keys else 100
            print(f"    [{lang}] {translated}/{total_keys} ({pct:.1f}%)")

    if missing:
        print(f"\n  Top 40 missing keys (need translation):")
        for literal, refs in sorted(missing.items())[:40]:
            short_ref = refs[0] if refs else "?"
            display = literal.replace('\n', '\\n')[:60]
            print(f"    • \"{display}\" — {short_ref}")
        if len(missing) > 40:
            print(f"    … and {len(missing) - 40} more (see scripts/missing_keys.json)")

    # Save missing keys to JSON for follow-up
    missing_out = ROOT / "scripts" / "missing_keys.json"
    missing_export = {
        k: {"refs": v, "suggested_translations": {lang: k for lang in LANGS}}
        for k, v in sorted(missing.items())
    }
    missing_out.write_text(
        json.dumps(missing_export, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )
    print(f"\n  Full missing key list → scripts/missing_keys.json")

    # Save full report JSON
    report = {
        "swift_files_scanned": sum(1 for d in dirs for _ in d.rglob("*.swift")),
        "swift_ui_literals_found": swift_count,
        "keys_in_source_ro": ro_count,
        "keys_missing_from_catalog": len(missing),
        "total_keys_in_xcstrings": total_keys,
        "translation_coverage": {
            lang: {
                "translated": total_keys - by_lang.get(lang, 0),
                "total": total_keys,
                "pct": round(100 * (total_keys - by_lang.get(lang, 0)) / total_keys, 1) if total_keys else 100
            }
            for lang in LANGS
        },
        "missing_keys": list(missing.keys()),
    }
    report_out = ROOT / "scripts" / "xcstrings_migration_report.json"
    report_out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"  Full report → scripts/xcstrings_migration_report.json")
    print("=" * 72)

    return 0 if (len(missing) == 0 and max(by_lang.values(), default=0) == 0) else 1


if __name__ == "__main__":
    sys.exit(main())
