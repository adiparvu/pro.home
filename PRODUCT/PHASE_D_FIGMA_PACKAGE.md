# PHASE D — FIGMA MASTER PACKAGE
## PRV HOUSE — The Property Operating System
### Figma-Ready Specification for Every Screen

**Version:** 1.0  
**Status:** Active  
**Depends on:** Phase A, Phase B, Phase C

---

## HOW TO USE THIS DOCUMENT

This package is the handoff specification for translating Phase B screen designs and Phase C design system tokens into a production Figma file. Every section maps to a Figma page, frame, component, or variable.

Each screen entry contains:
- **Frame** — dimensions and grid settings
- **Layers** — exact layer tree with naming convention
- **Components** — which design system components appear and their variant states
- **Variables** — which token variables are applied
- **Prototype** — connection flows, trigger, animation, destination
- **Notes** — implementation edge cases and designer guidance

---

## D0 — FIGMA FILE ARCHITECTURE

### File Structure

```
PRV HOUSE — Design System & Screens.fig
│
├── 📁 PAGE: _Cover
│   └── File cover, version history, owner
│
├── 📁 PAGE: 🧱 Foundations
│   ├── Color Styles
│   ├── Typography Styles
│   ├── Effect Styles (shadows, blurs)
│   └── Grid Styles
│
├── 📁 PAGE: 🔤 Typography
│   └── Type scale specimens, all roles
│
├── 📁 PAGE: 🎨 Color Palette
│   └── All swatches, semantic roles, module colors
│
├── 📁 PAGE: ✨ Glass Physics
│   └── Glass tier samples (all 6 tiers × dark/light)
│
├── 📁 PAGE: 🔘 Components — Atoms
│   └── Button, Input, Badge, Toggle, Slider, Avatar, Skeleton
│
├── 📁 PAGE: 🧩 Components — Molecules
│   └── Card, Toast, Health Ring, ARIA Bubble, Tab Bar, Sidebar, Modal
│
├── 📁 PAGE: 🏗️ Components — Organisms
│   └── Widget Grid, Property Selector, ARIA Panel, Notification Center
│
├── 📁 PAGE: 📱 Mobile Screens
│   ├── D1 Authentication
│   ├── D2 Onboarding
│   ├── D3 Home Dashboard
│   ├── D4 Property
│   ├── D5 Digital Twin
│   ├── D6 Family
│   ├── D7 ARIA
│   ├── D8 Security
│   ├── D9 Energy
│   ├── D10 Inventory / M-SCAN
│   ├── D11 Maintenance
│   ├── D12 Marketplace
│   └── D13 Settings
│
├── 📁 PAGE: 💻 Tablet Screens
│   └── [Same sections — 768px frames]
│
├── 📁 PAGE: 🖥️ Desktop Screens
│   └── [Same sections — 1440px frames]
│
├── 📁 PAGE: 🌙 Dark Mode Samples
│   └── Key screens in dark mode (auto-generated via mode swap)
│
├── 📁 PAGE: ☀️ Light Mode Samples
│   └── Key screens in light mode
│
├── 📁 PAGE: 🔄 Prototype Flows
│   └── Connected prototype flows with spring animations
│
└── 📁 PAGE: 📦 Export Assets
    └── Icons, illustrations, screenshots for handoff
```

---

### Figma Variable Collections

```
COLLECTION: Color / Dark
  ├── background/environment
  ├── background/base
  ├── background/surface
  ├── background/elevated
  ├── background/floating
  ├── background/overlay
  ├── glass/fill
  ├── glass/fill-heavy
  ├── glass/border
  ├── glass/border-top
  ├── text/primary
  ├── text/secondary
  ├── text/tertiary
  ├── text/disabled
  ├── text/link
  ├── icon/primary
  ├── icon/secondary
  ├── icon/tertiary
  ├── border/subtle
  ├── border/default
  ├── border/strong
  └── [status colors — success/warning/danger/info × fill/surface]

COLLECTION: Color / Light
  └── [Same structure, light mode values]

COLLECTION: Color / Module
  ├── home/[100–900]
  ├── property/[100–900]
  ├── twin/[100–900]
  ├── family/[100–900]
  ├── aria/[100–900]
  ├── security/[100–900]
  ├── energy/[100–900]
  ├── inventory/[100–900]
  ├── maintenance/[100–900]
  ├── finances/[100–900]
  ├── documents/[100–900]
  └── marketplace/[100–900]

COLLECTION: Spacing
  └── space-0 through space-64 (all scale steps)

COLLECTION: Radius
  └── All semantic radius tokens

COLLECTION: Typography
  └── All type role tokens as number variables

COLLECTION: Mode
  ├── theme: "dark" | "light" | "auto"
  └── motion: "full" | "reduced" | "none"
```

---

### Naming Conventions

```
FRAMES:
  [Device]/[Section]/[Screen Name]/[State]
  Examples:
    Mobile/D1-Auth/Login/Default
    Mobile/D1-Auth/Login/Loading
    Tablet/D3-Dashboard/Home/Loaded
    Desktop/D7-ARIA/Panel/Expanded

COMPONENTS:
  [Category]/[Name]/[Variant]=[Value], [State]=[Value]
  Examples:
    Atoms/Button/Variant=Primary, Size=MD, State=Default
    Atoms/Button/Variant=Primary, Size=MD, State=Loading
    Molecules/Card/Variant=Standard, Module=Home, State=Hover
    Molecules/Toast/Variant=Success, Action=True

LAYERS inside frames:
  Use descriptive names, not default "Frame 123"
  Group logically: "Header", "Hero", "Grid/Row 1", "Grid/Row 2"
  Background layers: suffix with "·bg" or "·glass"
  
  Convention:
    🔲 Frame/Group  →  group name
    🔷 Component    →  ComponentName (instance name)
    ▭  Rectangle   →  [purpose]·bg
    T  Text        →  [content description]·text
    ☁  Effect      →  [type]·blur or [type]·shadow
```

---

### Auto Layout Conventions

```
All frames use Auto Layout (not manual positioning).

VERTICAL STACKS:
  Direction: Vertical
  Spacing: token from stack scale
  Padding: token from inset scale
  Alignment: Left (most cases), Center (hero sections)

HORIZONTAL ROWS:
  Direction: Horizontal
  Spacing: token from inline scale
  Alignment: Center (vertically)
  Fill: First or last child set to "Fill container" for stretch

GRIDS:
  Use Figma "Grid" layout for widget grids
  Columns: variable (4 mobile, 8 tablet, 12 desktop)
  Gutter: per breakpoint token

RESIZING:
  Container components: Hug contents (default), Fill for stretch
  Text layers: Hug contents always (never fixed width)
  Icons: Fixed 24×24 (or size variant)
```

---

## D1 — AUTHENTICATION SCREENS

### D1.1 — Login Screen

