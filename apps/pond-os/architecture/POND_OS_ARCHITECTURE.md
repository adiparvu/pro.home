# Pond OS — Architecture
**Module of PRVIO · June 2026 · No existing code modified**

---

## Integration Philosophy

Pond OS **does not modify any existing PRVIO file**. It extends the platform through:

1. **New Supabase tables** — alongside existing ones, linked via `property_id`
2. **New Swift services** — same `@MainActor ObservableObject` pattern as `PropertyZoneService`
3. **New Swift models** — same `Codable + Identifiable` pattern as `PropertyElement`
4. **Extension on `TwinHealthEngine`** — Swift extension in `PondHealthEngine.swift`, no modification to original
5. **New entries in HA catalog** — `pond_plugins.json` (10 plugins for ESPHome/HA/Frigate)
6. **New ESPHome configs** — drop-in node for DS18B20 + HC-SR04 + Atlas Scientific EZO sensors

No tab is added to the app. Pond OS is accessible from the property Home tab (if ponds exist).

---

## Layer Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                        PRVIO iOS App                              │
│                                                                   │
│   Existing:                    Pond OS (new, no conflicts):       │
│   ┌────────────────────┐       ┌──────────────────────────────┐  │
│   │ MainTabView        │       │ PondDashboardView            │  │
│   │ LivingDigitalTwin  │──────►│ PondDigitalTwinView          │  │
│   │ TwinHealthEngine   │◄──ext─│ PondHealthEngine             │  │
│   │ SensorChart        │◄──use─│ WaterQualityCenter           │  │
│   │ GlassCard/liquidGl │◄──use─│ FishManagementView           │  │
│   │ NotificationSched. │◄──use─│ FeedingSystem                │  │
│   │ HAEntityBridge     │◄──use─│ WaterQualityService          │  │
│   │ AppRouter/sheets   │◄──use─│ PondService / FishService    │  │
│   └────────────────────┘       └──────────────────────────────┘  │
│                                                                   │
│   ┌──────────────────────────────────────────────────────────┐   │
│   │                 Supabase (shared client)                  │   │
│   │  Existing: properties, property_zones, sensor_readings    │   │
│   │  New:      ponds, pond_zones, pond_equipment,             │   │
│   │            water_quality_readings, pond_alerts,           │   │
│   │            fish_populations, fish_journal,               │   │
│   │            feeding_schedules, feeding_logs               │   │
│   └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼─────────────────────┐
         ▼                    ▼                     ▼
  ┌─────────────┐    ┌────────────────┐    ┌──────────────────┐
  │  ESPHome    │    │ Home Assistant │    │     Frigate      │
  │  (pond node │    │  WebSocket     │    │  (pond cameras,  │
  │  DS18B20    │───►│  + HACS        │───►│   heron detect,  │
  │  EZO pH/DO  │    │  + MQTT        │    │   motion zones)  │
  │  turbidity) │    └────────────────┘    └──────────────────┘
  └─────────────┘
```

---

## 6 Modules

### 1. Pond Dashboard

Entry point for all pond data. Accessed from Home tab when `ponds.count > 0`.

```
PondDashboardView
├── Pond selector (if multiple ponds)
├── Health Orb — PondHealthEngine.score() → 0–100
│     Reuses: PropertyHealthOrb pattern (parameterized)
├── Water Quality Cards (7 parameters)
│     Reuses: GlassCard + SensorChart
│     Parameters: temp, pH, DO, turbidity, salinity, conductivity, level
├── Live Equipment Status
│     Pump ✅ | Filter ✅ | Aerator ✅ | UV ⚠️ off
│     Data source: HAEntityBridge → PondEquipment.isRunning
├── Active Alerts banner (PondAlert.severity == .critical)
├── Last Feeding — FeedingService.lastFeedingTime()
└── Quick Actions: + Add Reading, Feed Now, Add Fish
```

**Reuses:** `GlassCard`, `liquidGlass()`, `SensorChart` (V1.F4), `PRVIOTokens`  
**New:** `PondDashboardView.swift`, `WaterParameterCard.swift`

---

### 2. Pond Digital Twin

Top-down 2D view of the pond. Zones, equipment, fish density — all as overlays on a pond shape.

```
PondDigitalTwinView
├── Pond Canvas (SwiftUI Canvas)
│     Shape: SVG path or oval/rect approximation
│     Background: gradient blue (depth-shaded: shallow=light, deep=dark)
│
├── Zone Layer (PondZone markers)
│     Circle overlays with zone color + icon (tap → zone detail)
│
├── Equipment Layer (PondEquipment markers)
│     Each equipment type has SF Symbol icon
│     Tap → equipment detail sheet (status, maintenance date, HA entity)
│     Running status: green glow = on, grey = off
│
├── Sensor Overlay (live readings)
│     Temperature badge at sensor position
│     DO badge at aerator position
│     pH badge at filter zone
│
├── Fish Density Heatmap (optional)
│     Color-coded by estimated fish/m² density
│
└── Camera Layer
      If Frigate camera mapped → live thumbnail in corner
