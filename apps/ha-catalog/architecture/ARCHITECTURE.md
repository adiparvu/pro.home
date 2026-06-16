# HA Plugin Catalog — Modular Architecture for PRVIO

## Overview

The HA Plugin Catalog integrates Home Assistant ecosystem management directly into PRVIO.
Users browse, install, enable, and disable HA integrations, cards, and themes without
leaving the app. Each plugin maps to a real HA community project sourced from
`frenck/awesome-home-assistant` (230+ entries).

---

## Layer Diagram

```
┌─────────────────────────────────────────────────────────┐
│                      PRVIO iOS App                       │
│                                                          │
│  ┌──────────────────┐    ┌──────────────────────────┐   │
│  │  HAPluginCatalog │    │    HAInstanceManager     │   │
│  │      View        │◄───│  (HA server connections) │   │
│  └────────┬─────────┘    └──────────────────────────┘   │
│           │                                               │
│  ┌────────▼─────────┐    ┌──────────────────────────┐   │
│  │  HAPluginRegistry│    │    HAPluginManager       │   │
│  │  (catalog store) │    │  (install/enable/disable)│   │
│  └────────┬─────────┘    └──────────────┬───────────┘   │
│           │                              │                │
│  ┌────────▼──────────────────────────────▼──────────┐   │
│  │                  plugins.json                     │   │
│  │          (230+ entries, bundled + remote)         │   │
│  └───────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                          │ WebSocket / REST
                          ▼
              ┌───────────────────────┐
              │   Home Assistant      │
              │   (local or remote)   │
              │                       │
              │  • REST API           │
              │  • WebSocket API      │
              │  • HACS API           │
              │  • Supervisor API     │
              └───────────────────────┘
```

---

## Modules

### 1. `HAPluginModels.swift`
Pure data layer — no logic, no I/O.

| Type | Role |
|------|------|
| `HAPluginCategory` | 17-value enum with display name + SF Symbol icon |
| `HAPluginStatus` | active / archived / deprecated / unknown |
| `HAPluginInstallType` | hacs / addon / manual / lovelace / theme / blueprint |
| `HAPluginManifest` | Immutable catalog entry (id, name, category, URLs, license, stars…) |
| `HAInstalledPlugin` | Mutable per-user install state (enabled, version, instanceId) |
| `HAInstance` | HA server connection target (URL, token, name, default) |
| `HAPluginCatalog` | Top-level JSON wrapper (version + plugins[] + categories[]) |

### 2. `HAPluginRegistry.swift`
**Read-only** in-memory catalog store. Never writes.

| Method | Behavior |
|--------|----------|
| `loadBundled()` | Decode `plugins.json` from app bundle |
| `loadRemote(from:)` | Fetch & decode newer catalog JSON from CDN |
| `plugins(in:)` | Filter by `HAPluginCategory` |
| `plugins(matching:)` | Full-text search across name, description, tags |
| `plugin(id:)` | Lookup by stable ID |

### 3. `HAPluginManager.swift`
**Write** layer — install state per user.

| Method | Phase |
|--------|-------|
| `install(_:)` | Phase 1: local record; Phase 2: call HACS/HA API |
| `uninstall(pluginId:from:)` | Phase 1: local record; Phase 2: call HACS/HA API |
| `enable(pluginId:)` | Toggle isEnabled = true, persist to UserDefaults |
| `disable(pluginId:)` | Toggle isEnabled = false, persist to UserDefaults |
| `refresh()` | Phase 2: sync installed state from real HA instance |

Install strategy pattern — each `HAPluginInstallType` gets its own `HAInstallStrategy`:

```
HAInstallStrategy (protocol)
  ├── HACSInstallStrategy      — POST /api/hacs/repository/download
  ├── AddonInstallStrategy     — POST /api/hassio/addons/{slug}/install
  ├── LovelaceInstallStrategy  — patch configuration.yaml resources:
  └── ThemeInstallStrategy     — inject into themes: folder + reload frontend
```

### 4. `HAInstanceManager.swift`
Manages one or more HA server connections.

| Method | Phase |
|--------|-------|
| `add(_:)` / `remove(id:)` / `update(_:)` | Phase 1: CRUD in UserDefaults |
| `discoverOnLocalNetwork()` | Phase 2: Bonjour/mDNS `_home-assistant._tcp` |
| `checkHealth(of:)` | Phase 2: GET /api/ with Bearer token |
| `connectWebSocket(to:)` | Phase 2: ws(s)://host/api/websocket |