```
FRAME:
  Name:       Mobile/D1-Auth/Login/Default
  Width:      390px
  Height:     844px  (iPhone 14 Pro)
  Grid:       4 columns, 16px margin, 16px gutter

LAYER TREE:
  Login/Default
  ├── lpbe·bg                    [Full frame, LPBE gradient — golden hour]
  │   ├── sky-gradient·bg        [Rectangle, full frame, gradient fill]
  │   └── property-photo·overlay [Image layer, 40% opacity, blend: Multiply]
  │
  ├── glass-blur·overlay         [Rectangle, full frame, backdrop blur 24px]
  │
  ├── content·container          [Auto Layout, Vertical, Center, padding 32px 24px]
  │   │
  │   ├── logo·group             [Auto Layout, Horizontal, gap 8px, Center]
  │   │   ├── prv-logo·icon      [Component: Brand/Logo/Mark, 32×32]
  │   │   └── prv-wordmark·text  [Component: Brand/Logo/Wordmark, height 24]
  │   │
  │   ├── headline·group         [Auto Layout, Vertical, gap 8px, spacer: 48px top]
  │   │   ├── title·text         [Text: "Welcome back", Display/Hero, text-primary]
  │   │   └── subtitle·text      [Text: "Your property intelligence awaits", Body/LG, text-secondary]
  │   │
  │   ├── form·group             [Auto Layout, Vertical, gap 16px, spacer: 40px top]
  │   │   ├── email-field        [Component: Atoms/Input/Type=Email, Size=MD, State=Empty]
  │   │   ├── password-field     [Component: Atoms/Input/Type=Password, Size=MD, State=Empty]
  │   │   └── forgot-link        [Component: Atoms/Button/Variant=Ghost, Size=SM, Align=Right]
  │   │
  │   ├── cta·group              [Auto Layout, Vertical, gap 12px, spacer: 24px top]
  │   │   ├── signin-btn         [Component: Atoms/Button/Variant=Primary, Size=LG, Full-width]
  │   │   ├── divider·row        [Auto Layout, Horizontal, "or continue with"]
  │   │   └── social·row         [Auto Layout, Horizontal, gap 12px]
  │   │       ├── apple-btn      [Component: Atoms/Button/Variant=Glass, Size=MD, Icon=Apple]
  │   │       └── google-btn     [Component: Atoms/Button/Variant=Glass, Size=MD, Icon=Google]
  │   │
  │   └── signup·link            [Text: "Don't have an account? Sign up", Body/SM]
  │
  └── safe-area·bottom           [Spacer, height = safe-area-inset-bottom]

COMPONENT STATES TO INCLUDE:
  Login/Default        (all fields empty)
  Login/Typing-Email   (email field filled, password empty)
  Login/Typing-Pass    (both filled, button enabled)
  Login/Loading        (button in loading state, fields disabled)
  Login/Error          (error toast visible, fields shake)
  Login/Success        (button success state, transitioning out)

APPLIED VARIABLES:
  sky-gradient fill    → lpbe-golden-horizon → lpbe-golden-zenith (gradient)
  glass-blur fill      → glass/fill + 24px blur
  title text           → text/primary
  subtitle text        → text/secondary
  signin-btn bg        → module/home/500
  
PROTOTYPE CONNECTIONS:
  Forgot-link tap      → Modal/D1-Auth/ForgotPassword/Default, spring.smooth
  Apple-btn tap        → Mobile/D1-Auth/Login/Loading (simulate)
  Google-btn tap       → Mobile/D1-Auth/Login/Loading (simulate)
  Signin-btn tap       → Mobile/D1-Auth/Login/Loading → D2-Onboarding/Step1
  Signup link tap      → Mobile/D1-Auth/Register/Default, slide-left

NOTES:
  - LPBE background uses the actual property photo of the user's home
    (first-time users see a generic "beautiful home" hero image)
  - Logo + wordmark are white at all times on this screen (never inverted)
  - Bottom safe area must be respected on all Auth screens
  - Social login buttons are equal width, side by side
```

---

### D1.2 — MFA Screen

```
FRAME:
  Name:   Mobile/D1-Auth/MFA/Default
  Size:   390×844px

LAYER TREE:
  MFA/Default
  ├── lpbe·bg                [Inherited from Login — same scene, dimmed 20%]
  ├── bottom-sheet·container [Auto Layout, bottom-anchored, radius 32px top]
  │   ├── drag-handle        [Rectangle, 36×4px, radius full, glass/border]
  │   ├── header·row         [Auto Layout, Horizontal, space-between]
  │   │   ├── back-btn       [Component: Atoms/Button/Variant=Ghost, Icon=ChevronLeft]
  │   │   └── title·text     [Text: "Two-Factor Authentication"]
  │   ├── instructions·text  [Body/Base, "Enter the 6-digit code sent to..."]
  │   ├── otp·input-row      [Auto Layout, Horizontal, gap 8px]
  │   │   ├── digit-1        [Component: OTPDigit/State=Empty] ×6
  │   ├── resend·row         [Body/SM, "Didn't receive it?" + Ghost button "Resend"]
  │   └── verify-btn         [Atoms/Button/Primary/LG/Full-width]
  │
  STATES:
    MFA/Default   (all digits empty)
    MFA/Filling   (3 of 6 filled — active digit has blue border)
    MFA/Complete  (all 6 filled — button enabled)
    MFA/Verify    (button loading)
    MFA/Error     (digit row shakes, error text: "Incorrect code")
    MFA/Success   (transition to app)
```

---

### D1.3 — Register Screen

```
FRAME: Mobile/D1-Auth/Register/Default
SIZE:  390×844px

Mirrors Login layout with:
  - 3 fields: Full Name, Email, Password
  - Password strength meter (5-segment bar, color-coded)
  - Terms checkbox
  - "Create Account" primary CTA
  - Biometric toggle ("Enable Face ID later" — optional callout)
```

---

## D2 — ONBOARDING SCREENS

### D2.1 — Welcome Shell

```
FRAME: Mobile/D2-Onboarding/Welcome/Default
SIZE:  390×844px

LAYER TREE:
  Welcome/Default
  ├── lpbe·bg                [Dawn sky gradient, animated particles (spec only)]
  ├── progress·header        [Auto Layout, top-safe area + 16px padding]
  │   ├── skip-btn           [Ghost/SM, right-aligned]
  │   └── progress-dots      [Custom component: 5 dots, dot-1 active]
  ├── hero·section           [Auto Layout, Vertical, Center, flex-grow]
  │   ├── house-illustration [SVG/Image, 240×240px]
  │   ├── title·text         [Display/Large: "Your home, intelligently managed"]
  │   └── subtitle·text      [Body/LG, text-secondary, 2 lines max]
  └── cta·footer             [Auto Layout, Vertical, bottom-safe + 24px padding]
      ├── continue-btn       [Primary/LG/Full-width: "Get Started"]
      └── signin-link        [Ghost/SM: "Already have an account? Sign in"]
```

---

### D2.2 — Add Property Step

