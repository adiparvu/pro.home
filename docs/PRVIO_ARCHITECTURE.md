# PRVIO — Complete System Architecture
**Version 2.0 · June 2026 · Build 192 baseline**

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Plugin Engine](#2-plugin-engine)
3. [Data Layer](#3-data-layer)
4. [SwiftUI Design System](#4-swiftui-design-system)
5. [Navigation Architecture](#5-navigation-architecture)
6. [Marketplace](#6-marketplace)
7. [Digital Twin Engine](#7-digital-twin-engine)
8. [Integration Map](#8-integration-map)
9. [Implementation Roadmap](#9-implementation-roadmap)

---

## 1. System Overview

PRVIO is a property intelligence platform that unifies three domains into one coherent experience:

```
┌─────────────────────────────────────────────────────────────────┐
│                         PRVIO iOS App                           │
│                                                                  │
│   ┌──────────────┐  ┌──────────────┐  ┌─────────────────────┐  │
│   │  Digital     │  │  Plugin      │  │    Marketplace      │  │
│   │  Twin Engine │  │  Engine      │  │    (HA Catalog +    │  │
│   │  (property   │  │  (HA plugin  │  │    Themes/Cards/    │  │
│   │  intelligence│  │  lifecycle)  │  │    Automations)     │  │
│   └──────┬───────┘  └──────┬───────┘  └─────────┬───────────┘  │
│          │                 │                     │              │
│   ┌──────▼─────────────────▼─────────────────────▼───────────┐  │
│   │                    Data Layer                             │  │
│   │    Universal Entity Model · SyncEngine · TimeSeriesStore  │  │
│   └──────────────────────────┬────────────────────────────────┘  │
│                              │                                   │
│   ┌──────────────────────────▼────────────────────────────────┐  │
│   │               PRVIODesignSystem + Navigation              │  │
│   │    liquidGlass · GlassCard · PRVIORouter · TabAdapter     │  │
│   └───────────────────────────────────────────────────────────┘  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
   ┌─────────────┐    ┌────────────────┐    ┌──────────────┐
   │  Supabase   │    │ Home Assistant │    │  CDN / Apple  │
   │  (20 tables │    │  REST/WS/HACS  │    │  Servers      │
   │  + Edge Fn) │    │  + Supervisor  │    │  (catalog,    │
   └─────────────┘    └────────────────┘    │   widgets)    │
                                            └──────────────┘
```

### Baseline State (Build 192)

| Dimension | Current |
|-----------|---------|
| Swift files | ~220 |
| Supabase tables | 20 |
| Navigation tabs | 5 (Home, Twin, Tasks, Chat, Settings) |
| Design system | liquidGlass (partial — no token file) |
| Plugin system | Phase 1 stubs only (catalog JSON + models) |
| HA integration | Not connected (no real API calls) |
| Marketplace | Does not exist |
| iPad/Mac | Not supported |
| Twin | PRVIO data only, no HA sensor overlay |

---

## 2. Plugin Engine

### 2.1 Responsibility

The Plugin Engine manages the full lifecycle of any plugin from the HA ecosystem catalog: discovery → install → enable → update → uninstall. It is the only layer that calls HA APIs.

### 2.2 Architecture

```
PluginEngine
├── PluginRegistry          (catalog store — read-only, exists as HAPluginRegistry)
├── PluginStateStore        (installed state — UserDefaults + Supabase mirror)
├── PluginInstaller         (strategy dispatch per install type)
│   ├── HACSStrategy        POST /api/hacs/repository/download
│   ├── AddonStrategy       POST /api/hassio/addons/{slug}/install
│   ├── LovelaceStrategy    PATCH configuration.yaml resources:[]
│   ├── ThemeStrategy       inject into themes: folder + reload_themes service
│   └── BlueprintStrategy   POST /api/blueprint/import
├── PluginPermissionGate    (iOS permission requests per capability)
├── PluginDependencyGraph   (DAG — topological install order)
├── PluginUpdateChecker     (background task, CDN version polling)
└── PluginEventBus          (notify Twin/Marketplace on state changes)
```

### 2.3 Plugin Manifest Extensions

The current `HAPluginManifest` (Phase 1) is extended with engine metadata:

```
HAPluginManifest (Phase 2 additions)
  ├── requiredCapabilities: [PluginCapability]
  │     .camera | .location | .bluetooth | .localNetwork
  │     .notifications | .siri | .homeKit
  ├── dependsOn: [String]          ← plugin IDs (resolved before install)
  ├── conflictsWith: [String]      ← mutually exclusive plugins
  ├── minHAVersion: String?        ← e.g. "2024.1"
  ├── minPRVIOVersion: String?     ← e.g. "1.2.0"
  └── providesEntityTypes: [HAEntityType]
        ← what entity domains this plugin adds to HA
           (sensor, switch, light, climate, camera, ...)
```

### 2.4 Installation Pipeline

```
User taps "Install"
  │
  ├─► PluginPermissionGate
  │       Check: plugin.requiredCapabilities
  │       Request iOS permission for each missing capability
  │       Block install if denied (show Settings deep link)
  │
  ├─► PluginDependencyGraph
  │       Build DAG from plugin.dependsOn (recursive)
  │       Detect cycles → error
  │       Return install order [dep2, dep1, target]
  │
  ├─► for each plugin in install order:
  │       PluginInstaller.install(manifest, on: HAInstance)
  │           → dispatch to matching HAInstallStrategy
  │           → wait for HA API confirmation
  │           → PluginStateStore.markInstalled(pluginId, version, instanceId)
  │
  ├─► PluginEventBus.publish(.pluginInstalled(manifest))
  │       → TwinSyncService.refresh()   ← Twin picks up new entity types
  │       → WidgetCenter.reloadAll()    ← Widget reflects new data
  │       → Marketplace badge update
  │
  └─► PluginStateStore.persist()        ← Supabase mirror for multi-device sync
```

### 2.5 Update Checker

- `BGAppRefreshTask` registered under `com.prvio.plugin-update-check`
- Frequency: every 6 hours
- Compares `HAPluginCatalog.version` (CDN) vs `cachedCatalogVersion` (local)
- Per-plugin: `installedVersion` vs `manifest.latestVersion`
- Stores pending updates in `PluginStateStore.pendingUpdates: [String]`
- Shows badge on Marketplace tab icon

### 2.6 Permission Gate

| Plugin Capability | iOS Framework | Permission String |
|-------------------|--------------|-------------------|
| `.camera` | AVFoundation | NSCameraUsageDescription |
| `.location` | CoreLocation | NSLocationWhenInUseUsageDescription |
| `.bluetooth` | CoreBluetooth | NSBluetoothAlwaysUsageDescription |
| `.localNetwork` | Network.framework | NSLocalNetworkUsageDescription |
| `.notifications` | UserNotifications | UNAuthorizationOptions |
| `.siri` | Intents | NSSiriUsageDescription |

### 2.7 Dependency Graph (DAG)

```
Example: installing "Mushroom Cards"
  dependsOn: ["lovelace-resources"]
    dependsOn: ["hacs"]

Resolution order:
  1. hacs (no deps)
  2. lovelace-resources (needs hacs)
  3. mushroom-cards (needs lovelace-resources)
```

Cycle detection: DFS with visited/inStack sets. Circular deps → `PluginInstallError.circularDependency`.

---

## 3. Data Layer

### 3.1 Universal Entity Model

Every object in PRVIO — native or HA-bridged — conforms to `PRVIOEntity`:

```
protocol PRVIOEntity: Identifiable, Codable {
    var id: String { get }
    var displayName: String { get }
    var entityType: EntityType { get }
    var zoneId: String? { get }            ← which zone this belongs to
    var propertyId: String { get }
    var lastUpdated: Date { get }
    var iconName: String { get }           ← SF Symbol
    var tintColor: Color { get }
}

enum EntityType {
    // PRVIO native
    case zone, element, appliance, plant, task, document, sensor

    // HA bridged (mirrors HA domain)
    case haSwitch, haLight, haClimate, haSensor
    case haCamera, haBinarySensor, haLock
    case haMediaPlayer, haCover, haAlarm
    case haScript, haAutomation, haScene
    case haWeather, haPersonTracker
}
```

### 3.2 Current Supabase Schema (20 tables) + Extensions

**Existing tables (Build 192):**

```
Core:          properties, property_members, property_zones, property_elements
               element_records
Maintenance:   maintenance_tasks
Content:       documents, photo_journal_entries
People:        family_members, profiles, avatars
Shopping:      supply_lists, supply_items, public_items
Finances:      financial_records
Smart Home:    appliances, plants, paint_colors
Messaging:     messages, message_reads
```

**New tables (Phase 2+):**

```
Plugin state:
  plugin_installations
    id, property_id, plugin_id, ha_instance_id, version,
    is_enabled, installed_at, updated_at

HA entities:
  ha_instances
    id, property_id, name, url, access_token_encrypted,
    is_default, ha_version, last_seen_at

  ha_entity_mappings
    id, ha_instance_id, entity_id (HA), zone_id (PRVIO),
    display_name_override, is_visible

Time series:
  sensor_readings
    id, entity_id, property_id, value (float), unit,
    recorded_at  ← partitioned by month

  energy_readings
    id, property_id, zone_id, kwh, cost, recorded_at

Marketplace:
  plugin_reviews
    id, user_id, plugin_id, rating (1-5), comment, created_at
```

### 3.3 SyncEngine

```
SyncEngine
├── Online mode:
│     Supabase Realtime subscriptions → local cache update → UI refresh
│     HA WebSocket → HAEntityBridge → TwinSyncService → UI refresh
│
├── Offline mode:
│     MutationQueue: [PendingMutation] persisted to UserDefaults
│     On reconnect: replay queue in order, resolve conflicts
│
└── Conflict resolution:
      last_write_wins on server timestamp
      Exception: task completion is idempotent (completed stays completed)
```

### 3.4 TimeSeriesStore

```
TimeSeriesStore
├── Source: Supabase sensor_readings + energy_readings
├── Local cache: last 24h of readings per entity (in-memory)
├── Granularity:
│     live:    latest value (WebSocket push)
│     hourly:  avg over last 7 days
│     daily:   avg over last 90 days
│     monthly: avg over last 2 years
└── Consumers:
      SensorChart (Swift Charts, PluginDetailView)
      EnergyDashboard (HomeView quick stat)
      TwinZoneCard (live sensor overlay)
```

### 3.5 HAEntityBridge

Maps Home Assistant entity state to PRVIO models:

```
HAEntityBridge
├── Input:  HA WebSocket state_changed events
├── Output: [HAEntitySnapshot] — id, state, attributes, lastChanged
│
├── Zone mapping:
│     ha_entity_mappings table → entity_id → zone_id
│     Unmapped entities: appear in "Unassigned" section
│
├── Entity → PRVIO translation:
│     sensor.temperature_bedroom → ZoneSnapshot.temperature
│     switch.bedroom_light       → ZoneSnapshot.devices[].state
│     camera.front_door          → PropertyElement (type: .camera)
│     alarm_control_panel.home   → SecurityStatus
│
└── Conflict:  if PRVIO has native appliance + HA has same device,
               user chooses primary source (PRVIO wins by default)
```

---

## 4. SwiftUI Design System

### 4.1 Design Tokens (currently missing — hardcoded values everywhere)

```
PRVIOTokens
├── Color
│   ├── Semantic
│   │   background:        Color(.systemBackground)
│   │   backgroundSecondary: Color(.secondarySystemBackground)
│   │   surface:           Color(.tertiarySystemBackground)
│   │   onBackground:      Color(.label)
│   │   onBackgroundSecondary: Color(.secondaryLabel)
│   │   accent:            Color("AccentColor")   ← from Assets.xcassets
│   │   success:           #34C759
│   │   warning:           #FF9F0A
│   │   error:             #FF3B30
│   │   info:              #0A84FF
│   └── Category tints (17 — from HAPluginCategory)
│         integrations: #5B8CFF,  ai: #BF5AF2,  cameras: #30B0C7 ...
│
├── Spacing
│   xs: 4,  sm: 8,  md: 12,  lg: 16,  xl: 24,  xxl: 32,  xxxl: 48
│
├── Radius
│   small: 8,  medium: 12,  large: 20,  xLarge: 28,  pill: 100
│
├── Typography   ← maps directly to Apple Dynamic Type
│   largeTitle,  title1, title2, title3
│   headline, subheadline, body
│   callout, footnote, caption1, caption2
│
└── Motion
      spring:     dampingRatio: 0.7, response: 0.4
      quick:      dampingRatio: 0.8, response: 0.25
      bouncy:     dampingRatio: 0.5, response: 0.5
      easeInOut:  duration: 0.35
```

### 4.2 Component Library

**Existing (Build 192):**

| Component | File | Status |
|-----------|------|--------|
| `liquidGlass()` | ViewModifiers.swift | ✅ Complete |
| `GlassCard` | Components/ | ✅ Complete |
| `HeavyGlassCard` | Components/ | ✅ Complete |
| `FloatingSpeedDial` | Components/ | ✅ Complete |
| `CameraCapture` | Features/Common/ | ✅ Complete |
| `PropertyHealthOrb` | Features/LivingTwin/ | ✅ Complete |

**To build (Phase 2+):**

| Component | Purpose | Priority |
|-----------|---------|----------|
| `PRVIOButton` | Standardized primary/secondary/ghost/destructive | High |
| `EntityRow` | Universal entity row (icon, name, state badge) | High |
| `PluginCard` | Marketplace card (icon, name, stars, badge, install btn) | High |
| `PRVIOSearchBar` | Animated search with filter chips | High |
| `SensorChart` | Swift Charts wrapper (line/bar, time range picker) | Medium |
| `CategoryGrid` | 2-column icon grid for category browsing | Medium |
| `StatCard` | Single metric card with trend indicator | Medium |
| `HealthBadge` | Color-coded health status chip | Medium |
| `PermissionAlert` | Standard permission request sheet | Medium |
| `EmptyStateView` | Consistent empty state (illustration + CTA) | Low |
| `PRVIOToast` | Non-blocking feedback (success/error/info) | Low |

### 4.3 Glass Design Rules

```
Surface hierarchy (top = least prominent):
  .ultraThinMaterial  ←  behind content (navigation bars, tab bar)
  .thinMaterial       ←  GlassCard default
  .regularMaterial    ←  HeavyGlassCard, modal sheets
  .thickMaterial      ←  overlay on live content (camera feed, map)
  .ultraThickMaterial ←  never use (opaque, defeats glass effect)

iOS 26 native glass:
  .glassEffect()                    ←  maps to ultraThinMaterial behavior
  .glassEffect(.regular)            ←  maps to GlassCard
  .glassEffect(.prominent)          ←  maps to HeavyGlassCard

Accessibility overrides (already implemented):
  reduceTransparency: ON  → opaque background fallback
  increaseContrast:   ON  → stronger border, higher contrast text
```

### 4.4 Dynamic Island

**Existing Live Activities (Build 192):**
- ShoppingActivity, MaintenanceActivity, DeliveryActivity, PlantCareActivity

**New: HAPluginActivity (Phase 2)**
- Triggers: doorbell ring, motion detected, alarm state change, device offline
- Compact: entity icon + state string
- Expanded: entity name, state, last changed, quick action button

**New: TwinHealthActivity (Phase 2)**
- Triggers: property health drops below threshold
- Compact: health orb color + score
- Expanded: top 3 critical alerts with tap-to-navigate

### 4.5 iPad & Mac Support

**iPad (Priority: Medium):**
```
NavigationSplitView
├── Sidebar (width: 320)
│   ├── Property selector
│   ├── Navigation items (mirroring tab bar)
│   └── Quick stats panel
├── Content (flexible)
│   └── Primary view for selected tab
└── Detail (optional, width: 360)
    └── Detail view (zone detail, plugin detail, task detail)
```

Adaptive layout breakpoints:
- compact width (iPhone): TabView (existing)
- regular width (iPad portrait): NavigationSplitView, 2-column grids
- regular width + regular height (iPad landscape): 3-column layouts

**Mac (Priority: Low):**
- Mac Catalyst with optimized idiom (not scaled-to-fit)
- Menu bar extra: property health status + quick actions
- Keyboard shortcuts: ⌘1-5 for tabs, ⌘F for search, ⌘N for new task
- Toolbar items replace tab bar

---

## 5. Navigation Architecture

### 5.1 Tab Structure

**Current (Build 192):** Home · Twin · Tasks · Chat · Settings

**Proposed (Phase 2):**

```
TabBar
├── Tab 1: Home          (house.fill)           — dashboard, health, quick actions
├── Tab 2: Twin          (cube.transparent.fill) — digital twin canvas
├── Tab 3: Marketplace   (square.grid.2x2.fill)  — NEW: plugin catalog + themes
├── Tab 4: Tasks         (checklist)             — maintenance tasks
└── Tab 5: Profile       (person.crop.circle)    — settings, account, HA instances
```

**Chat removed as a tab** — conversations with family members are accessible from Home (collaboration card) or from property members list. ARIA remains a floating button overlaid on all tabs.

**Marketplace** replaces the gap: currently there's no home for the HA Catalog we built. This gives it a permanent, discoverable location.

**Settings promoted to Profile** — combines current Settings + HA instance management + account switching.

### 5.2 Router Architecture

```
PRVIORouter (replaces AppRouter, same patterns)
├── selectedTab: AppTab
├── presentedSheet: SheetDestination?   ← single active sheet
│
├── enum AppTab: Int, Hashable
│     case home, twin, marketplace, tasks, profile
│
├── enum SheetDestination: Identifiable
│     case addTask(elementId: String?)
│     case addAppliance
│     case addPlant
│     case pluginDetail(HAPluginManifest)
│     case haInstanceSetup
│     case zoneDetail(PropertyZone)
│     case aria
│     case scan
│     case documentViewer(DocumentModel)
│     case expenseEntry
│     case waterPlant(Plant)
│
└── func navigate(to destination: NavigationDestination)
      — handles tab switch + optional sheet
      — deep link parsing: prvio://marketplace/plugin/{id}
      — Spotlight NSUserActivity continuation
      — Siri Shortcut intent routing
```

**Sheet discipline:**
- Only one sheet at a time (no `.sheet` inside `.sheet`)
- All sheets declared at `MainTabView` level via `PRVIORouter`
- Feature views use `@EnvironmentObject var router: PRVIORouter` + `router.present(.addTask())`
- Prevents iOS navigation stack corruption

### 5.3 Deep Link Map

```
prvio://home                        → Tab.home
prvio://twin                        → Tab.twin
prvio://twin/zone/{id}              → Tab.twin + expand ZoneDetail(id)
prvio://marketplace                 → Tab.marketplace
prvio://marketplace/plugin/{id}     → Tab.marketplace + PluginDetail(id)
prvio://marketplace/category/{slug} → Tab.marketplace + CategoryView(slug)
prvio://tasks                       → Tab.tasks
prvio://tasks/{id}                  → Tab.tasks + TaskDetail(id)
prvio://plants/{id}                 → Tab.home + WaterPlant(id) sheet
prvio://scan                        → Tab.home + ScanSheet
prvio://aria                        → ARIA sheet (any tab)
prvio://settings                    → Tab.profile
prvio://ha-instance/setup           → Tab.profile + HAInstanceSetup sheet
```

### 5.4 Hierarchy Rules

1. **No lateral navigation** — a view opened from Tab A cannot navigate to Tab B's content directly; it shows a link that switches tabs.
2. **No stacked sheets** — every sheet is a peer, never a child of another sheet.
3. **Back always works** — NavigationStack paths are typed (`NavigationPath`) and can be restored from deep links.
4. **iPad sidebar = tab bar** — the same `AppTab` enum drives both, no duplication.
5. **ARIA is always accessible** — floating button persists across all tabs, not gated behind a tab.

---

## 6. Marketplace

### 6.1 Information Architecture

```
MarketplaceView (Tab 3)
├── SearchBar (full-text across all plugins)
│
├── Featured Section           ← curated by PRVIO team (hardcoded plugin IDs)
│   └── HorizontalScroll of PluginCard (large format)
│
├── New & Updated              ← sorted by lastUpdated desc
│   └── HorizontalScroll of PluginCard (compact format)
│
├── Browse by Category         ← 17-cell grid of CategoryTile
│   └── → CategoryPluginListView
│         └── → PluginDetailView
│
├── Themes Gallery             ← category == .themes
│   └── ThemePreviewCard with live mock
│
├── Automation Blueprints      ← category == .automations, installType == .blueprint
│   └── BlueprintCard with import CTA
│
└── Installed Tab              ← secondary tab within Marketplace
    ├── Enabled plugins (toggle to disable)
    ├── Disabled plugins (toggle to enable)
    ├── Updates available (badge count)
    └── Filter by HA instance
```

### 6.2 PluginDetailView

```
PluginDetailView
├── Hero: icon, name, author (from githubUrl), stars, category badge
├── Status bar: installed / not installed / update available
├── Description (from manifest.description)
├── Tags chips (from manifest.tags)
├── Install button / Enable-Disable toggle / Update button
│     → triggers PluginEngine pipeline
├── Permissions required (list of PluginCapability icons)
├── Dependencies (collapsible: "Requires X, Y")
├── Links: GitHub, HACS, Docs, Website
├── Entity types provided (shown after install)
│     "This plugin adds: 3 sensors, 1 switch to your HA instance"
└── Reviews (from plugin_reviews table) — Phase 3
```

### 6.3 Theme Gallery

```
ThemeGalleryView
├── ThemePreviewCard
│   ├── Mock: mini room card with theme colors applied
│   ├── Name, author, stars
│   └── "Apply" button → ThemeInstallStrategy
│         → copies theme YAML to HA themes folder
│         → calls frontend.reload_themes service
│
└── Theme categories:
      Dark themes · Light themes · Retro · Minimal · Seasonal
```

### 6.4 Widget Gallery

Bridges HA entity data to PRVIO widget slots:

```
WidgetGalleryView
├── Available widget slots (from PRVIOWidgets):
│   DashboardWidget · TasksWidget · PlantsWidget · ShoppingWidget · LockScreenWidgets
│
├── HA data sources (from installed plugins + ha_entity_mappings):
│   sensor.temperature → numeric value
│   switch.* → on/off toggle
│   camera.* → live thumbnail
│
└── Configuration sheet:
    Pick widget slot → pick entity → preview → save
    → SharedDataStore.setWidgetConfig(slot, entityId)
    → WidgetCenter.reloadTimelines(ofKind: slot)
```

### 6.5 Search & Filtering

```
SearchState
├── query: String                     ← text input
├── activeCategory: HAPluginCategory? ← nil = all
├── activeInstallType: HAPluginInstallType? ← nil = all
├── hacsOnly: Bool                    ← filter to hacsCompatible == true
├── showInstalled: Bool               ← filter to installed set
│
└── results: [HAPluginManifest]
      computed from HAPluginRegistry.plugins(matching: query)
      + client-side filters applied on top
```

Local search is instant (no network). All 200 plugins in `plugins.json` + `plugins_extended.json` are loaded into `HAPluginRegistry.allPlugins` at startup.

---

## 7. Digital Twin Engine

### 7.1 Current Twin (Build 192)

```
TwinAggregator     ← collects PRVIO data → ZoneSnapshot[]
TwinHealthEngine   ← scores zones + property (0-100)
TwinCanvas         ← SwiftUI canvas with pan/zoom
TwinRenderer       ← layer-based rendering (property, rooms, objects, health, AI)
TwinHealthLayer    ← health orb animation
TwinAILayer        ← ARIA insights overlay
TwinAIInsightsView ← recommendation list
```

Data flow: Supabase → Services → TwinAggregator → Canvas render.
**Missing:** HA entities, real-time sensors, 3D USDZ, garden zones.

### 7.2 Extended Twin Engine

```
TwinEngine (new orchestrator — replaces direct TwinAggregator calls)
│
├── TwinAggregator          (existing — PRVIO native data)
├── HAEntityBridge          (NEW — HA WebSocket → entity state map)
│
├── TwinSyncService         (NEW — merges both sources into TwinState)
│   TwinState
│   ├── zoneSnapshots: [EnrichedZoneSnapshot]
│   │     ZoneSnapshot (existing) + HAEntityOverlay
│   │       haEntities: [HAEntitySnapshot]
│   │       temperature: Double?   ← from mapped sensor
│   │       humidity: Double?
│   │       motionDetected: Bool?
│   │       lightsOn: Bool?
│   │       energyW: Double?       ← live watt reading
│   ├── outdoorZones: [GardenZoneSnapshot]  ← NEW
│   ├── propertyHealthScore: Int
│   └── criticalAlerts: [TwinAlert]
│
├── TwinRenderer3D          (NEW — extends TwinCanvas with USDZ)
│   ├── 2D mode (existing canvas)     ← default, works on all devices
│   └── 3D mode (RealityKit + USDZ)  ← only if LiDAR scan exists
│         BlueprintService.usdzUrl → RealityView → zone tap detection
│
├── ZoneGraph               (NEW — zone relationships)
│   ├── edges: [(from: zoneId, to: zoneId, relation: ZoneRelation)]
│   ├── ZoneRelation: .above, .below, .adjacent, .contains
│   └── Used for: energy flow, sound propagation, ventilation display
│
└── TwinTimeSeriesEngine    (NEW — sensor history per zone)
    ├── Queries sensor_readings from Supabase (time range)
    ├── Caches last 24h in-memory
    └── Feeds SensorChart in TwinZoneDetailView
```

### 7.3 Garden & Outdoor Zones

Garden zones are `PropertyZone` instances with `layer: .property` (existing), extended with:

```
GardenZoneSnapshot
├── zone: PropertyZone
├── plants: [Plant]          ← plants geo-located in this zone
├── soilMoisture: Double?    ← from HA sensor (if mapped)
├── irrigationState: IrrigationState  ← from HA switch/script
│     .off | .active(endTime: Date) | .scheduled(next: Date)
├── weatherOverlay: WeatherCondition?  ← from HA weather entity
└── healthScore: Int         ← plants health average
```

### 7.4 Real-time Sensor Overlay

When an HA instance is connected and entity mappings exist, zone cards show live data:

```
ZoneCard (enhanced)
├── Name + health score (existing)
├── [if temperature mapped] 🌡 22.4°C
├── [if humidity mapped]    💧 48%
├── [if motion mapped]      🚶 Motion · 2 min ago
├── [if energy mapped]      ⚡ 340W live
└── [if light mapped]       💡 3 lights on
```

Refresh rate: WebSocket push from HA (near-real-time, ~1s latency).
Fallback: polling GET /api/states/{entity_id} every 30s when WebSocket unavailable.

### 7.5 Health Engine Extensions

Current scoring: Elements 40%, Tasks 25%, Docs 15%, Plants 10%, Warranties 10%.

Phase 2 additions:

```
TwinHealthEngine (extended)
├── HA connectivity penalty:
│     no HA instance configured: -0 (optional feature)
│     HA instance offline:       -5 points
│     plugins > 0 installed but HA offline: -8 points
│
├── Energy anomaly penalty:
│     energy reading > 150% of 30-day average: -5
│     no energy data in >7 days: -3
│
└── Security bonus:
      alarm armed + no alerts: +3
      all locks locked (if mapped): +2
```

---

## 8. Integration Map

How the 6 systems connect:

```
                    ┌─────────────────┐
                    │   Marketplace   │
                    │  (Tab 3 UI)     │
                    └────────┬────────┘
                             │ user taps Install
                             ▼
                    ┌─────────────────┐
                    │  Plugin Engine  │◄──── HAPluginRegistry (catalog)
                    │                 │
                    │  - Permission   │
                    │  - Dependency   │
                    │  - Install      │
                    │  - State        │
                    └───┬─────────┬───┘
                        │         │
         plugin installed         HA entity types unlocked
                        │         │
              ┌─────────▼─┐   ┌───▼──────────────┐
              │  Data     │   │  Digital Twin    │
              │  Layer    │   │  Engine          │
              │           │   │                  │
              │ - SyncEng │   │ - HAEntityBridge │
              │ - TimeSer │   │ - TwinSyncSvc    │
              │ - Supabase│   │ - Canvas/3D      │
              └─────┬─────┘   └───────┬──────────┘
                    │                 │
              ┌─────▼─────────────────▼──────────┐
              │         Design System             │
              │  PRVIOTokens · GlassCard ·        │
              │  EntityRow · PluginCard ·         │
              │  SensorChart · PRVIOButton        │
              └─────────────┬─────────────────────┘
                            │
              ┌─────────────▼─────────────────────┐
              │         Navigation                 │
              │   PRVIORouter · AdaptiveTabView ·  │
              │   DeepLinkHandler · SheetRouter    │
              └────────────────────────────────────┘

Event bus connections:
  PluginEngine → TwinEngine:    .pluginInstalled → refresh entity types
  TwinEngine → Marketplace:     .healthAlert → show relevant plugin suggestion
  DataLayer → Design System:    .entityStateChanged → EntityRow re-renders
  Navigation → all:             deepLink → tab switch + sheet open
```

---

## 9. Implementation Roadmap

### Build 193–194 · Design System Foundation

**Goal:** PRVIOTokens file + new components. No feature changes.

| Task | File | Notes |
|------|------|-------|
| Create `PRVIOTokens.swift` | Sources/Components/ | All hardcoded colors/spacing extracted |
| Create `PRVIOButton.swift` | Sources/Components/ | primary, secondary, ghost, destructive |
| Create `EntityRow.swift` | Sources/Components/ | generic row for any PRVIOEntity |
| Create `PRVIOSearchBar.swift` | Sources/Components/ | animated, filter-chip capable |
| Create `EmptyStateView.swift` | Sources/Components/ | reusable empty state |
| Create `PRVIOToast.swift` | Sources/Components/ | overlay notification |
| Audit + migrate hardcoded values | all Features/ | replace with tokens |

---

### Build 195–196 · Navigation Refactor

**Goal:** PRVIORouter + Marketplace tab + iPad split view.

| Task | File | Notes |
|------|------|-------|
| Rename AppRouter → PRVIORouter | Sources/App/ | add SheetDestination enum |
| Add `.marketplace` to AppTab | Sources/App/ | 5th tab replaces Chat or adds 6th |
| Create `MarketplaceView.swift` (shell) | Sources/Features/Marketplace/ | tabs: Browse, Installed |
| `AdaptiveNavigationView.swift` | Sources/App/ | TabView on iPhone, SplitView on iPad |
| Move Chat to Home collaboration card | Sources/Features/Home/ | or keep as tab |
| Deep link handler extension | Sources/App/ | add marketplace URLs |

---

### Build 197–198 · Marketplace + Plugin Engine Phase 2

**Goal:** Browsable catalog, plugin install flow (local + real HACS API).

| Task | File | Notes |
|------|------|-------|
| `PluginCard.swift` | Sources/Components/ | icon, name, stars, badge |
| `CategoryGridView.swift` | Sources/Features/Marketplace/ | 17-tile grid |
| `PluginDetailView.swift` | Sources/Features/Marketplace/ | hero, install, links |
| `PluginPermissionGate.swift` | Sources/Services/ | iOS permission requests |
| `PluginDependencyGraph.swift` | Sources/Services/ | DAG resolver |
| `HACSInstallStrategy.swift` | Sources/Services/PluginStrategies/ | real HACS API |
| `AddonInstallStrategy.swift` | Sources/Services/PluginStrategies/ | Supervisor API |
| `LovelaceInstallStrategy.swift` | Sources/Services/PluginStrategies/ | patch config |
| `ThemeInstallStrategy.swift` | Sources/Services/PluginStrategies/ | inject + reload |
| `PluginUpdateChecker.swift` | Sources/Services/ | BGAppRefreshTask |
| Supabase: `plugin_installations` | supabase/migrations/ | new table |

---

### Build 199–200 · HA Instance + Real Connection

**Goal:** Add HA instance from app, real WebSocket connection, entity mapping.

| Task | File | Notes |
|------|------|-------|
| `HAInstanceSetupView.swift` | Sources/Features/Profile/ | URL + token input |
| `HAHealthChecker.swift` | Sources/Services/ | GET /api/ validation |
| `HAWebSocketManager.swift` | Sources/Services/ | ws(s):// persistent conn |
| `HAEntityBridge.swift` | Sources/Services/ | state_changed → local model |
| `EntityMappingView.swift` | Sources/Features/Profile/ | map ha entity → zone |
| Supabase: `ha_instances`, `ha_entity_mappings` | supabase/migrations/ | new tables |

---

### Build 201–202 · Twin Sensor Overlay

**Goal:** Live HA sensor data on zone cards in Digital Twin.

| Task | File | Notes |
|------|------|-------|
| `TwinEngine.swift` | Sources/Features/LivingTwin/ | new orchestrator |
| `TwinSyncService.swift` | Sources/Services/ | merges PRVIO + HA |
| `EnrichedZoneSnapshot.swift` | Sources/Models/ | ZoneSnapshot + HAOverlay |
| Update `TwinZoneCard.swift` | Sources/Features/LivingTwin/ | show temp, humidity, lights |
| `SensorChart.swift` | Sources/Components/ | Swift Charts time series |
| `TwinTimeSeriesEngine.swift` | Sources/Services/ | historical sensor queries |
| Supabase: `sensor_readings` | supabase/migrations/ | partitioned table |

---

### Build 203–204 · ARIA Tool-Use (Phase 3 from original plan)

**Goal:** ARIA can execute actions, not just advise.

| Task | File | Notes |
|------|------|-------|
| Extend `aria-chat` edge function | supabase/functions/aria-chat/ | Claude `tools` param |
| Implement tool-use loop | supabase/functions/aria-chat/ | tool_result → continue |
| Tools: `create_task`, `add_appliance`, `mark_watered` | supabase/functions/ | first tools |
| Tools: `query_twin_health`, `schedule_maintenance` | supabase/functions/ | read tools |
| Tool: `search_plugin`, `install_plugin` | supabase/functions/ | Marketplace tool |
| Confirmation UI in ARIAView | Sources/Features/ARIA/ | show intent → confirm |
| Action feedback in TwinAIInsightsView | Sources/Features/LivingTwin/ | "Do it" button |

---

### Build 205–206 · Garden & Outdoor Twin

**Goal:** Garden zones in Twin with plant clusters, irrigation, soil sensors.

| Task | File | Notes |
|------|------|-------|
| `GardenZoneSnapshot.swift` | Sources/Models/ | outdoor zone model |
| `GardenTwinView.swift` | Sources/Features/LivingTwin/ | outdoor canvas section |
| `IrrigationCard.swift` | Sources/Features/ | irrigation status + manual control |
| HA: Irrigation Unlimited bridge | HAEntityBridge | map irrigation schedules |
| HA: soil moisture sensors | HAEntityBridge | map to GardenZone |

---

### Build 207–208 · 3D Twin (RoomPlan → Twin)

**Goal:** USDZ models from RoomPlan render in Twin canvas.

| Task | File | Notes |
|------|------|-------|
| `RoomScanView` save-as-zone | Sources/Features/Blueprints/ | create zone from USDZ |
| `TwinRenderer3D.swift` | Sources/Features/LivingTwin/ | RealityKit + USDZ |
| Zone tap detection in 3D | TwinRenderer3D | entity_id → PRVIORouter |
| 2D/3D mode toggle in canvas | LivingDigitalTwinView | toggle button |

---

### Build 209–210 · Proactive Engine (Phase 4 from original plan)

**Goal:** Background analysis, proactive notifications, widget with health trend.

| Task | File | Notes |
|------|------|-------|
| `ProactiveEngine.swift` | Sources/Services/ | orchestrator |
| Extend `TwinHealthEngine` | Sources/Features/LivingTwin/ | predictive rules |
| `BGAppRefreshTask` registration | Sources/App/ | com.prvio.proactive |
| `NotificationScheduler` extension | Sources/Services/ | proactive notif |
| New: `TwinHealthActivity` (Dynamic Island) | Sources/LiveActivities/ | health drop |
| Dashboard widget: health trend sparkline | Widgets/ | 7-day trend |

---

### Build 211+ · iPad & Mac Support

| Task | Notes |
|------|-------|
| `AdaptiveNavigationView` — SplitView for iPad | `horizontalSizeClass` adaptive |
| All grid views: 1-col iPhone → 2-col iPad → 3-col Mac | `adaptiveGridItem` |
| Mac Catalyst target | menu bar extra, keyboard shortcuts |
| Mac: menu bar status item | property health at a glance |

---

## Summary

| System | Status | Builds |
|--------|--------|--------|
| Design System Tokens | ⬜ Not started | 193-194 |
| Navigation Refactor | ⬜ Not started | 195-196 |
| Marketplace UI | ⬜ Not started | 197-198 |
| Plugin Engine (real API) | ⬜ Not started | 197-198 |
| HA Real Connection | ⬜ Not started | 199-200 |
| Twin Sensor Overlay | ⬜ Not started | 201-202 |
| ARIA Tool-Use | ⬜ Not started | 203-204 |
| Garden Twin | ⬜ Not started | 205-206 |
| 3D Twin | ⬜ Not started | 207-208 |
| Proactive Engine | ⬜ Not started | 209-210 |
| iPad & Mac | ⬜ Not started | 211+ |

**Current baseline: Build 192 · 220 Swift files · 20 Supabase tables · Plugin catalog built (Phase 1)**
