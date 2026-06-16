# PRVIO — Complete Product Backlog
**Version 1.0 · June 2026 · Build 192 baseline**

---

## How to Read This Backlog

**Impact** — value delivered to user: 🔴 High / 🟡 Medium / 🟢 Low  
**Effort** — engineering cost: XS (hours) · S (1-2 days) · M (3-5 days) · L (1-2 weeks) · XL (2-4 weeks)  
**Status** — ✅ Done · 🔨 Partial / stub · ⬜ Not started  
**Dep** — which items must be complete first

Items within each version are ordered: impact descending, effort ascending (best ROI first).

---

## Current State (Build 192)

The app is functional as a **manual property management tool**. Everything works without internet if Supabase is cached. The smart home layer (HA integration) and intelligence layer (ARIA tool-use, proactive engine) are stubs.

```
✅ Working today:
   Auth + onboarding, property CRUD, zones (polygon), elements/appliances
   Tasks + notifications, plants + watering reminders, documents + expiry
   Photo journal, supply lists, chat/messaging, financial tracking
   Living Digital Twin (2D canvas, health engine, AI insights layer)
   ARIA (chatbot — advises but cannot execute)
   Blueprints (RoomPlan LiDAR → USDZ), VisionCapture OCR (product labels)
   5 widget types, 4 Live Activities, Siri Shortcuts, Spotlight, deep links
   Family + multi-property, biometric lock, currency conversion

🔨 Stubs (models exist, no real API):
   HA Plugin Catalog (200 plugins catalogued, no install/connect)
   Plugin install strategies (declared, not implemented)
   HA WebSocket / REST connection (not implemented)

⬜ Not built:
   Marketplace UI, Plugin Engine, HA connection, Sensor overlay in Twin
   ARIA tool-use, Proactive engine, Garden twin, 3D twin
   Recurring tasks, Plant species DB, Energy dashboard
   Document OCR, Mortgage/utility tracker, iPad, Mac
```

---

## MVP (Build 192 — Shipped)

The current build IS the MVP. It proves the concept and is usable for real property management.

### MVP Feature Set

| # | Feature | Impact | Effort | Status |
|---|---------|--------|--------|--------|
| M1 | Auth — email login, session persistence, biometric lock | 🔴 | M | ✅ |
| M2 | Onboarding — property type, address, photo | 🔴 | M | ✅ |
| M3 | Property CRUD — create, edit, switch, multi-property | 🔴 | M | ✅ |
| M4 | Zones — polygon-based areas, health score, icons | 🔴 | L | ✅ |
| M5 | Property Elements — type, condition, location, zone link | 🔴 | L | ✅ |
| M6 | Appliances — warranty tracking, brand/model, OCR scan | 🔴 | M | ✅ |
| M7 | Maintenance Tasks — priority, due date, status, notifications | 🔴 | L | ✅ |
| M8 | Seasonal Checklists — pre-built per season | 🟡 | M | ✅ |
| M9 | Plants — health status, watering reminders, notifications | 🔴 | M | ✅ |
| M10 | Documents — storage, expiry alerts, criticality flags | 🔴 | M | ✅ |
| M11 | Photo Journal — tagged entries, photo upload | 🟡 | S | ✅ |
| M12 | Supply Lists — shared shopping, quantity, categories | 🟡 | M | ✅ |
| M13 | Financial Tracking — expenses, categories, budget | 🟡 | M | ✅ |
| M14 | Paint Colors — swatches, rooms, photo reference | 🟢 | S | ✅ |
| M15 | Chat / Messaging — property-scoped, reactions, stickers | 🟡 | M | ✅ |
| M16 | Family Members — roles (owner/manager/guest), invites | 🔴 | M | ✅ |
| M17 | Living Digital Twin — 2D canvas, pan/zoom, layers | 🔴 | XL | ✅ |
| M18 | Twin Health Engine — 5-factor score, color scale, alerts | 🔴 | L | ✅ |
| M19 | Twin AI Insights — ARIA recommendations overlay | 🔴 | L | ✅ |
| M20 | ARIA Chat — Claude-powered assistant (advice only) | 🔴 | L | ✅ |
| M21 | Blueprints — RoomPlan LiDAR scan → USDZ storage | 🟡 | L | ✅ |
| M22 | VisionCapture OCR — product label → brand/model/serial | 🟡 | M | ✅ |
| M23 | Widgets — Dashboard, Tasks, Plants, Shopping, Lock Screen | 🟡 | L | ✅ |
| M24 | Live Activities — Shopping, Maintenance, Delivery, PlantCare | 🟡 | M | ✅ |
| M25 | Siri Shortcuts + AppIntents — 6 intent types | 🟢 | M | ✅ |
| M26 | Spotlight Search — tasks + plants indexed | 🟢 | S | ✅ |
| M27 | HA Plugin Catalog — 200 plugins, models, registry | 🔴 | XL | ✅ |
| M28 | Currency conversion — live rates | 🟢 | S | ✅ |
| M29 | Property Value tracking — valuation history | 🟡 | S | ✅ |
| M30 | Delivery Tracking — shipment status | 🟢 | M | ✅ |