```
FRAME: Mobile/D2-Onboarding/AddProperty/Default
SIZE:  390×844px

LAYER TREE:
  AddProperty/Default
  ├── progress·header        [Step 1 of 5 active]
  ├── content·scroll         [Scrollable, Auto Layout, Vertical]
  │   ├── step-header        [Step number chip + "Add Your Property"]
  │   ├── address-field      [Input, Type=Text, Placeholder="Start typing your address"]
  │   ├── autocomplete-list  [Component: Molecules/Autocomplete/Open, 5 suggestions]
  │   ├── property-type·row  [Auto Layout, Horizontal, gap 8px]
  │   │   ├── type-chip[0]   [Component: Atoms/Chip/Selected: "House"]
  │   │   ├── type-chip[1]   [Component: Atoms/Chip/Default: "Apartment"]
  │   │   ├── type-chip[2]   [Component: Atoms/Chip/Default: "Villa"]
  │   │   └── type-chip[3]   [Component: Atoms/Chip/Default: "Other"]
  │   ├── photo-upload       [Component: Molecules/PhotoUpload/Empty]
  │   └── year-field         [Input, Type=Number, "Year built (optional)"]
  └── cta·footer             [Continue btn enabled when address filled]

  STATES:
    AddProperty/Default     (empty form)
    AddProperty/Typing      (address field active, autocomplete open)
    AddProperty/Selected    (address chosen, chips selectable)
    AddProperty/Filled      (type selected, photo optional — btn enabled)
    AddProperty/Uploading   (photo upload progress)
```

---

### D2.3 — Property Profile Step

```
FRAME: Mobile/D2-Onboarding/PropertyProfile/Default
SIZE:  390×844px

Fields:
  - Property nickname (optional, "My Home", "Beach House")
  - Size (m²) — numeric input
  - Number of rooms — stepper component (+/-)
  - Number of bathrooms — stepper
  - Heating type — chip selector (Gas/Electric/Heat Pump/Other)
  - Year of last renovation — optional
```

---

### D2.4 — Family Setup Step

```
FRAME: Mobile/D2-Onboarding/FamilySetup/Default
SIZE:  390×844px

LAYER TREE:
  FamilySetup/Default
  ├── progress·header        [Step 3 of 5]
  ├── content                [Auto Layout, Vertical]
  │   ├── step-header        ["Who lives here?"]
  │   ├── members-list       [Auto Layout, Vertical, gap 12px]
  │   │   ├── member-row[0]  [Component: Molecules/MemberRow/You/Owner]
  │   │   ├── member-row[1]  [Component: Molecules/MemberRow/Added, name="Anna"]
  │   │   └── add-member-btn [Component: Atoms/Button/Variant=Ghost, Icon=Plus, "Add family member"]
  │   └── skip-text          [Body/SM, text-tertiary: "You can add people later in Settings"]
  └── cta·footer             [Continue btn]
```

---

### D2.5 — Permissions Step

```
FRAME: Mobile/D2-Onboarding/Permissions/Default
SIZE:  390×844px

Permission cards (each is a Molecules/PermissionCard):
  1. Notifications — "Stay updated on maintenance, alerts & ARIA insights"
  2. Location — "Automatically detect your property's local weather"
  3. Camera — "Use M-SCAN™ to catalog your appliances"
  4. Biometric Auth — "Sign in with Face ID or fingerprint"

Each card:
  - Icon (module-colored)
  - Title + description
  - "Allow" primary button
  - "Not now" ghost link
```

---

### D2.6 — ARIA Introduction Step

```
FRAME: Mobile/D2-Onboarding/ARIAIntro/Default
SIZE:  390×844px

Shows ARIA speaking to the user for the first time.
Full-screen, violet gradient background.
ARIA avatar (abstract AI orb, violet + indigo animated).
Text: "Hi, I'm ARIA — your property's AI brain.
       I'll learn how your home works, alert you to things that matter,
       and handle the complexity so you don't have to."
"Meet ARIA" CTA → first ARIA conversation prompt.
"Set up later" ghost link.
```

---

## D3 — HOME DASHBOARD

### D3.1 — Dashboard (Loaded)

```
FRAME: Mobile/D3-Dashboard/Home/Loaded
SIZE:  390×844px

LAYER TREE:
  Home/Loaded
  ├── lpbe·bg                [Living background — current time/weather of property]
  │   ├── sky·gradient       [Real-time sky color variables from LPBE palette]
  │   └── property·image     [User's property photo, 30% opacity, bottom-anchored]
  │
  ├── status-bar·overlay     [44px, safe area top, glass-whisper]
  │
  ├── header·bar             [Auto Layout, Horizontal, Space-between, 52px height]
  │   ├── property-selector  [Component: Molecules/PropertySelector/Collapsed]
  │   ├── date·text          [Body/SM, text-secondary: "Tuesday, 9 June"]
  │   └── actions·row        [Auto Layout, Horizontal, gap 4px]
  │       ├── notifications-btn [Component: Atoms/IconButton, Icon=Bell, Badge=3]
  │       └── profile-btn    [Component: Atoms/Avatar, Size=SM, State=Online]
  │
  ├── scroll·container       [Vertical scroll, overscroll-behavior: contain]
  │   │
  │   ├── health-hero·card   [Component: Organisms/HealthHeroCard, Full-width]
  │   │   [2×2 glass-heavy card]
  │   │   ├── health-ring    [Component: Molecules/HealthRing, Size=Hero, Score=84]
  │   │   ├── score-label    [Text: "Good", H3, color-health-good]
  │   │   ├── quick-stats    [3 micro-metrics: Open Tasks / Alerts / Warranty Due]
  │   │   └── view-report-link [Ghost/SM]
  │   │
  │   ├── widget-grid·row1   [Auto Layout, Horizontal, gap 12px]
  │   │   ├── energy-widget  [Component: Molecules/Widget/Energy, Size=1×1]
  │   │   │   [Shows: 2.4 kWh today, trend arrow, mini sparkline]
  │   │   └── security-widget [Component: Molecules/Widget/Security, Size=1×1]
  │   │       [Shows: Armed/Disarmed, last event]
  │   │
  │   ├── widget-grid·row2   [Auto Layout, Horizontal, gap 12px]
  │   │   ├── tasks-widget   [Component: Molecules/Widget/Tasks, Size=2×1, Full-width]
  │   │   │   [Shows: 3 upcoming tasks with dates]
  │   │
  │   ├── aria-promo·card    [Component: Molecules/ARIAInsightCard]
  │   │   [ARIA's proactive daily insight — glass-heavy, violet tint]
  │   │
  │   ├── widget-grid·row3   [Auto Layout, Horizontal, gap 12px]
  │   │   ├── weather-widget [1×1]
  │   │   └── family-widget  [1×1: 2 online, 1 away]
  │   │
  │   ├── widget-grid·row4   [Auto Layout, Horizontal, gap 12px]
  │   │   ├── finances-widget [1×1]
  │   │   └── inventory-widget [1×1: 47 items]
  │   │
  │   └── bottom-spacer      [Height: 88px (tab bar clearance)]
  │
  └── tab-bar                [Component: Organisms/TabBar, Position=Sticky Bottom]
      [5 items: Home(active), Property, ARIA(center elevated), Family, More]

PROTOTYPE CONNECTIONS:
  health-hero card tap     → Mobile/D4-Property/Health/Default, spring.smooth
  energy-widget tap        → Mobile/D9-Energy/Dashboard/Default
  security-widget tap      → Mobile/D8-Security/Center/Default
  tasks-widget row tap     → Mobile/D11-Maintenance/TaskDetail/Default
  aria-promo card tap      → Mobile/D7-ARIA/Chat/Peek
  notifications-btn tap    → Mobile/D3-Dashboard/Notifications/Open
  property-selector tap    → Mobile/D3-Dashboard/PropertyPicker/Open
  tab-bar/Property tap     → Mobile/D4-Property/Overview/Default
  tab-bar/ARIA tap         → Mobile/D7-ARIA/Chat/Expanded (spring.smooth, slide-up)
  tab-bar/Family tap       → Mobile/D6-Family/Overview/Default
  tab-bar/More tap         → Mobile/D3-Dashboard/More/Default

STATES TO INCLUDE:
  Home/Loading             (skeletons for all widgets)
  Home/Loaded              (full data)
  Home/Reorder             (long-press triggers, drag handles visible)
  Home/No-Properties       (empty state: add first property)
  Home/Offline             (all widgets show "offline" indicator)
```

