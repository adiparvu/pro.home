#!/usr/bin/env python3
"""
PRVIO: Add missing format strings (%@, %lld) to all 5 language files
and rebuild Localizable.xcstrings cleanly.
"""

import json, re
from pathlib import Path

ROOT = Path(__file__).parent.parent
RESOURCES = ROOT / "Resources"
LANGS = ["ro", "en", "fr", "nl", "de"]

# ─── Missing format strings with translations for all 5 languages ─────────────
# Key = the format string as it appears in the .strings file
# Each key must be the exact string SwiftUI looks up.
#
# SwiftUI LocalizedStringKey interpolation:
#   String argument  → %@
#   Int argument     → %lld
#   literal %        → %% in the key

MISSING_FORMAT_STRINGS = {
    # ── Delete / Remove confirmations ─────────────────────────────────────────
    'Delete "%@"?': {
        "ro": 'Șterge "%@"?',
        "en": 'Delete "%@"?',
        "fr": 'Supprimer "%@" ?',
        "nl": 'Verwijder "%@"?',
        "de": 'Löschen "%@"?',
    },
    "Delete %@?": {
        "ro": "Șterge %@?",
        "en": "Delete %@?",
        "fr": "Supprimer %@ ?",
        "nl": "Verwijder %@?",
        "de": "Löschen %@?",
    },
    "Remove %@?": {
        "ro": "Elimină %@?",
        "en": "Remove %@?",
        "fr": "Retirer %@ ?",
        "nl": "Verwijder %@?",
        "de": "Entfernen %@?",
    },

    # ── Loan return confirmation ───────────────────────────────────────────────
    '"%@" loaned to %@ will be marked as returned.': {
        "ro": '"%@" împrumutat lui %@ va fi marcat ca returnat.',
        "en": '"%@" loaned to %@ will be marked as returned.',
        "fr": '"%@" prêté à %@ sera marqué comme retourné.',
        "nl": '"%@" uitgeleend aan %@ wordt gemarkeerd als teruggegeven.',
        "de": '"%@" ausgeliehen an %@ wird als zurückgegeben markiert.',
    },

    # ── Progress ──────────────────────────────────────────────────────────────
    "%lld of %lld done": {
        "ro": "%lld din %lld finalizate",
        "en": "%lld of %lld done",
        "fr": "%lld sur %lld terminé(s)",
        "nl": "%lld van %lld gedaan",
        "de": "%lld von %lld erledigt",
    },

    # ── Status counts with text ───────────────────────────────────────────────
    "%lld active": {
        "ro": "%lld active",
        "en": "%lld active",
        "fr": "%lld actif(s)",
        "nl": "%lld actief",
        "de": "%lld aktiv",
    },
    "%lld warranty expiring soon": {
        "ro": "%lld garanții expiră curând",
        "en": "%lld warranty expiring soon",
        "fr": "%lld garantie(s) expirant bientôt",
        "nl": "%lld garantie(s) verlopen binnenkort",
        "de": "%lld Garantie(n) läuft bald ab",
    },
    "%lld overdue": {
        "ro": "%lld întârziate",
        "en": "%lld overdue",
        "fr": "%lld en retard",
        "nl": "%lld te laat",
        "de": "%lld überfällig",
    },

    # ── Widget strings ────────────────────────────────────────────────────────
    "%lld plants": {
        "ro": "%lld plante",
        "en": "%lld plants",
        "fr": "%lld plante(s)",
        "nl": "%lld planten",
        "de": "%lld Pflanzen",
    },
    "%lld today": {
        "ro": "%lld azi",
        "en": "%lld today",
        "fr": "%lld aujourd'hui",
        "nl": "%lld vandaag",
        "de": "%lld heute",
    },
    "%lld delivered": {
        "ro": "%lld livrate",
        "en": "%lld delivered",
        "fr": "%lld livré(s)",
        "nl": "%lld bezorgd",
        "de": "%lld geliefert",
    },

    # ── Seasonal checklist header ──────────────────────────────────────────────
    "%@ maintenance checklist": {
        "ro": "lista de verificare %@",
        "en": "%@ maintenance checklist",
        "fr": "liste de contrôle %@",
        "nl": "%@ onderhoudslijst",
        "de": "%@ Wartungsliste",
    },

    # ── Widget: Shopping list progress ────────────────────────────────────────
    "%lld din %lld articole": {
        "ro": "%lld din %lld articole",
        "en": "%lld of %lld items",
        "fr": "%lld sur %lld articles",
        "nl": "%lld van %lld artikelen",
        "de": "%lld von %lld Artikeln",
    },

    # ── Widget: Plant watering progress ───────────────────────────────────────
    "%lld din %lld plante udate": {
        "ro": "%lld din %lld plante udate",
        "en": "%lld of %lld plants watered",
        "fr": "%lld sur %lld plantes arrosées",
        "nl": "%lld van %lld planten bewaterd",
        "de": "%lld von %lld Pflanzen bewässert",
    },

    # ── Live Activity: carrier · status ──────────────────────────────────────
    "%@ · %@": {
        "ro": "%@ · %@",
        "en": "%@ · %@",
        "fr": "%@ · %@",
        "nl": "%@ · %@",
        "de": "%@ · %@",
    },
}