**MVP dependency graph:** M1 → M2 → M3 → (M4, M5, M6, M7, M9, M10) → M17 → M18 → M19 → M20

---

## V1 — Smart Home Foundation
**Target: Build 193–204 · ~10–14 weeks**  
**Theme: Make PRVIO genuinely useful for smart home owners. Connect HA. Ship Marketplace. Give ARIA hands.**

---

### V1.A — Design System (Builds 193–194)
*No new features — lowers bug rate, speeds all future development*

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 1.A1 | **PRVIOTokens.swift** — centralize all colors, spacing, radius, typography, motion | 🔴 | S | — |
| 1.A2 | **PRVIOButton** — primary / secondary / ghost / destructive variants | 🔴 | S | 1.A1 |
| 1.A3 | **EntityRow** — universal row for any PRVIOEntity (icon, name, state badge, chevron) | 🔴 | S | 1.A1 |
| 1.A4 | **EmptyStateView** — consistent empty state across all list screens | 🟡 | XS | 1.A1 |
| 1.A5 | **PRVIOToast** — non-blocking feedback overlay (success/error/info) | 🟡 | XS | 1.A1 |
| 1.A6 | **PRVIOSearchBar** — animated search with filter chips | 🟡 | S | 1.A1 |
| 1.A7 | Audit + migrate hardcoded values in all 220 files to use PRVIOTokens | 🟡 | M | 1.A1 |

---

### V1.B — Navigation Refactor (Build 195)
*Unblocks Marketplace, scales to 200+ screens*

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 1.B1 | **PRVIORouter** — typed `SheetDestination` enum, single sheet at a time | 🔴 | M | — |
| 1.B2 | **Marketplace tab** — replace or add Tab 3 (was Chat) | 🔴 | S | 1.B1 |
| 1.B3 | Move Chat to Home (collaboration card) | 🟡 | S | 1.B1 |
| 1.B4 | Deep link extension — add `prvio://marketplace/*`, `prvio://plugin/*` | 🟡 | S | 1.B1, 1.B2 |
| 1.B5 | **Zone templates in Onboarding** — auto-generate zones by property type | 🔴 | S | M3 |

> 1.B5 detail: house → [Living, Kitchen, Bedroom, Bathroom, Hall, Exterior]; apartment → [Living, Kitchen, Bedroom, Bathroom]; studio → [Main Room, Bathroom, Balcony]. One-tap, skippable.

---

### V1.C — Marketplace UI (Build 196–197)
*The catalog we built becomes a real browsable product*

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 1.C1 | **PluginCard component** — icon, name, stars, category badge, install state | 🔴 | S | 1.A1 |
| 1.C2 | **MarketplaceView** — shell with Browse/Installed tabs | 🔴 | M | 1.B2, 1.C1 |
| 1.C3 | **CategoryGridView** — 17-tile icon grid → plugin list | 🔴 | S | 1.C2 |
| 1.C4 | **PluginDetailView** — hero, description, tags, links, install button | 🔴 | M | 1.C2, 1.C1 |
| 1.C5 | **Marketplace search** — full-text on all 200 plugins, instant local | 🔴 | S | 1.C2, 1.A6 |
| 1.C6 | **Installed plugins view** — toggle enable/disable, per-HA-instance | 🔴 | M | 1.C2, 1.D1 |
| 1.C7 | **Theme gallery** — preview card with mock colors, apply button | 🟡 | M | 1.C2 |
| 1.C8 | Featured section — curated 8 plugins, horizontal scroll | 🟡 | S | 1.C2 |
| 1.C9 | New & Updated section — sorted by lastUpdated | 🟢 | XS | 1.C2 |