---

### D3.2 — Notification Drawer

```
FRAME: Mobile/D3-Dashboard/Notifications/Open
SIZE:  390×844px (modal overlay on top of Dashboard)

LAYER TREE:
  Notifications/Open
  ├── [Dashboard/Loaded visible behind, 40% dimmed]
  ├── scrim                  [Full frame, glass-frosted]
  └── drawer·sheet           [Bottom sheet, max-height 80%, glass-opaque]
      ├── drag-handle
      ├── header·row         [Title "Notifications" + "Mark all read" link]
      ├── critical·section   [Section header + 1–2 critical items]
      ├── new·section        [Section header + N new items]
      ├── earlier·section    [Section header + older items]
      └── [Each item: Molecules/NotificationRow]
```

---

## D4 — PROPERTY SCREENS

### D4.1 — Property Overview

```
FRAME: Mobile/D4-Property/Overview/Default
SIZE:  390×844px

LAYER TREE:
  Overview/Default
  ├── lpbe·bg
  ├── header·bar             [Auto Layout, Space-between]
  │   ├── back-btn           [Icon=ChevronLeft]
  │   ├── property-name·text [H2: "Casa Florilor"]
  │   └── more-btn           [Icon=MoreHorizontal]
  │
  ├── property-hero·card     [Full-width, 200px height, radius-card-lg]
  │   ├── photo·image        [Property photo, fill]
  │   ├── overlay·gradient   [Bottom-to-transparent dark gradient]
  │   ├── address·text       [Body/SM, white: "Str. Florilor 12, Cluj-Napoca"]
  │   └── health-badge       [Component: Badge/Health, Score=84]
  │
  ├── tab-bar·secondary      [5 tabs: Overview, Health, Documents, History, Settings]
  │
  ├── overview-content       [Auto Layout, Vertical]
  │   ├── stats·row          [4 metric cards: m², Rooms, Year Built, Owner since]
  │   ├── systems·section    [Heading + system status grid]
  │   │   ├── hvac-card      [1×1: Status + last service]
  │   │   ├── electrical-card [1×1: Status]
  │   │   ├── plumbing-card  [1×1: Status]
  │   │   └── security-card  [1×1: Armed/Disarmed]
  │   ├── upcoming-tasks·section [3 nearest tasks]
  │   └── recent-activity·section [5 recent events, timeline layout]
  │
  └── tab-bar·primary
```

---

### D4.2 — Property Health Report

```
FRAME: Mobile/D4-Property/Health/Default
SIZE:  390×844px

Full health report — all 7 factors expanded.

LAYER TREE:
  Health/Default
  ├── header·bar [← Property name + "Health Report"]
  ├── scroll·container
  │   ├── hero-ring·section
  │   │   ├── health-ring    [Size=Hero, 160px, Score=84]
  │   │   ├── score-number   [Display/Large: "84", color-health-good]
  │   │   ├── status-label   [H3: "Good"]
  │   │   └── last-updated   [Body/XS: "Updated 2 hours ago"]
  │   │
  │   ├── trend·section      [Mini chart: 12-month score history]
  │   │
  │   ├── factors·section    [Section header: "Health Factors"]
  │   │   └── [7 × Molecules/HealthFactorRow]
  │   │       Each row: icon + name + score bar + score number + detail link
  │   │       Factor 1: Maintenance (weight 30%)
  │   │       Factor 2: Safety & Security (weight 25%)
  │   │       Factor 3: Energy Efficiency (weight 15%)
  │   │       Factor 4: Document Status (weight 10%)
  │   │       Factor 5: System Health (weight 10%)
  │   │       Factor 6: Insurance Coverage (weight 5%)
  │   │       Factor 7: Financial Health (weight 5%)
  │   │
  │   ├── recommendations·section [ARIA insight cards — top 3 actions]
  │   └── bottom-spacer
```

---

## D5 — DIGITAL TWIN

### D5.1 — Twin Viewer

```
FRAME: Mobile/D5-Twin/Viewer/Default
SIZE:  390×844px

LAYER TREE:
  Viewer/Default
  ├── canvas·3d              [Full screen — Three.js/R3F canvas area]
  │   [3D floor plan rendered, interactive]
  │
  ├── header·overlay         [Auto Layout, top-safe, glass-heavy, blur 24px]
  │   ├── back-btn
  │   ├── property-name·text ["Casa Florilor · 3D View"]
  │   └── actions·row
  │       ├── filter-btn     [Icon=Filter — filter overlaid IoT devices]
  │       └── fullscreen-btn [Icon=Expand]
  │
  ├── mode-selector·pill     [Auto Layout, Horizontal, centered, glass-heavy]
  │   ├── mode[0]            [Chip: "Rooms" — active]
  │   ├── mode[1]            [Chip: "Systems"]
  │   ├── mode[2]            [Chip: "Energy"]
  │   ├── mode[3]            [Chip: "Security"]
  │   └── mode[4]            [Chip: "Devices"]
  │
  ├── zoom-controls          [Auto Layout, Vertical, right-anchored, 80px from bottom]
  │   ├── zoom-in-btn
  │   ├── zoom-out-btn
  │   └── reset-btn          [Icon=Home — reset to default view]
  │
  ├── room-panel·bottom      [Bottom sheet 140px, glass-heavy]
  │   [Shown when room is tapped]
  │   ├── drag-handle
  │   ├── room-name·text     [H3: "Living Room"]
  │   ├── room-stats·row     [m², Temp, Humidity, Devices]
  │   └── view-detail-btn    [Ghost/SM: "View full details →"]
  │
  └── tab-bar

STATES:
  Viewer/Default             (house visible, no room selected)
  Viewer/RoomSelected        (room highlighted, bottom panel shown)
  Viewer/Loading             (skeleton spinner, "Building your Digital Twin...")
  Viewer/NoTwin              (empty state: "Set up your Digital Twin")
  Viewer/DeviceHighlight     (IoT device markers visible, tappable)
```

---

## D6 — FAMILY SCREENS

### D6.1 — Family Overview