---

## Category Taxonomy (17 categories)

| Category | Color | Source in Awesome-HA |
|----------|-------|---------------------|
| Integrations | `#5B8CFF` | Vendor & Brand, Network, Federation |
| AI | `#BF5AF2` | AI & LLMs |
| Cameras | `#30B0C7` | Cameras & Video, Camera Cards |
| Security | `#FF3B30` | Security & Alarm |
| Energy | `#FFD60A` | Energy & Solar, EV Charging, Energy Cards |
| Garden | `#34C759` | Civic & Household (Irrigation) |
| Voice | `#FF9F0A` | Voice & Media Playback |
| Automations | `#636366` | Automation Tooling, Lighting, Climate Automation |
| Monitoring | `#FF6B35` | Logging & Analytics, Battery, Docker, NAS |
| Media | `#FF2D55` | Media Cards, Media Players |
| MQTT | `#6E4C9E` | MQTT Broker, MQTT Gateway |
| Zigbee | `#32ADE6` | Zigbee Gateway (Z2M, deCONZ) |
| Matter | `#00C7BE` | (future — Thread/Matter devices) |
| Dashboards | `#1C1C1E` | Dashboard Frameworks, Full Dashboards |
| Cards | `#007AFF` | All Lovelace Cards |
| Themes | `#FF6B9D` | All Themes + Icon Packs |
| Utilities | `#8E8E93` | Apps, DIY, Tools |

---

## Plugin Lifecycle

```
NOT_INSTALLED
     │
     │ install()
     ▼
  INSTALLED (isEnabled = true by default)
     │                    │
     │ disable()          │ uninstall()
     ▼                    ▼
  DISABLED          NOT_INSTALLED
     │
     │ enable()
     ▼
  INSTALLED
```

---

## Data Flow

```
App Launch
   │
   ├── HAPluginRegistry.loadBundled()     ← plugins.json (bundle)
   │
   ├── HAInstanceManager.loadFromDisk()   ← UserDefaults
   │
   ├── HAPluginManager.loadFromDisk()     ← UserDefaults (installed set)
   │
   └── (background) HAPluginRegistry.loadRemote()  ← CDN update check
```

---

## Catalog JSON Format

`apps/ha-catalog/catalog/plugins.json` — one file, all plugins.

```json
{
  "version": "1.0.0",
  "builtAt": "2026-06-16",
  "categories": [...],
  "plugins": [
    {
      "id":            "adaptive-lighting",
      "name":          "Adaptive Lighting",
      "category":      "automations",
      "subcategory":   "Lighting automation",
      "description":   "Slowly adjust brightness and color temperature...",
      "githubUrl":     "https://github.com/basnijholt/adaptive-lighting",
      "websiteUrl":    null,
      "hacsUrl":       null,
      "docsUrl":       null,
      "license":       "Apache-2.0",
      "status":        "active",
      "hacsCompatible": true,
      "stars":         3324,
      "lastUpdated":   null,
      "tags":          ["lighting", "circadian", "color-temperature"],
      "installType":   "hacs",
      "requiresHAVersion": null
    }
  ]
}
```

---

## Phase Plan

### Phase 1 (Current — catalog + architecture)
- ✅ `plugins.json` — 230+ entries from awesome-home-assistant
- ✅ `categories.json` — 17 categories with icons and colors
- ✅ `schema.json` — JSON Schema for validation
- ✅ `HAPluginModels.swift` — data types
- ✅ `HAPluginRegistry.swift` — catalog loading + search
- ✅ `HAPluginManager.swift` — install state stubs
- ✅ `HAInstanceManager.swift` — HA connection stubs

### Phase 2 (Next — UI + real HA connection)
- [ ] `HAPluginCatalogView.swift` — browse + search UI
- [ ] `HAPluginDetailView.swift` — plugin page with install button
- [ ] `HAInstanceSetupView.swift` — add HA instance (URL + token)
- [ ] Real HACS API install (POST /api/hacs/repository/download)
- [ ] Real HA Supervisor addon install
- [ ] HA WebSocket connection for live entity state

### Phase 3 (Future — deep PRVIO integration)
- [ ] Link HA entities to PRVIO zones (e.g., temperature sensor → room health)
- [ ] ARIA can query HA state via tool-use
- [ ] PRVIO property health incorporates HA sensor data
- [ ] Notifications from HA events piped into PRVIO alert system