---

### V1.D — HA Connection (Build 198–199)
*The most critical unblock — everything smart home depends on this*

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 1.D1 | **HAInstanceSetupView** — URL + token input, validate, save | 🔴 | M | M27 |
| 1.D2 | **HA health check** — GET /api/ with Bearer token, show HA version | 🔴 | S | 1.D1 |
| 1.D3 | **Bonjour/mDNS discovery** — scan local network for `_home-assistant._tcp` | 🔴 | M | 1.D1 |
| 1.D4 | **HAWebSocketManager** — persistent ws(s):// connection, reconnect logic | 🔴 | L | 1.D1, 1.D2 |
| 1.D5 | **HAEntityBridge** — `state_changed` events → local `HAEntitySnapshot` | 🔴 | L | 1.D4 |
| 1.D6 | **Entity mapping UI** — assign HA entity_id to PRVIO zone | 🔴 | M | 1.D5 |
| 1.D7 | HA instance section in Profile tab — add/remove/set default | 🔴 | S | 1.D1 |
| 1.D8 | **Supabase: ha_instances, ha_entity_mappings tables** | 🔴 | S | 1.D1 |

---

### V1.E — Plugin Engine (Build 199–200)
*Real install/uninstall, not local-only stubs*

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 1.E1 | **PluginPermissionGate** — request iOS permissions per plugin capability | 🔴 | M | 1.C4 |
| 1.E2 | **PluginDependencyGraph** — DAG resolution, topological install order | 🔴 | M | M27 |
| 1.E3 | **HACSInstallStrategy** — POST /api/hacs/repository/download | 🔴 | M | 1.D4, 1.E2 |
| 1.E4 | **AddonInstallStrategy** — POST /api/hassio/addons/{slug}/install | 🔴 | M | 1.D4, 1.E2 |
| 1.E5 | **LovelaceInstallStrategy** — patch configuration.yaml resources | 🟡 | M | 1.D4 |
| 1.E6 | **ThemeInstallStrategy** — inject YAML + reload_themes | 🟡 | S | 1.D4 |
| 1.E7 | **BlueprintImportStrategy** — POST /api/blueprint/import | 🟡 | S | 1.D4 |
| 1.E8 | **PluginUpdateChecker** — BGAppRefreshTask, CDN version compare | 🟡 | M | 1.C2, 1.E3 |
| 1.E9 | Supabase: plugin_installations table | 🔴 | XS | 1.E3 |

---

### V1.F — Twin Sensor Overlay (Build 200–201)
*Twin shows live data from real home, not just manual entries*

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 1.F1 | **TwinEngine orchestrator** — merges PRVIO + HA into unified TwinState | 🔴 | M | 1.D5, 1.D6 |
| 1.F2 | **EnrichedZoneSnapshot** — ZoneSnapshot + HA overlay (temp, humidity, motion, lights, energy) | 🔴 | M | 1.F1 |
| 1.F3 | **Zone cards — live sensor data** — show 🌡💧🚶⚡ badges from HA entities | 🔴 | M | 1.F2 |
| 1.F4 | **SensorChart component** — Swift Charts time series, time range picker | 🔴 | M | 1.A1 |
| 1.F5 | Supabase: sensor_readings table (partitioned by month) | 🟡 | S | 1.F1 |
| 1.F6 | Energy dashboard — zone-level kWh, cost, 7-day chart | 🔴 | M | 1.F4, 1.F5 |
| 1.F7 | Twin Health — HA connectivity penalty in score formula | 🟡 | S | 1.F1 |

---