def escape_strings_value(s: str) -> str:
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')


def key_exists_in(content: str, key: str) -> bool:
    escaped_key = re.escape(escape_strings_value(key))
    return bool(re.search(rf'"{escaped_key}"\s*=', content))


def add_to_strings_file(path: Path, entries: dict[str, str], build_comment: str) -> int:
    content = path.read_text(encoding="utf-8")
    new_lines = [f"\n/* {build_comment} */"]
    added = 0
    for key, val in entries.items():
        if key_exists_in(content, key):
            continue
        ek = escape_strings_value(key)
        ev = escape_strings_value(val)
        new_lines.append(f'"{ek}" = "{ev}";')
        added += 1
    if added > 0:
        content = content.rstrip() + "\n" + "\n".join(new_lines) + "\n"
        path.write_text(content, encoding="utf-8")
    return added


def main():
    print("Adding missing format strings to all language files…")
    for lang in LANGS:
        path = RESOURCES / f"{lang}.lproj" / "Localizable.strings"
        entries = {k: v[lang] for k, v in MISSING_FORMAT_STRINGS.items()}
        added = add_to_strings_file(path, entries, "Build 293 — missing format strings (%@/%lld)")
        print(f"  [{lang}] +{added} format strings")

    # ── Rebuild Localizable.xcstrings cleanly ─────────────────────────────────
    print("\nRebuilding Localizable.xcstrings…")
    import sys
    sys.path.insert(0, str(ROOT / "scripts"))

    # Re-parse updated .strings files
    def unescape(s):
        return s.replace('\\n', '\n').replace('\\t', '\t').replace('\\"', '"').replace('\\\\', '\\')

    def parse_strings(path):
        result = {}
        if not path.exists():
            return result
        text = path.read_text(encoding="utf-8")
        text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
        text = re.sub(r'//[^\n]*', '', text)
        for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"', text):
            result[unescape(m.group(1))] = unescape(m.group(2))
        return result

    strings_data = {lang: parse_strings(RESOURCES / f"{lang}.lproj" / "Localizable.strings")
                    for lang in LANGS}

    # Build xcstrings
    all_keys = set()
    for d in strings_data.values():
        all_keys.update(d.keys())

    strings_dict = {}
    for key in sorted(all_keys, key=str.casefold):
        locs = {}
        for lang in LANGS:
            val = strings_data[lang].get(key)
            if val is not None:
                locs[lang] = {"stringUnit": {"state": "translated", "value": val}}
        if "ro" in locs:
            for lang in LANGS:
                if lang != "ro" and lang not in locs:
                    locs[lang] = {"stringUnit": {"state": "needs_review", "value": strings_data["ro"][key]}}
        strings_dict[key] = {"localizations": locs} if locs else {}

    xcstrings = {
        "sourceLanguage": "ro",
        "strings": strings_dict,
        "version": "1.0"
    }

    output = RESOURCES / "Localizable.xcstrings"
    output.write_text(json.dumps(xcstrings, ensure_ascii=False, indent=2), encoding="utf-8")
    total = len(strings_dict)
    print(f"  Wrote {total} keys to Localizable.xcstrings")

    # ── Final coverage report ─────────────────────────────────────────────────
    ro_count = len(strings_data["ro"])
    print(f"\nFinal translation coverage:")
    print(f"  [ro] {ro_count}/{total} (source language)")
    for lang in ["en", "fr", "nl", "de"]:
        count = len(strings_data[lang])
        pct = 100 * count / total if total else 100
        gap = total - count
        suffix = f" (gap: {gap})" if gap > 0 else " ✓"
        print(f"  [{lang}] {count}/{total} ({pct:.1f}%){suffix}")


if __name__ == "__main__":
    main()