```
FRAME: Mobile/D6-Family/Overview/Default
SIZE:  390×844px

LAYER TREE:
  Family/Overview/Default
  ├── header·bar ["Family" + "Manage" button]
  │
  ├── scroll·container
  │   ├── active-members·section
  │   │   ├── section-header ["At Home Now" + member count badge]
  │   │   └── members·row    [Auto Layout, Horizontal, overflow scroll]
  │   │       └── [N × Molecules/MemberPresenceCard]
  │   │           Each: avatar + name + status dot + "At home" text
  │   │
  │   ├── all-members·section
  │   │   ├── section-header ["Family Members" + "Invite" button]
  │   │   └── [N × Molecules/MemberListRow]
  │   │       Each: avatar + name + role + status + ">" chevron
  │   │
  │   ├── zones·section       [Access zones for property areas]
  │   │   ├── zone-card[0]   [Main Door — 2 keys assigned]
  │   │   ├── zone-card[1]   [Smart Lock — Garage]
  │   │   └── zone-card[2]   [Safe Room — Owner only]
  │   │
  │   ├── activity·section   [Family activity feed, 24h]
  │   │   └── [N × Molecules/ActivityRow — arrival/departure/action]
  │   │
  │   └── guest-section      [Active guests, invite new]
  │
  └── tab-bar
```

---

### D6.2 — Member Detail

```
FRAME: Mobile/D6-Family/MemberDetail/Default
SIZE:  390×844px

LAYER TREE:
  MemberDetail/Default
  ├── header·bar [← Family + member name]
  ├── member-hero·card [glass-heavy, rose tint]
  │   ├── avatar             [Size=2XL, 80px]
  │   ├── name·text          [H2]
  │   ├── role-badge         [Badge/Module/Family]
  │   └── status·row         [Status dot + "At home" + last seen]
  │
  ├── permissions·section    ["Module Access" — toggle list for each module]
  ├── zones·section          ["Property Zones" — checkboxes per zone]
  ├── notifications·section  ["Notify me when..." — toggle rules]
  └── actions·footer
      ├── remove-btn         [Destructive: "Remove from household"]
      └── transfer-btn       [Ghost: "Transfer ownership" — owner only]
```

---

## D7 — ARIA SCREENS

### D7.1 — ARIA Chat (Collapsed → Peek → Expanded)

```
FRAME SET — 3 states shown in Prototype flow:

STATE 1: Collapsed (Pill)
  Height: 48px
  Position: Floating, 16px above tab bar
  Background: glass-heavy + violet tint + blur 24px
  Border: 1px rgba(128,64,196,0.40)
  Content: [Sparkles icon] + "Ask ARIA anything..." text
  Box-shadow: shadow-3 + glow-aria
  Border-radius: 24px (pill)

STATE 2: Peek (40% height)
  Height: 380px
  Background: glass-opaque + violet tint, radius-modal-lg top corners only
  Content:
    ├── drag-handle
    ├── quick-actions·row [3 context-aware chips]
    ├── input·field [focused, keyboard open]
    └── recent-context [Small card: last query summary]

STATE 3: Expanded (70% height)
  Height: 640px
  Background: glass-opaque + violet tint
  Content:
    ├── drag-handle + header ["ARIA" + "Clear" link]
    ├── messages·scroll [Full conversation]
    │   ├── [User bubbles: right-aligned, glass-standard]
    │   └── [ARIA bubbles: left-aligned, violet glass + sparkles avatar]
    │       — Thinking state: 3-dot pulse
    │       — Inline cards: Molecules/ARIACard (metrics, tasks, devices)
    └── input·footer [TextField + Send btn]

ARIA MESSAGE TYPES (show all in frame):
  D7-ARIA/Messages/UserText      (user bubble, right-aligned)
  D7-ARIA/Messages/ARIAText      (ARIA bubble, left, streaming cursor shown)
  D7-ARIA/Messages/ARIACard-Metric (glass card with big number)
  D7-ARIA/Messages/ARIACard-Task  (task item with status/CTA)
  D7-ARIA/Messages/ARIACard-Alert (red border, alert content)
  D7-ARIA/Messages/ARIAChart      (mini line chart inline)
  D7-ARIA/Messages/ARIAThinking   (3 dots animating)
```

---

## D8 — SECURITY SCREENS

### D8.1 — Security Center

```
FRAME: Mobile/D8-Security/Center/Default
SIZE:  390×844px

LAYER TREE:
  Security/Center/Default
  ├── header·bar ["Security" + History icon]
  ├── arm-hero·card          [Full-width, glass-heavy, RED tint when armed]
  │   ├── status-icon        [ShieldCheck 48px, white]
  │   ├── status·text        [H1: "Armed — Away" or "Disarmed"]
  │   ├── arm-mode·row       [3 chips: Home / Away / Night]
  │   └── arm-btn            [Large 52px CTA: "Arm" / "Disarm"]
  │
  ├── zones·section          [Section header + zone cards]
  │   └── [N × Molecules/ZoneCard]
  │       Each: zone name + status badge + devices count + ">" 
  │
  ├── cameras·section        [Camera feed thumbnails grid]
  │   └── [N × Molecules/CameraThumb, 2-col grid]
  │       Each: live feed image + camera name + status dot
  │
  ├── activity·section       [Recent security events, timeline]
  │   └── [N × Molecules/SecurityEvent]
  │       Each: icon + event text + timestamp + "View clip" link
  │
  └── tab-bar

STATES:
  Security/Disarmed
  Security/Armed-Away
  Security/Armed-Home
  Security/Alert        (full red tint, alert modal overlay)
  Security/Camera-Tap   (camera fullscreen modal)
```

---

## D9 — ENERGY SCREENS

### D9.1 — Energy Dashboard

```
FRAME: Mobile/D9-Energy/Dashboard/Default
SIZE:  390×844px

LAYER TREE:
  Energy/Dashboard/Default
  ├── header·bar ["Energy" + Solar/Grid icon toggle]
  ├── live-usage·hero        [Full-width, glass-heavy, green tint]
  │   ├── current-draw·text  [Display/LG: "2.4 kW", numeric]
  │   ├── usage-label        [Label: "LIVE CONSUMPTION"]
  │   ├── source-row         [Grid % / Solar % bar indicator]
  │   └── vs-yesterday       [Body/SM: "↓ 12% vs yesterday"]
  │
  ├── sankey·section         [Section header + Organisms/EnergySankey]
  │   [Vertical layout on mobile]
  │
  ├── period-selector        [Chips: Day / Week / Month / Year]
  │
  ├── usage-chart·section    [Area chart, period-based]
  │   [gradient fill: green to transparent]
  │
  ├── cost-breakdown·section [Stacked bar: Grid / Solar / Battery]
  │   ├── cost-hero          [H2: "€ 84.20 this month"]
  │   └── breakdown-bar      [Visual cost breakdown]
  │
  ├── devices·section        [Top consumers ranked]
  │   └── [N × Molecules/DeviceUsageRow]
  │
  └── tab-bar

STATES:
  Energy/Loading
  Energy/Default             (day view)
  Energy/WeekView
  Energy/MonthView
  Energy/SolarExporting      (positive net meter — special green glow)
```

---

## D10 — INVENTORY / M-SCAN SCREENS

### D10.1 — Inventory List