### V1.G — ARIA Tool-Use (Build 202–204)
*ARIA goes from chatbot to operator*

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 1.G1 | **aria-chat edge function: Claude tools param** — implement tool-use loop | 🔴 | L | M20 |
| 1.G2 | Tool: `create_task` — ARIA creates maintenance task | 🔴 | S | 1.G1 |
| 1.G3 | Tool: `mark_plant_watered` — ARIA logs watering | 🔴 | XS | 1.G1 |
| 1.G4 | Tool: `add_appliance` — ARIA adds appliance with details | 🔴 | S | 1.G1 |
| 1.G5 | Tool: `query_twin_health` — ARIA reads current health state | 🔴 | S | 1.G1, M18 |
| 1.G6 | Tool: `schedule_maintenance` — ARIA sets recurring task | 🔴 | S | 1.G1, 1.G7 |
| 1.G7 | **Recurring tasks** — recurrence field + scheduler | 🔴 | M | M7 |
| 1.G8 | Tool: `search_plugin` / `suggest_plugin` — ARIA recommends from catalog | 🟡 | S | 1.G1, M27 |
| 1.G9 | **Confirmation UI in ARIAView** — show proposed action before execution | 🔴 | M | 1.G1 |
| 1.G10 | "Do it" button in TwinAIInsightsView — insights become actionable | 🔴 | S | 1.G9 |

---

### V1.H — Quick Wins (any V1 build)
*High ROI, low effort — fill sprint gaps*

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 1.H1 | **Task assignment to family member** — assignee field + notification to them | 🔴 | S | M7, M16 |
| 1.H2 | **Document OCR scan** — photo → auto-fill document name/date/category | 🔴 | S | M22 |
| 1.H3 | **Warranty auto-extraction from invoice photo** — OCR → expiry date | 🔴 | S | M22 |
| 1.H4 | **TwinHealthActivity** — Dynamic Island drops when health score falls | 🟡 | M | M24, M18 |
| 1.H5 | **Mortgage tracker** — principal, rate, term, monthly payment calculator | 🟡 | M | M13 |
| 1.H6 | **Utility bill tracker** — meter readings, monthly trend | 🟡 | M | M13 |
| 1.H7 | Task templates — pre-built task sets (boiler service, AC filter, gutter clean) | 🟡 | S | M7 |
| 1.H8 | Plant species mini-database — 50 common species with care tips, watering intervals | 🟡 | M | M9 |
| 1.H9 | Maintenance cost tracker — link expenses to tasks | 🟡 | S | M7, M13 |
| 1.H10 | Property value trend chart — 12-month sparkline on Home | 🟢 | S | M29 |

---

### V1 Dependency Chain (critical path)

```
PRVIOTokens (1.A1)
  └─► PRVIORouter (1.B1)
        └─► Marketplace tab (1.B2)
              └─► MarketplaceView (1.C2)
                    └─► PluginDetailView (1.C4)

HA Instance Setup (1.D1)
  └─► HA Health Check (1.D2) ─► Bonjour Discovery (1.D3)
  └─► HAWebSocketManager (1.D4)
        └─► HAEntityBridge (1.D5)
              └─► Entity Mapping UI (1.D6)
                    └─► TwinEngine (1.F1)
                          └─► EnrichedZoneSnapshot (1.F2)
                                └─► Zone live badges (1.F3)

HA Connection (1.D4) + Dependency Graph (1.E2)
  └─► HACS Strategy (1.E3) ─► Addon Strategy (1.E4)
        └─► Plugin installations table (1.E9)

ARIA tools loop (1.G1)
  └─► create_task (1.G2), water_plant (1.G3), add_appliance (1.G4)
  └─► Confirmation UI (1.G9) ─► "Do it" button (1.G10)
```

---

## V2 — Advanced Intelligence
**Target: Build 205–216 · ~4–6 months post V1**  
**Theme: Proactive, predictive, 3D-aware, garden-smart. The app knows your home better than you do.**

---

### V2.A — Proactive Engine

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 2.A1 | **ProactiveEngine.swift** — BGAppRefreshTask analyzing TwinState | 🔴 | L | V1 complete |
| 2.A2 | Predictive maintenance rules — appliance age + type → failure risk | 🔴 | M | 2.A1 |
| 2.A3 | Warranty expiry proactive alert (30/7/1 day) | 🔴 | S | 2.A1 |
| 2.A4 | Seasonal task generator — auto-create checklists based on date + climate | 🔴 | M | 2.A1 |
| 2.A5 | Energy anomaly detection — >150% 30-day avg → alert + ARIA explanation | 🔴 | M | 2.A1, 1.F6 |
| 2.A6 | **Proactive ARIA suggestions** — push insight to ARIA inbox, not just on request | 🔴 | M | 2.A1, 1.G1 |
| 2.A7 | Estimated repair cost engine — appliance type + age + condition → cost range | 🟡 | L | 2.A2 |
| 2.A8 | Smart notification throttling — no more than 3 alerts/day, priority ranked | 🟡 | S | 2.A1 |