```

**Reuses:** `TwinCanvas` rendering pattern, `liquidGlass()`, `GlassCard`  
**New:** `PondDigitalTwinView.swift` — does NOT modify `TwinCanvas.swift`

The Pond Digital Twin is a **self-contained SwiftUI view** using `Canvas` and `ZStack`. It does not inherit from or extend `TwinCanvas` — it borrows the visual language.

---

### 3. Fish Management

```
FishManagementView
├── Population Overview
│     Total fish count, biomass estimate, species count
│     FishService.totalFishCount, estimatedBiomassKg()
│
├── Species Grid (per-species card)
│     Icon, common name, latin name, count, avg size
│     FishPopulation + FishService.builtInSpecies lookup
│
├── Add Fish sheet
│     Species picker (search from FishService.builtInSpecies)
│     Count, color variety, source notes
│
├── Journal (FishJournalEntry list)
│     Timeline sorted by recordedAt
│     Icons per event type (FishEvent.icon/color)
│
└── Log Event sheet
      Event picker (stocking/harvest/disease/treatment/observation…)
      Count, species, notes, photo
```

**Reuses:** `GlassCard`, `PRVIOSearchBar`, photo upload pattern from `PhotoJournalService`  
**New:** `FishManagementView.swift`, `FishJournalView.swift`

---

### 4. Water Quality Center

```
WaterQualityCenter
├── Parameter tabs (all 12 parameters)
│
├── Per-parameter view:
│     Current value badge + healthy range bar
│     SensorChart (7d / 30d / 90d)
│     Last updated + source (manual/ESPHome/HA)
│     "Add Reading" button
│
├── History table (WaterQualityReading list)
│     Date, value, parameter, source icon
│
├── Alerts section (PondAlert list)
│     Sorted by severity
│     Acknowledge button
│
└── AI Prediction panel (Phase 2)
      WaterQualityService.predictNextDay()
      "pH likely to drop tomorrow due to high temps"
      Powered by ARIA tool: predict_water_quality
```

**Reuses:** `SensorChart` (V1.F4), `TwinAlert` display pattern, `GlassCard`  
**New:** `WaterQualityCenter.swift`, `WaterParameterDetailView.swift`

---

### 5. Feeding System

```
FeedingSystemView
├── Schedule List
│     FeedingSchedule cards: time, food type, amount, on/off toggle
│     Next feeding countdown
│
├── Add Schedule sheet
│     TimePicker, FoodType picker, amount slider (0–200g)
│     HA feeder entity picker (from ha_entity_mappings)
│     Days of week selector
│
├── Feed Now button
│     Manual log: FeedingService.logManualFeeding()
│     If haFeederEntityId set: also calls FeedingService.triggerHAFeeder()
│
├── Consumption Chart
│     Weekly grams per food type (bar chart — Swift Charts)
│     FeedingService.weeklyFoodConsumptionGrams()
│
└── Feeding Log (last 30 entries)
      fed_at, amount, type, source icon (manual/auto/ARIA)