```
FRAME: Mobile/D10-Inventory/List/Default
SIZE:  390×844px

LAYER TREE:
  Inventory/List/Default
  ├── header·bar ["Inventory" + Search + Filter + Scan FAB]
  │
  ├── stats·row              [4 chips: Total items / Warranties / Recalls / Value]
  │
  ├── filter-bar             [Horizontal scroll: All / Appliances / Electronics / Furniture / Tools]
  │
  ├── items-list             [Auto Layout, Vertical, gap 8px]
  │   └── [N × Molecules/InventoryItemRow]
  │       Each: thumbnail + name + brand + warranty badge + room label + ">"
  │
  ├── scan-fab               [Component: Atoms/Button/FAB, Icon=Camera, teal color]
  │
  └── tab-bar
```

---

### D10.2 — M-SCAN™ Scanner

```
FRAME: Mobile/D10-Inventory/MScan/Default
SIZE:  390×844px

LAYER TREE:
  MScan/Default
  ├── camera·full-screen     [Full frame, live camera]
  │
  ├── header·overlay         [Top glass bar]
  │   ├── close-btn
  │   ├── title·text         ["M-SCAN™"]
  │   └── flash-btn
  │
  ├── guide-frame            [SVG overlay: animated corner brackets, 240×160px, centered]
  │   [Brackets animate on detect: scale pulse, color → green]
  │
  ├── status-text            [Body/SM, white, centered: "Aim at the nameplate"]
  │
  ├── gallery-import·btn     [Auto Layout, Horizontal, bottom-left]
  │
  └── [Result bottom sheet — see below]

SCAN RESULT BOTTOM SHEET (slides up after success):
  Name:   MScan/Result/Default
  Height: 360px (partial), glass-opaque

  Content:
  ├── drag-handle
  ├── appliance-hero·row [Thumbnail 64×64 + Name + Brand + Model]
  ├── details·list [Serial / Manufacture Date / Warranty Status (badge) / Manual link]
  ├── warranty-card [Prominent: "✓ Warranty active until Mar 2027" — green glass]
  └── cta-row
      ├── add-btn            [Primary: "Add to Inventory"]
      └── scan-again-btn     [Ghost: "Scan Another"]

STATES:
  MScan/Default              (scanning)
  MScan/Detecting            (corners animate, "Detecting nameplate...")
  MScan/Processing           (spinner, "Reading...")
  MScan/Result               (result sheet visible)
  MScan/Error                ("Couldn't read — try manual entry" + retry)
  MScan/Manual               (form fallback sheet)
```

---

## D11 — MAINTENANCE SCREENS

### D11.1 — Maintenance Center

```
FRAME: Mobile/D11-Maintenance/Center/Default
SIZE:  390×844px

LAYER TREE:
  Maintenance/Center/Default
  ├── header·bar ["Maintenance" + Calendar + Add button]
  │
  ├── upcoming-hero·card     [glass-heavy, amber tint]
  │   ├── next-task·text     ["Next: HVAC Filter — in 3 days"]
  │   ├── mini-calendar      [7-day strip, task dots overlay]
  │   └── view-calendar-link
  │
  ├── urgent-section         [Section: "Overdue" (if any), red border accent]
  │   └── [N × Molecules/TaskCard/Urgent]
  │
  ├── upcoming-section       [Section: "This Week"]
  │   └── [N × Molecules/TaskCard/Standard]
  │
  ├── scheduled-section      [Section: "Scheduled"]
  │   └── [N × Molecules/TaskCard/Scheduled]
  │
  ├── completed-section      [Collapsed by default, "Completed This Month"]
  │
  └── tab-bar

TASK CARD ANATOMY (Molecules/TaskCard):
  [Icon (wrench) in module-amber circle] [Task name·H5] [Due date·Badge]
  [Property system tag] [Assigned to avatar (if any)] [Status badge]
  [Priority indicator: colored left border — Red/Amber/Green/Gray]
```

---

### D11.2 — Task Detail

```
FRAME: Mobile/D11-Maintenance/TaskDetail/Default
SIZE:  390×844px

Full task detail:
  - Hero section: task title + system + priority badge + status
  - Description / notes (expandable)
  - Checklist (interactive checkboxes)
  - Before/After photo upload
  - Assigned contractor (if any) — with contact button
  - Related inventory items (appliances)
  - Cost tracking (parts + labor)
  - History (previous completions)
  - Action buttons: "Mark Complete" / "Reschedule" / "Assign"
```

---

## D12 — MARKETPLACE SCREENS

### D12.1 — Marketplace Home

```
FRAME: Mobile/D12-Marketplace/Home/Default
SIZE:  390×844px

LAYER TREE:
  Marketplace/Home/Default
  ├── header·bar ["Marketplace" + Cart icon (with badge) + Search]
  │
  ├── search-bar             [Input/Search, full-width]
  │
  ├── aria-recommendation·banner [glass-heavy, lime tint]
  │   ["ARIA suggests: Your HVAC filter is due. Order now →"]
  │
  ├── categories·row         [Horizontal scroll: Maintenance / Appliances / Smart Home / Services / Insurance]
  │
  ├── featured·section       [2 hero cards, full-width]
  │   └── [Molecules/FeaturedProductCard]
  │
  ├── trending·section       [Heading + 2-col product grid]
  │   └── [N × Molecules/ProductCard]
  │       Each: image + name + rating + price + "Add to cart" btn
  │
  ├── services·section       [Heading + provider cards]
  │   └── [N × Molecules/ServiceProviderCard]
  │       Each: logo + name + specialty + rating + "Book" btn
  │
  └── tab-bar (inside More nav)
```

---

## D13 — SETTINGS SCREENS

### D13.1 — Settings Root

```
FRAME: Mobile/D13-Settings/Root/Default
SIZE:  390×844px

LAYER TREE:
  Settings/Root/Default
  ├── header·bar ["Settings"]
  │
  ├── profile-card           [glass-heavy, top section]
  │   ├── avatar             [Size=XL, 64px]
  │   ├── name·text          [H3]
  │   ├── email·text         [Body/SM, text-secondary]
  │   └── edit-btn           [Ghost/SM: "Edit Profile"]
  │
  ├── settings-scroll        [Auto Layout, Vertical, gap 8px]
  │   │
  │   ├── section-label      ["PROPERTY"]
  │   ├── property-section·card [glass-standard]
  │   │   ├── properties-row     [Nav: "My Properties" + count badge]
  │   │   ├── family-row         [Nav: "Family & Access"]
  │   │   └── notifications-row  [Nav: "Notifications"]
  │   │
  │   ├── section-label      ["APP"]
  │   ├── app-section·card   [glass-standard]
  │   │   ├── appearance-row     [Nav: "Appearance" + current mode value]
  │   │   ├── language-row       [Nav: "Language" + current lang]
  │   │   ├── units-row          [Nav: "Units" + m²/ft²]
  │   │   └── privacy-row        [Nav: "Privacy & Data"]
  │   │
  │   ├── section-label      ["ARIA"]
  │   ├── aria-section·card  [glass-standard, violet tint]
  │   │   ├── aria-memory-row    [Nav: "ARIA Memory & Context"]
  │   │   ├── aria-model-row     [Nav: "AI Model" + current model name]
  │   │   └── aria-data-row      [Nav: "ARIA Data Sources"]
  │   │
  │   ├── section-label      ["ACCOUNT"]
  │   ├── account-section·card [glass-standard]
  │   │   ├── subscription-row   [Nav: "Subscription" + plan badge]
  │   │   ├── security-row       [Nav: "Security & Login"]
  │   │   └── billing-row        [Nav: "Billing"]
  │   │
  │   ├── section-label      ["SUPPORT"]
  │   ├── support-section·card [glass-standard]
  │   │   ├── help-row           [Nav: "Help & FAQ"]
  │   │   ├── feedback-row       [Nav: "Send Feedback"]
  │   │   └── about-row          [Nav: "About PRV HOUSE" + version]
  │   │
  │   └── signout-btn        [Destructive/LG/Full-width: "Sign Out"]
  │
  └── tab-bar (inside More nav)
```