---

### V2.B — Garden & Outdoor Twin

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 2.B1 | **Garden zone type** — outdoor zone with plant cluster rendering | 🔴 | M | 1.F1 |
| 2.B2 | **Irrigation integration** — HA switch/script → irrigation state on garden card | 🔴 | M | 1.D5, 2.B1 |
| 2.B3 | Soil moisture sensor overlay — from HA sensor, shown on garden zone | 🔴 | M | 1.F2, 2.B1 |
| 2.B4 | Weather overlay — from HA weather entity, shown on outdoor zones | 🟡 | S | 1.D5 |
| 2.B5 | **Plant growth photo timeline** — series of zone photos, growth diff | 🟡 | M | M11 |
| 2.B6 | Garden seasonal tasks — spring prepare / autumn winterize auto-list | 🟡 | M | 2.B1, 2.A4 |
| 2.B7 | Plant compatibility checker — species A + species B, spacing guide | 🟢 | L | 1.H8 |
| 2.B8 | Pest/disease log per plant — photo + symptom tagging | 🟢 | M | M9 |

---

### V2.C — 3D Digital Twin

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 2.C1 | **RoomScan → Zone link** — after LiDAR scan, "Save as Zone" creates PropertyZone with USDZ | 🔴 | M | M21 |
| 2.C2 | **TwinRenderer3D** — RealityKit + USDZ rendering in Twin canvas | 🔴 | XL | 2.C1 |
| 2.C3 | Zone tap detection in 3D model — tapping 3D room opens ZoneDetailView | 🔴 | L | 2.C2 |
| 2.C4 | 2D/3D mode toggle — button in Twin canvas header | 🔴 | S | 2.C2 |
| 2.C5 | Element placement in 3D — drag appliance onto 3D room | 🟡 | XL | 2.C2, M5 |
| 2.C6 | Energy heatmap overlay in 3D — zone color = energy consumption | 🟡 | L | 2.C2, 1.F6 |

---

### V2.D — Security Layer

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 2.D1 | **HA alarm integration** — arm/disarm from Twin, state shown on Twin | 🔴 | M | 1.D5 |
| 2.D2 | **Camera feed in Twin** — Frigate/HA camera entity → thumbnail on zone | 🔴 | L | 1.D5 |
| 2.D3 | Motion alert → Live Activity — motion sensor → Dynamic Island | 🔴 | M | 1.D5, M24 |
| 2.D4 | Lock status in Twin — HA lock entity → shown on zone card | 🟡 | S | 1.D5 |
| 2.D5 | Security score in Twin Health — alarm armed + no alerts = bonus | 🟡 | S | 2.D1, M18 |
| 2.D6 | Visitor log — who entered, when, via which door (HA + NFC) | 🟡 | L | 2.D4 |

---

### V2.E — iPad Support

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 2.E1 | **AdaptiveNavigationView** — NavigationSplitView for iPad | 🔴 | L | 1.B1 |
| 2.E2 | 2-column grid layouts — CategoryGrid, PluginList, ZoneList | 🔴 | M | 2.E1 |
| 2.E3 | Split-view Twin + ZoneDetail — side-by-side on iPad landscape | 🔴 | L | 2.E1, M17 |
| 2.E4 | Drag & drop in Twin — rearrange elements on iPad | 🟡 | L | 2.E3 |
| 2.E5 | Keyboard shortcuts on iPad — ⌘F search, ⌘N new task, ⌘1-5 tabs | 🟡 | S | 2.E1 |

---

### V2.F — Energy Management

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 2.F1 | **Energy dashboard** — per-zone kWh, cost, monthly trend, top consumers | 🔴 | L | 1.F6 |
| 2.F2 | Solar production tracking — HA Solar integration → generation vs consumption | 🔴 | M | 1.D5, 2.F1 |
| 2.F3 | EV charging status — vehicle SOC, charge rate, estimated full time | 🟡 | M | 1.D5 |
| 2.F4 | Tariff-aware cost calculator — peak/off-peak rates, monthly bill projection | 🟡 | L | 2.F1 |
| 2.F5 | Energy export to CSV — 12-month history download | 🟢 | S | 2.F1 |

---

