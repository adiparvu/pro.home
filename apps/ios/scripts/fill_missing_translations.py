#!/usr/bin/env python3
"""
Generate translations for the 67 keys missing from en/fr/nl/de,
and append them to each Localizable.strings file.
"""

import json, re
from pathlib import Path

ROOT = Path(__file__).parent.parent
RESOURCES = ROOT / "Resources"

# All 67 missing keys with translations per language
# Keys are the English/source strings; values are per-language translations
TRANSLATIONS = {
    "AI Settings": {
        "en": "AI Settings",
        "fr": "Paramètres IA",
        "nl": "AI-instellingen",
        "de": "KI-Einstellungen",
    },
    "ARIA Insights": {
        "en": "ARIA Insights",
        "fr": "Analyses ARIA",
        "nl": "ARIA-inzichten",
        "de": "ARIA-Einblicke",
    },
    "Accounts": {
        "en": "Accounts",
        "fr": "Comptes",
        "nl": "Accounts",
        "de": "Konten",
    },
    "Activities appear automatically as you\nadd tasks, documents, and transactions.": {
        "en": "Activities appear automatically as you\nadd tasks, documents, and transactions.",
        "fr": "Les activités apparaissent automatiquement\nquand vous ajoutez des tâches, documents et transactions.",
        "nl": "Activiteiten verschijnen automatisch\nals je taken, documenten en transacties toevoegt.",
        "de": "Aktivitäten erscheinen automatisch,\nwenn Sie Aufgaben, Dokumente und Transaktionen hinzufügen.",
    },
    "Adaugă persoană": {
        "en": "Add Person",
        "fr": "Ajouter une personne",
        "nl": "Persoon toevoegen",
        "de": "Person hinzufügen",
    },
    "Add Appliance": {
        "en": "Add Appliance",
        "fr": "Ajouter un appareil",
        "nl": "Apparaat toevoegen",
        "de": "Gerät hinzufügen",
    },
    "Add Bill": {
        "en": "Add Bill",
        "fr": "Ajouter une facture",
        "nl": "Rekening toevoegen",
        "de": "Rechnung hinzufügen",
    },
    "Add Buried Line": {
        "en": "Add Buried Line",
        "fr": "Ajouter une ligne souterraine",
        "nl": "Ondergrondse leiding toevoegen",
        "de": "Unterirdische Leitung hinzufügen",
    },
    "Add Contact": {
        "en": "Add Contact",
        "fr": "Ajouter un contact",
        "nl": "Contact toevoegen",
        "de": "Kontakt hinzufügen",
    },
    "Add Contractor": {
        "en": "Add Contractor",
        "fr": "Ajouter un prestataire",
        "nl": "Aannemer toevoegen",
        "de": "Auftragnehmer hinzufügen",
    },
    "Add Document": {
        "en": "Add Document",
        "fr": "Ajouter un document",
        "nl": "Document toevoegen",
        "de": "Dokument hinzufügen",
    },
    "Add Item": {
        "en": "Add Item",
        "fr": "Ajouter un article",
        "nl": "Item toevoegen",
        "de": "Element hinzufügen",
    },
    "Add Member": {
        "en": "Add Member",
        "fr": "Ajouter un membre",
        "nl": "Lid toevoegen",
        "de": "Mitglied hinzufügen",
    },
    "Add Network": {
        "en": "Add Network",
        "fr": "Ajouter un réseau",
        "nl": "Netwerk toevoegen",
        "de": "Netzwerk hinzufügen",
    },
    "Add Paint Color": {
        "en": "Add Paint Color",
        "fr": "Ajouter une couleur de peinture",
        "nl": "Verfkleur toevoegen",
        "de": "Farbe hinzufügen",
    },
    "Add Photo": {
        "en": "Add Photo",
        "fr": "Ajouter une photo",
        "nl": "Foto toevoegen",
        "de": "Foto hinzufügen",
    },
    "Add Plan": {
        "en": "Add Plan",
        "fr": "Ajouter un plan",
        "nl": "Plan toevoegen",
        "de": "Plan hinzufügen",
    },
    "Add Record": {
        "en": "Add Record",
        "fr": "Ajouter un enregistrement",
        "nl": "Record toevoegen",
        "de": "Eintrag hinzufügen",
    },
    "Add Value Entry": {
        "en": "Add Value Entry",
        "fr": "Ajouter une valeur",
        "nl": "Waarde toevoegen",
        "de": "Wert hinzufügen",
    },
    "Add account": {
        "en": "Add account",
        "fr": "Ajouter un compte",
        "nl": "Account toevoegen",
        "de": "Konto hinzufügen",
    },
    "Add plants to track\nwatering and their health status.": {
        "en": "Add plants to track\nwatering and their health status.",
        "fr": "Ajoutez des plantes pour suivre\nl'arrosage et leur état de santé.",
        "nl": "Voeg planten toe om bewateringsintervallen\nen gezondheid bij te houden.",
        "de": "Fügen Sie Pflanzen hinzu, um\nBewässerung und Gesundheitsstatus zu verfolgen.",
    },
    "Appliances": {
        "en": "Appliances",
        "fr": "Appareils",
        "nl": "Apparaten",
        "de": "Geräte",
    },
    "Assign Task": {
        "en": "Assign Task",
        "fr": "Attribuer une tâche",
        "nl": "Taak toewijzen",
        "de": "Aufgabe zuweisen",
    },
    "Authenticator": {
        "en": "Authenticator",
        "fr": "Authentificateur",
        "nl": "Authenticator",
        "de": "Authentifikator",
    },
    "Automation Builder": {
        "en": "Automation Builder",
        "fr": "Générateur d'automatisations",
        "nl": "Automatiseringsbouwer",
        "de": "Automatisierungsersteller",
    },
    "Calendar": {
        "en": "Calendar",
        "fr": "Calendrier",
        "nl": "Agenda",
        "de": "Kalender",
    },
    "Change Email": {
        "en": "Change Email",
        "fr": "Changer l'e-mail",
        "nl": "E-mail wijzigen",
        "de": "E-Mail ändern",
    },
    "Change Password": {
        "en": "Change Password",
        "fr": "Changer le mot de passe",
        "nl": "Wachtwoord wijzigen",
        "de": "Passwort ändern",
    },
    "Choose one of the 10 available icons.\nEach has variants for light and dark mode.": {
        "en": "Choose one of the 10 available icons.\nEach has variants for light and dark mode.",
        "fr": "Choisissez parmi les 10 icônes disponibles.\nChacune a des variantes clair et sombre.",
        "nl": "Kies uit 10 beschikbare pictogrammen.\nElk heeft varianten voor lichte en donkere modus.",
        "de": "Wählen Sie eines der 10 verfügbaren Symbole.\nJedes hat Varianten für den Licht- und Dunkelmodus.",
    },
    "Control what each family member\ncan see and access in the app.": {
        "en": "Control what each family member\ncan see and access in the app.",
        "fr": "Contrôlez ce que chaque membre de la famille\npeut voir et accéder dans l'application.",
        "nl": "Bepaal wat elk gezinslid\nkan zien en openen in de app.",
        "de": "Bestimmen Sie, was jedes Familienmitglied\nin der App sehen und aufrufen kann.",
    },
    "Custom range": {
        "en": "Custom range",
        "fr": "Période personnalisée",
        "nl": "Aangepaste periode",
        "de": "Benutzerdefinierter Zeitraum",
    },
    "Digital Twin": {
        "en": "Digital Twin",
        "fr": "Jumeau numérique",
        "nl": "Digitale tweeling",
        "de": "Digitaler Zwilling",
    },
    "Edit Contractor": {
        "en": "Edit Contractor",
        "fr": "Modifier le prestataire",
        "nl": "Aannemer bewerken",
        "de": "Auftragnehmer bearbeiten",
    },
    "Edit Member": {
        "en": "Edit Member",
        "fr": "Modifier le membre",
        "nl": "Lid bewerken",
        "de": "Mitglied bearbeiten",
    },
    "Edit zone": {
        "en": "Edit zone",
        "fr": "Modifier la zone",
        "nl": "Zone bewerken",
        "de": "Zone bearbeiten",
    },
    "Global Search": {
        "en": "Global Search",
        "fr": "Recherche globale",
        "nl": "Globale zoekopdracht",
        "de": "Globale Suche",
    },
    "Guest Mode": {
        "en": "Guest Mode",
        "fr": "Mode invité",
        "nl": "Gastmodus",
        "de": "Gastmodus",
    },
    "Jurnal activitate": {
        "en": "Activity Log",
        "fr": "Journal d'activité",
        "nl": "Activiteitenlogboek",
        "de": "Aktivitätsprotokoll",
    },
    "Link document": {
        "en": "Link document",
        "fr": "Lier un document",
        "nl": "Document koppelen",
        "de": "Dokument verknüpfen",
    },
    "Link task": {
        "en": "Link task",
        "fr": "Lier une tâche",
        "nl": "Taak koppelen",
        "de": "Aufgabe verknüpfen",
    },
    "Loan Out Item": {
        "en": "Loan Out Item",
        "fr": "Prêter un article",
        "nl": "Item uitlenen",
        "de": "Element ausleihen",
    },
    "Location & Tracker": {
        "en": "Location & Tracker",
        "fr": "Localisation & Tracker",
        "nl": "Locatie & Tracker",
        "de": "Standort & Tracker",
    },
    "Lost & Found Card": {
        "en": "Lost & Found Card",
        "fr": "Carte Perdu & Trouvé",
        "nl": "Gevonden Voorwerpen kaart",
        "de": "Fundsachen-Karte",
    },
    "Mention": {
        "en": "Mention",
        "fr": "Mention",
        "nl": "Vermelding",
        "de": "Erwähnung",
    },
    "Monthly Budget": {
        "en": "Monthly Budget",
        "fr": "Budget mensuel",
        "nl": "Maandbudget",
        "de": "Monatsbudget",
    },
    "Mortgage": {
        "en": "Mortgage",
        "fr": "Hypothèque",
        "nl": "Hypotheek",
        "de": "Hypothek",
    },
    "Mortgage Details": {
        "en": "Mortgage Details",
        "fr": "Détails de l'hypothèque",
        "nl": "Hypotheekdetails",
        "de": "Hypothekendetails",
    },
    "New List": {
        "en": "New List",
        "fr": "Nouvelle liste",
        "nl": "Nieuwe lijst",
        "de": "Neue Liste",
    },
    "New Plant": {
        "en": "New Plant",
        "fr": "Nouvelle plante",
        "nl": "Nieuwe plant",
        "de": "Neue Pflanze",
    },
    "New element": {
        "en": "New element",
        "fr": "Nouvel élément",
        "nl": "Nieuw element",
        "de": "Neues Element",
    },
    "New record": {
        "en": "New record",
        "fr": "Nouvel enregistrement",
        "nl": "Nieuw record",
        "de": "Neuer Eintrag",
    },
    "Notifications": {
        "en": "Notifications",
        "fr": "Notifications",
        "nl": "Meldingen",
        "de": "Benachrichtigungen",
    },
    "Objects": {
        "en": "Objects",
        "fr": "Objets",
        "nl": "Objecten",
        "de": "Objekte",
    },
    "PRVIO": {
        "en": "PRVIO",
        "fr": "PRVIO",
        "nl": "PRVIO",
        "de": "PRVIO",
    },
    "Paint Colors": {
        "en": "Paint Colors",
        "fr": "Couleurs de peinture",
        "nl": "Verfkleuren",
        "de": "Wandfarben",
    },
    "Photo Journal": {
        "en": "Photo Journal",
        "fr": "Journal photo",
        "nl": "Fotojournaal",
        "de": "Fototagebuch",
    },
    "Place on map": {
        "en": "Place on map",
        "fr": "Placer sur la carte",
        "nl": "Op kaart plaatsen",
        "de": "Auf Karte platzieren",
    },
    "Plans & 3D": {
        "en": "Plans & 3D",
        "fr": "Plans & 3D",
        "nl": "Plannen & 3D",
        "de": "Pläne & 3D",
    },
    "Property Value": {
        "en": "Property Value",
        "fr": "Valeur de la propriété",
        "nl": "Woningwaarde",
        "de": "Immobilienwert",
    },
    "Search": {
        "en": "Search",
        "fr": "Recherche",
        "nl": "Zoeken",
        "de": "Suche",
    },
    "Seasonal Checklists": {
        "en": "Seasonal Checklists",
        "fr": "Listes saisonnières",
        "nl": "Seizoenslijsten",
        "de": "Saisonale Checklisten",
    },
    "Share Location": {
        "en": "Share Location",
        "fr": "Partager la localisation",
        "nl": "Locatie delen",
        "de": "Standort teilen",
    },
    "Timeline": {
        "en": "Timeline",
        "fr": "Chronologie",
        "nl": "Tijdlijn",
        "de": "Zeitlinie",
    },
    "Trusted Contact": {
        "en": "Trusted Contact",
        "fr": "Contact de confiance",
        "nl": "Vertrouwd contact",
        "de": "Vertrauenskontakt",
    },
    "Underground": {
        "en": "Underground",
        "fr": "Souterrain",
        "nl": "Ondergronds",
        "de": "Unterirdisch",
    },
    "Zones": {
        "en": "Zones",
        "fr": "Zones",
        "nl": "Zones",
        "de": "Zonen",
    },
    "Șterge tot": {
        "en": "Clear All",
        "fr": "Tout effacer",
        "nl": "Alles wissen",
        "de": "Alles löschen",
    },
}

def escape_strings_value(s: str) -> str:
    """Escape a value for use in a .strings file."""
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')

def key_exists(content: str, key: str) -> bool:
    escaped_key = re.escape(key.replace('\n', '\\n'))
    pattern = rf'"{escaped_key}"\s*='
    return bool(re.search(pattern, content))

def main():
    for lang in ["en", "fr", "nl", "de"]:
        path = RESOURCES / f"{lang}.lproj" / "Localizable.strings"
        content = path.read_text(encoding="utf-8")

        new_lines = [f"\n/* Build 291 — missing keys propagated from ro.lproj */"]
        added = 0

        for key, translations in TRANSLATIONS.items():
            escaped_key = escape_strings_value(key)
            # Check if key already exists
            if key_exists(content, key):
                continue
            value = translations.get(lang, translations.get("en", key))
            escaped_val = escape_strings_value(value)
            new_lines.append(f'"{escaped_key}" = "{escaped_val}";')
            added += 1

        if added > 0:
            content = content.rstrip() + "\n" + "\n".join(new_lines) + "\n"
            path.write_text(content, encoding="utf-8")
            print(f"[{lang}] Added {added} missing keys")
        else:
            print(f"[{lang}] No missing keys to add")

if __name__ == "__main__":
    main()