```

**Reuses:** `NotificationScheduler` patterns (same `UNCalendarNotificationTrigger`)  
**New:** `FeedingSystemView.swift`

---

### 6. Integrations

How Pond OS connects to the HA ecosystem:

#### ESPHome → HA → HAEntityBridge → Pond OS

```
ESPHome pond_sensors.yaml
  │ native API (auto-discovery)
  ▼
Home Assistant
  sensor.pond_water_temperature   → WaterParameter.temperature
  sensor.pond_ph                  → WaterParameter.ph
  sensor.pond_dissolved_oxygen    → WaterParameter.dissolvedOxygen
  sensor.pond_turbidity           → WaterParameter.turbidity
  sensor.pond_conductivity        → WaterParameter.conductivity
  sensor.pond_water_level         → WaterParameter.waterLevel
  sensor.pond_orp                 → WaterParameter.orp
  switch.pond_main_pump           → PondEquipment.isRunning (pump)
  switch.pond_aerator             → PondEquipment.isRunning (aerator)
  switch.pond_uv_sterilizer       → PondEquipment.isRunning (uv)
  switch.pond_auto_feeder         → FeedingService.triggerHAFeeder()
  binary_sensor.pond_overflow     → PondAlert (critical)
  │
  │ WebSocket (HAWebSocketManager — existing V1.D4)
  ▼
HAEntityBridge.syncFromHA()
  │ maps entity_id → WaterParameter via ha_entity_mappings.pond_id
  ▼
WaterQualityService.syncFromHA()
  │ writes to water_quality_readings
  ▼
PondDashboardView (live update via @Published)
```

#### MQTT Alternative Path (for Node-RED / non-HA setups)

```
pond_controller.yaml (ESPHome MQTT publish)
  │ topic: pond/{device}/telemetry
  ▼
Mosquitto MQTT Broker (HA addon)
  │ HA MQTT sensor platform
  ▼
Same path as above via HAEntityBridge
```

#### Frigate Camera Integration

```
Frigate (HA addon)
  │ Pond zone defined in frigate.yml: zones: {pond_zone: {coordinates: ...}}
  ▼
MQTT events: frigate/events/detect → payload: {label: "bird", zone: "pond_zone"}
  │ HA automation: Frigate event → notify PRVIO
  ▼
HAEntityBridge binary_sensor.pond_heron_detected
  │
  ▼
PondAlert(severity: .critical, title: "Predator detected", message: "Heron near pond")
```

#### ReefPi Integration

```
ReefPi (Raspberry Pi)
  │ REST API → HACS reef-pi-hass integration
  ▼
HA sensors + switches (temperature, pumps, dosing)
  │ Same path as ESPHome via HAEntityBridge
  ▼
WaterQualityService / PondEquipment
```

---

## Data Model Relationships

```
Property (existing)
  └─► Pond (new, property_id FK)
        ├─► PondZone[] (pond_id FK)
        ├─► PondEquipment[] (pond_id FK) ← HA entity_id links to ha_entity_mappings
        ├─► WaterQualityReading[] (pond_id FK, partitioned by month)
        ├─► PondAlert[] (pond_id FK)
        ├─► FishPopulation[] (pond_id FK) → FishSpecies (built-in catalog)
        ├─► FishJournalEntry[] (pond_id FK)
        ├─► FeedingSchedule[] (pond_id FK)
        └─► FeedingLog[] (pond_id FK)

ha_entity_mappings (existing, V1.D8)
  └── pond_id column ADDED (nullable) ← ALTER TABLE, no breaking change
      Maps HA entity_id to a specific Pond for WaterQualityService