### V2.G — Family Intelligence

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 2.G1 | **Smart notifications** — alert only relevant member (who owns zone, who assigned task) | 🔴 | M | M16, 1.H1 |
| 2.G2 | Member activity feed — who watered what, who completed what (Home tab) | 🟡 | M | M16 |
| 2.G3 | Family dashboard — member presence, task ownership, plant responsibilities | 🟡 | M | M16 |
| 2.G4 | Property handover mode — list everything for new tenant/buyer | 🟡 | L | M3, M5, M10 |
| 2.G5 | Shared shopping — real-time supply list sync across family members | 🟡 | M | M12 |

---

### V2.H — ARIA Advanced

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 2.H1 | **ARIA can query HA state** — tool: `get_ha_entity_state(entity_id)` | 🔴 | M | 1.G1, 1.D5 |
| 2.H2 | ARIA can control HA devices — tool: `set_ha_entity_state(entity_id, state)` + confirmation | 🔴 | L | 2.H1 |
| 2.H3 | ARIA voice input — Speech.framework → text → ARIA request | 🟡 | M | M20 |
| 2.H4 | ARIA energy advisor — "You could save €X/month by scheduling Y" | 🟡 | L | 2.H1, 2.F1 |
| 2.H5 | ARIA learns home patterns — "You usually water plants on Sundays" | 🟡 | XL | 2.H1 |

---

### V2.I — Renovations & Documents

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 2.I1 | **Renovation timeline** — project, contractor, cost, before/after photos | 🔴 | L | M5, M13 |
| 2.I2 | **Insurance document analysis** — OCR + extract coverage, premium, expiry | 🔴 | M | 1.H2 |
| 2.I3 | Contractor directory — contacts linked to tasks and renovations | 🟡 | M | 2.I1 |
| 2.I4 | ROI calculator — renovation cost vs property value lift | 🟡 | M | 2.I1, M29 |
| 2.I5 | Document version history — replace expired document, keep history | 🟢 | S | M10 |

---

### V2 Dependency Chain

```
V1 complete (especially 1.D5 HAEntityBridge, 1.G1 ARIA tools)
  │
  ├─► ProactiveEngine (2.A1)
  │     └─► Predictive maintenance (2.A2)
  │     └─► Energy anomaly (2.A5) ── needs 1.F6
  │     └─► Proactive ARIA (2.A6)
  │
  ├─► RoomScan→Zone (2.C1) ──► TwinRenderer3D (2.C2) ──► Zone tap 3D (2.C3)
  │
  ├─► Garden zone type (2.B1) ──► Irrigation (2.B2), Soil moisture (2.B3)
  │
  ├─► HA alarm (2.D1), Camera feed (2.D2), Motion alert (2.D3)
  │
  ├─► Energy dashboard (2.F1) ──► Solar (2.F2), EV (2.F3), Tariff (2.F4)
  │
  └─► ARIA HA state query (2.H1) ──► ARIA device control (2.H2)
```

---

## V3 — Platform
**Target: Build 217+ · ~6–12 months post V2**  
**Theme: PRVIO becomes a platform — third-party plugins, Mac, API, marketplace monetization.**

---

### V3.A — Mac Support

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 3.A1 | Mac Catalyst target — optimized idiom (not scaled) | 🔴 | XL | V2 complete |
| 3.A2 | Menu bar extra — property health status, quick actions | 🔴 | M | 3.A1 |
| 3.A3 | Keyboard shortcuts — ⌘1-5 tabs, ⌘F search, ⌘N new | 🟡 | S | 3.A1 |
| 3.A4 | Toolbar items — replace tab bar on Mac | 🟡 | M | 3.A1 |
| 3.A5 | Mac-native windows — resizable, multiple windows for multi-property | 🟡 | L | 3.A1 |

---

### V3.B — Marketplace Monetization

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 3.B1 | Plugin ratings & reviews — 1-5 stars, text, verified installs | 🔴 | M | 1.E9 |
| 3.B2 | Curated collections — "Best for energy saving", "Security starter pack" | 🟡 | S | V1 Marketplace |
| 3.B3 | Premium plugin tier — paid plugins with StoreKit IAP | 🟡 | XL | 3.B1 |
| 3.B4 | PRVIO-certified plugins — badge for tested integrations | 🟡 | M | 3.B1 |

---