---

## D14 — TABLET LAYOUT ADAPTATIONS

### General Tablet Rules

```
FRAME SIZE: 820×1180px (iPad Air)

KEY DIFFERENCES FROM MOBILE:

1. SIDEBAR replaces tab bar
   - Position: Left, 72px (collapsed) or 260px (expanded)
   - Trigger to expand: swipe right or tap expand icon
   - Content area: fills remaining width

2. SPLIT VIEWS on detail screens
   - Master list: left panel (320px)
   - Detail view: right panel (fills rest)
   - Used in: Inventory, Maintenance, Family, Documents, Settings

3. MODALS are side-sheets (right edge) not bottom sheets
   - Width: 400px
   - Full height
   - Backdrop: dims left panel

4. GRID upgrades
   - Dashboard: 2-col widget grid (was 1-col)
   - Inventory: 3-col grid (was 2-col)

5. ARIA panel
   - Persistent side panel (320px, right side) — not bottom sheet
   - Can be pinned open while navigating

FRAME NAMING:
  Tablet/D3-Dashboard/Home/Loaded
  Tablet/D4-Property/SplitView/Overview
  etc.
```

---

### D14.1 — Tablet Dashboard

```
FRAME: Tablet/D3-Dashboard/Home/Loaded
SIZE:  820×1180px

LAYER TREE:
  Dashboard/Loaded [Tablet]
  ├── lpbe·bg                [Full frame, sky + property]
  ├── sidebar·panel          [Left, 72px collapsed, glass-opaque]
  │   ├── logo-icon          [32px, top, 12px margin]
  │   ├── nav-items          [Auto Layout, Vertical, gap 4px, 12px margin]
  │   │   └── [N × Organisms/SidebarNavItem/Collapsed]
  │   └── profile-avatar     [Bottom, 40px]
  │
  └── content·area           [Right of sidebar, full height]
      ├── header·bar         [52px, Property selector + right actions]
      │
      └── scroll·container
          ├── health-hero·card [Full-width, 2×2]
          ├── widget-grid    [2-col auto grid, gap 16px]
          │   ├── energy-widget  [1×1]
          │   ├── security-widget [1×1]
          │   ├── tasks-widget   [2×1]
          │   ├── aria-card      [2×1]
          │   └── ...
          └── bottom-spacer
```

---

## D15 — DESKTOP LAYOUT ADAPTATIONS

### General Desktop Rules

```
FRAME SIZE: 1440×900px (standard desktop)

KEY DIFFERENCES:

1. SIDEBAR expanded (260px)
   - Shows icon + label for all nav items
   - Property selector at top
   - Health ring (small) below property selector
   - ARIA quick-access at bottom

2. THREE-COLUMN LAYOUTS
   - Left: sidebar (260px)
   - Center: main content (flexible)
   - Right: contextual panel (320px, appears on selection)

3. ALL MODALS are centered dialogs
   - Max-width: 480–640px
   - Always vertically centered
   - Background: glass-frosted scrim

4. HOVER STATES fully designed
   - Cards show hover elevation
   - Buttons show hover state
   - Sidebar items show hover bg

5. ARIA PANEL
   - Persistent right panel (320px)
   - Can be collapsed by user
   - Maintains conversation context
   - In-context query from any screen

FRAME NAMING:
  Desktop/D3-Dashboard/Home/Loaded
  Desktop/D4-Property/SplitView/Health
  etc.
```

---

### D15.1 — Desktop Dashboard

```
FRAME: Desktop/D3-Dashboard/Home/Loaded
SIZE:  1440×900px

LAYER TREE:
  Dashboard/Home [Desktop]
  ├── lpbe·bg                [Full frame]
  ├── sidebar·expanded       [260px, glass-opaque, full height]
  │   ├── header-section     [Auto Layout, Vertical, 20px padding]
  │   │   ├── logo-row       [PRV mark + wordmark]
  │   │   ├── property-selector [Full selector trigger]
  │   │   └── health-ring    [Size=Small, 40px]
  │   ├── nav-section        [Auto Layout, Vertical, flex-grow]
  │   │   └── [N × Organisms/SidebarNavItem/Expanded]
  │   └── footer-section     [ARIA quick access + profile]
  │
  ├── content·main           [Right of sidebar, full height, flex-grow]
  │   ├── topbar             [52px, search + notifications + profile]
  │   └── content·scroll     [3-col widget grid — 12-col CSS grid]
  │       ├── health-hero    [col span 4]
  │       ├── energy-widget  [col span 4]
  │       ├── security-widget [col span 4]
  │       ├── tasks-widget   [col span 6]
  │       ├── aria-card      [col span 6]
  │       ├── family-widget  [col span 4]
  │       ├── weather-widget [col span 4]
  │       └── finances-widget [col span 4]
  │
  └── aria·side-panel        [320px right, glass-opaque, persistent]
      ├── panel-header       ["ARIA" + collapse btn]
      ├── context-summary    [Small card: current module context]
      ├── quick-actions      [3 chips]
      └── input·footer       [Chat input + send]
```

---

## D16 — PROTOTYPE FLOWS

### Flow 1: First-Time User Journey

```
START: Mobile/D1-Auth/Login/Default

FLOW:
  Login/Default
    → [tap "Sign up"] → Register/Default, slide-left, spring.standard
  Register/Default
    → [fill + submit] → Register/Loading
    → [success] → D2-Onboarding/Welcome/Default, fade, spring.gentle
  Onboarding/Welcome
    → [tap "Get Started"] → Onboarding/AddProperty/Default, slide-left
  Onboarding/AddProperty
    → [fill address + type] → Onboarding/PropertyProfile/Default, slide-left
  Onboarding/PropertyProfile
    → [fill details] → Onboarding/FamilySetup/Default, slide-left
  Onboarding/FamilySetup
    → [continue] → Onboarding/Permissions/Default, slide-left
  Onboarding/Permissions
    → [allow/skip all] → Onboarding/ARIAIntro/Default, slide-left
  Onboarding/ARIAIntro
    → [tap "Meet ARIA"] → D3-Dashboard/Home/Loading → D3-Dashboard/Home/Loaded
```

---

### Flow 2: Dashboard → ARIA Interaction