```

---

## ARIA Integration (Phase 2)

New ARIA tools for Pond OS (added to aria-chat edge function, no modification to existing tools):

| Tool | Input | Output |
|------|-------|--------|
| `query_pond_health` | pond_id | PondHealthSnapshot as JSON |
| `get_water_quality` | pond_id, parameter? | Latest readings |
| `check_fish_status` | pond_id | Population + recent journal |
| `log_manual_reading` | pond_id, parameter, value | Confirmation |
| `schedule_feeding` | pond_id, hour, minute, amount_grams | FeedingSchedule created |
| `add_fish_journal` | pond_id, event, count, notes | FishJournalEntry created |
| `predict_water_quality` | pond_id | 24h forecast per parameter |

ARIA example:
> "pH-ul iazului meu a scăzut ieri la 6.2. Ce fac?"  
> → ARIA: `query_pond_health` → `get_water_quality(ph)` → explains cause (CO2, rain, algae) → recommends buffer dose → `schedule_maintenance` task to check KH

---

## Health Scoring (No TwinHealthEngine modification)

```swift
// PondHealthEngine.swift — Swift extension, zero coupling:

extension TwinHealthEngine {
    static func includingPondScore(
        baseScore: Int,
        pondSnapshots: [PondHealthSnapshot]
    ) -> Int {
        // Pond contributes 10% to property health if ponds exist
        let avgPondScore = pondSnapshots.reduce(0) { $0 + $1.overallScore } / pondSnapshots.count
        return Int(Double(baseScore) * 0.90 + Double(avgPondScore) * 0.10)
    }
}
```

Call site in `TwinAggregator.refresh()`:
```swift
// Add ONE line to TwinAggregator.refresh() — minimal footprint:
propertyHealthScore = TwinHealthEngine.includingPondScore(
    baseScore: rawScore,
    pondSnapshots: pondSnapshots
)
```

---

## Navigation (No new tabs)

```
Home Tab
  └─► "Your Ponds" card (shown if ponds.count > 0)
        └─► PondDashboardView (pushed on NavigationStack)
              ├─► [Digital Twin button] → PondDigitalTwinView
              ├─► [Water Quality] → WaterQualityCenter
              ├─► [Fish] → FishManagementView
              └─► [Feeding] → FeedingSystemView

Marketplace Tab (existing)
  └─► Category: "Pond & Water" (filtered from pond_plugins.json)
        └─► ESPHome Pond, ReefPi, Frigate, Seneye, etc.

Twin Tab (existing)
  └─► Property health orb (if pond exists, score includes pond)
  └─► Zone card for pond (if pond assigned to a PropertyZone)
```

No new tab. Pond OS appears organically within the existing navigation.

---

## Phase Plan

### Phase 1 (current — foundation)
- ✅ `PondModels.swift` — all data types
- ✅ `PondService.swift` — CRUD + equipment + zones
- ✅ `WaterQualityService.swift` — readings + alerts + HA sync
- ✅ `FishService.swift` — populations + species catalog + journal
- ✅ `FeedingService.swift` — schedules + logs + HA feeder trigger
- ✅ `PondHealthEngine.swift` — scoring + TwinHealthEngine extension
- ✅ `pond_sensors.yaml` — ESPHome DS18B20 + HC-SR04 + EZO + turbidity
- ✅ `pond_controller.yaml` — ESPHome local automation + MQTT
- ✅ `pond_os_migration.sql` — 9 tables + RLS + partitioning
- ✅ `pond_plugins.json` — 10 ecosystem plugins
- ✅ `POND_OS_ARCHITECTURE.md` — this document

### Phase 2 (UI — SwiftUI views)
- [ ] `PondDashboardView.swift` — main dashboard
- [ ] `PondDigitalTwinView.swift` — top-down canvas
- [ ] `WaterParameterCard.swift` — per-parameter mini card
- [ ] `WaterQualityCenter.swift` — full quality center
- [ ] `FishManagementView.swift` — species + journal
- [ ] `FeedingSystemView.swift` — schedules + logs
- [ ] `AddPondSheet.swift` — create pond wizard
- [ ] `PondEquipmentDetailSheet.swift`

### Phase 3 (AI + real-time)
- [ ] ARIA tools: `query_pond_health`, `predict_water_quality`, `schedule_feeding`
- [ ] Frigate zone mapping for pond camera alerts
- [ ] Live Activity: water quality alert on Dynamic Island
- [ ] Proactive: pH dropping trend → alert before it becomes critical