### V3.C — Automation Builder

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 3.C1 | **Automation templates browser** — import blueprints from catalog | 🔴 | L | 1.E7 |
| 3.C2 | Visual automation builder — trigger → condition → action node editor | 🔴 | XL | 1.D4 |
| 3.C3 | PRVIO automation types — "When plant needs water, notify assigned member" | 🔴 | L | 1.G1, 3.C1 |
| 3.C4 | Automation history — log of triggered automations | 🟡 | M | 3.C2 |
| 3.C5 | ARIA creates automations — "When I leave home, lock all locks" | 🟡 | L | 3.C2, 2.H2 |

---

### V3.D — Third-Party Integrations

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 3.D1 | **PRVIO API** — REST API for third-party apps to read Twin state | 🔴 | XL | V2 |
| 3.D2 | Matter / Thread — native iOS 16 Matter support (not via HA) | 🔴 | XL | 1.D4 |
| 3.D3 | HomeKit bridge — PRVIO property elements ↔ HomeKit | 🟡 | XL | 3.D1 |
| 3.D4 | Google Home integration — import device list | 🟢 | L | 3.D1 |
| 3.D5 | AirBnB / booking platform link — guest access, check-in automation | 🟢 | XL | 2.G4 |

---

### V3.E — Advanced Garden

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 3.E1 | **Garden plan / layout editor** — draw beds, place plants in 2D | 🔴 | XL | 2.B1 |
| 3.E2 | Plant compatibility matrix — 200 species, companion planting | 🟡 | L | 1.H8 |
| 3.E3 | Harvest tracker — crop yield, date, quantity | 🟢 | M | 2.B1 |
| 3.E4 | Garden camera timelapse — from Frigate, zone-linked | 🟢 | L | 2.D2 |

---

### V3.F — Financials Advanced

| # | Feature | Impact | Effort | Dep |
|---|---------|--------|--------|-----|
| 3.F1 | Tax document organizer — categorize expenses for tax return | 🟡 | M | M13 |
| 3.F2 | Carbon footprint tracker — energy consumption → CO₂ → offset suggestions | 🟡 | L | 2.F1 |
| 3.F3 | Market comparison — local property price trends (API: Zillow/Rightmove) | 🟡 | L | M29 |
| 3.F4 | Rental income tracker — tenant, rent, payment history | 🟢 | M | M3 |

---

## Dependency Map (Cross-Version)

```
AUTH (M1)
  └─► Everything

PROPERTY (M3)
  └─► ZONES (M4) ─► TWIN CANVAS (M17) ─► HEALTH ENGINE (M18) ─► ARIA (M20)
                                               │
                                               └─► PROACTIVE ENGINE (2.A1)

HA CATALOG (M27)
  └─► MARKETPLACE UI (1.C2) ─► PLUGIN DETAIL (1.C4) ─► REVIEWS (3.B1)
  └─► HA INSTANCE (1.D1)
        └─► HA WEBSOCKET (1.D4)
              └─► ENTITY BRIDGE (1.D5)
                    └─► ENTITY MAPPING (1.D6)
                    └─► TWIN SENSOR OVERLAY (1.F1, 1.F2, 1.F3)
                    └─► ALARM (2.D1), CAMERA (2.D2), LOCK (2.D4)
                    └─► ENERGY (2.F1) ─► SOLAR (2.F2), EV (2.F3)
                    └─► ARIA HA QUERY (2.H1) ─► ARIA CONTROL (2.H2)
        └─► PLUGIN ENGINE REAL (1.E3) ─► UPDATE CHECKER (1.E8)

VISION OCR (M22)
  └─► DOC OCR (1.H2) ─► INSURANCE ANALYSIS (2.I2)
  └─► WARRANTY EXTRACTION (1.H3)

ROOMPLAN (M21)
  └─► ROOMSCAN→ZONE (2.C1) ─► 3D TWIN (2.C2) ─► 3D INTERACTION (2.C3)

ARIA (M20)
  └─► TOOL-USE LOOP (1.G1)
        └─► ALL ARIA TOOLS (1.G2–1.G8)
        └─► ARIA HA QUERY (2.H1) ─► ARIA CONTROL (2.H2)
        └─► PROACTIVE ARIA (2.A6)
        └─► AUTOMATION CREATOR (3.C5)

IPAD NAV (2.E1)
  └─► 2-COL GRIDS (2.E2) ─► SPLIT TWIN (2.E3)
  └─► MAC CATALYST (3.A1)
```