```
START: Mobile/D3-Dashboard/Home/Loaded

FLOW:
  Dashboard/Loaded
    → [tap ARIA pill] → D7-ARIA/Peek, slide-up partial, spring.smooth
  ARIA/Peek
    → [drag up] → D7-ARIA/Expanded, slide-up, spring.smooth
    → [tap "What's my energy usage?"] → ARIA/Expanded/Typing → ARIA/Expanded/Responding
  ARIA/Expanded/Responding
    → [ARIA returns chart card] → ARIA/Expanded/CardShown
    → [tap energy chart card] → D9-Energy/Dashboard/Default, slide-left
  D9-Energy
    → [swipe down] → return to Dashboard, spring.standard
```

---

### Flow 3: M-SCAN™ Scan + Add

```
START: Mobile/D10-Inventory/List/Default

FLOW:
  Inventory/List
    → [tap FAB scan button] → D10-Inventory/MScan/Default, scale-up, spring.wobbly
  MScan/Default
    → [camera active, aim at nameplate]
    → MScan/Detecting → MScan/Processing
    → MScan/Result (bottom sheet slides up, spring.smooth)
  MScan/Result
    → [tap "Add to Inventory"] → InventoryItem/New/Default (detail view)
    → [save] → Inventory/List/Updated (new item at top, highlighted briefly)
```

---

### Flow 4: Security Alert Response

```
START: Mobile/D8-Security/Center/Default

FLOW:
  Security/Default
    → [notification arrives] → Security/AlertModal overlays (spring.snap, immediate)
  Security/Alert
    → [tap "View Camera"] → Security/CameraFullscreen/Default
  Camera/Fullscreen
    → [tap "Dismiss Alert"] → Security/Alert dismissed, spring.brisk
    → return to Security/Default
```

---

### Flow 5: Health Score Drill-Down

```
START: Mobile/D3-Dashboard/Home/Loaded

FLOW:
  Dashboard/Home
    → [tap Health Hero Card] → D4-Property/Health/Default, spring.smooth
  Property/Health
    → [tap "Maintenance" factor row] → D11-Maintenance/Center/Default, slide-left
  Maintenance/Center
    → [tap task row] → Maintenance/TaskDetail/Default, slide-left
  TaskDetail
    → [tap "Mark Complete"] → TaskDetail/Completing → TaskDetail/Completed
    → [return] → Maintenance/Center/Updated (task removed from list)
    → [return] → Property/Health/Updated (score animated up to 86)
    → [return] → Dashboard/Home/Updated (ring animates to 86)
```

---

## D17 — EXPORT ASSETS

### Icon Export Specifications

```
FORMAT: SVG (source) + PNG (1×, 2×, 3×)

EXPORT SIZES:
  App Icon: 1024×1024px, PNG (Apple required)
  Android Adaptive: 108×108px foreground + background layers
  Favicon: 32×32, 16×16
  Social preview: 1200×630px

MODULE ICONS (all 12):
  Export: SVG, 24px canvas, named: icon-[module].svg
  
CUSTOM ILLUSTRATIONS:
  Onboarding scenes: SVG
  Empty states: SVG
  ARIA avatar: SVG (animated version in Lottie JSON)

LPBE BACKGROUNDS:
  Static fallback images for each time-of-day state: 2 per state × 2 seasons = 28 images
  Dimensions: 1920×1080px, JPG 85% quality
  Naming: lpbe-[time]-[season]-[variant].jpg
  
LOADING/SKELETON:
  Not exported — CSS only
  
HEALTH RING ILLUSTRATIONS:
  5 states: exported as SVG (excellent, good, fair, poor, critical)
```

---

### Design Token Export (Figma → Code)

```
EXPORT METHOD: Figma Tokens plugin or Token Studio

OUTPUT FORMAT: JSON → fed into Style Dictionary for CSS/JS/Swift/Kotlin

FILE STRUCTURE (generated):
  tokens/
  ├── colors.dark.json
  ├── colors.light.json
  ├── colors.module.json
  ├── spacing.json
  ├── radius.json
  ├── typography.json
  ├── shadow.json
  ├── motion.json
  └── index.json

STYLE DICTIONARY CONFIG generates:
  → CSS custom properties  (web)
  → Tailwind config        (Next.js)
  → Swift UIColor + Font   (iOS)
  → Android resources      (Android)
  → Kotlin objects         (Compose)
```

---

## D18 — HANDOFF CHECKLIST

### For Each Screen, Verify:

```
□ Frame dimensions correct (390 mobile / 820 tablet / 1440 desktop)
□ Safe area insets applied (top + bottom on all mobile frames)
□ All text layers use type styles (not manual font settings)
□ All colors use variable references (not hex literals)
□ All effects use effect styles
□ All spacing uses spacing variables
□ Auto Layout on all groups (no manual positioning)
□ Touch targets minimum 44×44px on all interactive elements
□ Component instances used (not detached)
□ All states included (default, hover, focused, pressed, disabled, loading)
□ Prototype connections from all interactive elements
□ Screen reader labels set on all components
□ Accessibility notes written in component description
□ Layer names are descriptive (no "Frame 523")
□ Dark and light mode verified via variable mode swap
□ Reduced motion variant verified (static, no animation layers active)
```

---

### Designer → Developer Handoff Notes

```
GLASS EFFECTS:
  All backdrop-filter values are specified in Phase C.
  Reduce transparency fallback: replace glass with solid bg-surface.
  Safari requires -webkit-backdrop-filter prefix.

SPRING ANIMATIONS:
  All spring tokens in Phase C (C7) map to Framer Motion spring configs.
  React Native uses react-native-reanimated with withSpring.
  CSS fallback easing tokens provided for non-JS contexts.

LIVING BACKGROUND:
  Phase B (B0–B3) and LPBE palette in Phase C fully specify the engine.
  Static background image fallback: use nearest lpbe-*.jpg.
  Time-aware rendering requires device clock + property coordinates.

FONTS:
  SF Pro is system font on Apple devices (no download needed).
  Geist is open-source, load from vercel.com/font.
  Inter is fallback — load from Google Fonts or bundle.

ICONS:
  SF Symbols used on iOS/macOS only — use Lucide elsewhere.
  All 24px SVGs from Lucide are in /assets/icons/.
  Module identifier glyphs are custom — in /assets/icons/modules/.

HEALTH RING:
  Implemented as SVG with animated strokeDashoffset.
  Do not use CSS border-radius tricks — must be true arc.
  Color interpolation between health states uses HSL lerp.
```

---

*End of Phase D — Figma Master Package*  
*Version 1.0 — Complete screen specifications, component hierarchy, prototype flows, export guidelines*

---

## PHASE COMPLETION SUMMARY

All four phases are now complete:

| Phase | Document | Status |
|---|---|---|
| A — Product Blueprint | PHASE_A_PRODUCT_BLUEPRINT.md | ✓ Complete |
| B — Glass OS Master Design | PHASE_B_GLASS_OS_DESIGN.md | ✓ Complete |
| C — Design System | PHASE_C_DESIGN_SYSTEM.md | ✓ Complete |
| D — Figma Master Package | PHASE_D_FIGMA_PACKAGE.md | ✓ Complete |

**Ready for review and approval. Upon approval, proceed to:**
1. Database Architecture (Supabase schema, RLS policies, indexes)
2. API Architecture (REST + Realtime endpoints, auth middleware)
3. React / Next.js 15 Application (web)
4. React Native + Expo Application (mobile)