---

## Impact × Effort Matrix

### Quadrant 1 — Do First (High Impact, Low Effort)

| Item | Impact | Effort | Version |
|------|--------|--------|---------|
| Zone templates in Onboarding | 🔴 | XS | V1.B5 |
| PRVIOTokens.swift | 🔴 | S | V1.A1 |
| Document OCR scan | 🔴 | S | V1.H2 |
| Warranty auto-extraction | 🔴 | S | V1.H3 |
| Task assignment to family | 🔴 | S | V1.H1 |
| Task templates | 🟡 | S | V1.H7 |
| Maintenance cost tracker | 🟡 | S | V1.H9 |
| HA Health Check | 🔴 | S | V1.D2 |
| Recurring tasks | 🔴 | M | V1.G7 |
| Entity mapping UI | 🔴 | M | V1.D6 |
| Theme install strategy | 🟡 | S | V1.E6 |

### Quadrant 2 — Schedule (High Impact, Medium Effort)

| Item | Impact | Effort | Version |
|------|--------|--------|---------|
| HA Instance Setup UI | 🔴 | M | V1.D1 |
| MarketplaceView | 🔴 | M | V1.C2 |
| PluginDetailView | 🔴 | M | V1.C4 |
| ARIA tool-use loop | 🔴 | L | V1.G1 |
| Confirmation UI ARIA | 🔴 | M | V1.G9 |
| TwinEngine orchestrator | 🔴 | M | V1.F1 |
| Zone live sensor badges | 🔴 | M | V1.F3 |
| Plant species database | 🟡 | M | V1.H8 |
| Energy dashboard | 🔴 | L | V2.F1 |
| Predictive maintenance | 🔴 | M | V2.A2 |
| HA alarm integration | 🔴 | M | V2.D1 |
| Smart notifications | 🔴 | M | V2.G1 |

### Quadrant 3 — Big Bets (High Impact, High Effort)

| Item | Impact | Effort | Version |
|------|--------|--------|---------|
| HAWebSocketManager | 🔴 | L | V1.D4 |
| HACS Install Strategy | 🔴 | M | V1.E3 |
| 3D Twin (RealityKit) | 🔴 | XL | V2.C2 |
| iPad NavigationSplitView | 🔴 | L | V2.E1 |
| ProactiveEngine | 🔴 | L | V2.A1 |
| Camera feed in Twin | 🔴 | L | V2.D2 |
| Automation builder | 🔴 | XL | V3.C2 |
| PRVIO API | 🔴 | XL | V3.D1 |
| Mac Catalyst | 🔴 | XL | V3.A1 |

### Quadrant 4 — Defer or Cut (Low Impact, High Effort)

| Item | Impact | Effort | Note |
|------|--------|--------|------|
| Garden plan layout editor | 🟢 | XL | V3, only for serious gardeners |
| AirBnB integration | 🟢 | XL | V3, very niche |
| Matter native (not via HA) | 🟡 | XL | V3, duplicates HA capability |
| Carbon footprint tracker | 🟡 | L | V3, low demand |
| Harvest tracker | 🟢 | M | V3, very niche |

---

## What We Are NOT Building

| Feature | Reason |
|---------|--------|
| Custom HA automation scripting (Python/YAML) | HA is better at this — PRVIO wraps it |
| Full HA Lovelace dashboard editor in-app | Scope creep — use HA frontend |
| Smart thermostat brand-specific apps | Too fragmented — route through HA |
| Property marketplace / listing | Different product (Zillow territory) |
| IoT device firmware updates in-app | Security risk, vendor territory |
| Custom Map tile renderer | Apple Maps covers this |
| In-app video calls with contractors | Zoom/FaceTime does this better |

---

## Summary Table

| Version | Theme | Builds | Weeks | New Features |
|---------|-------|--------|-------|--------------|
| MVP | Manual property management | ~1–192 | Done | 30 features ✅ |
| **V1** | **Smart home foundation** | **193–204** | **10–14** | **48 features** |
| V2 | Advanced intelligence | 205–216 | 16–24 | 42 features |
| V3 | Platform | 217+ | 24–48 | 28 features |

**V1 is the version that transforms PRVIO from a capable manual tool into an intelligent smart home platform. Everything in V1 unlocks V2. V1 should ship before any V2 work starts.**
