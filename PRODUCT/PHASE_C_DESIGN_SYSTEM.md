# PHASE C — GLASS OS™ DESIGN SYSTEM
## PRV HOUSE — The Property Operating System
### Complete Design Token & Component Specification

**Version:** 1.0  
**Status:** Active  
**Depends on:** Phase A (Product Blueprint), Phase B (Glass OS Master Design)

---

## TABLE OF CONTENTS

- [C0 — Design Principles](#c0--design-principles)
- [C1 — Design Tokens: Foundation](#c1--design-tokens-foundation)
- [C2 — Color System](#c2--color-system)
- [C3 — Typography System](#c3--typography-system)
- [C4 — Spacing & Layout](#c4--spacing--layout)
- [C5 — Elevation & Depth](#c5--elevation--depth)
- [C6 — Glass Physics](#c6--glass-physics)
- [C7 — Motion System](#c7--motion-system)
- [C8 — Iconography](#c8--iconography)
- [C9 — Component Library: Atoms](#c9--component-library-atoms)
- [C10 — Component Library: Molecules](#c10--component-library-molecules)
- [C11 — Component Library: Organisms](#c11--component-library-organisms)
- [C12 — Component Library: Templates](#c12--component-library-templates)
- [C13 — Dark Mode System](#c13--dark-mode-system)
- [C14 — Light Mode System](#c14--light-mode-system)
- [C15 — Accessibility System](#c15--accessibility-system)
- [C16 — Responsive System](#c16--responsive-system)

---

## C0 — DESIGN PRINCIPLES

### The Seven Laws of GLASS OS™

**Law 1 — Depth Before Flatness**  
Every surface exists at a specific depth in the Z-axis. Nothing is flat; everything is a layer in a living environment. Background breathes, midground holds data, foreground speaks.

**Law 2 — Glass Reveals, Never Hides**  
Glass panels are translucent, not opaque. The property environment always bleeds through. A surface that hides its background is not glass — it is a wall.

**Law 3 — Physics Is Non-Negotiable**  
Every element obeys spring physics. Snap, sway, settle. No linear easing. No cubic-bezier shortcuts. The UI has mass, friction, and elasticity.

**Law 4 — Light Follows Reality**  
The design adapts to the time of day, season, and weather of the actual property. A winter dawn looks different from a summer noon. The system knows.

**Law 5 — Information Has Hierarchy**  
Data is served in order of urgency. Critical → High → Normal → Ambient. The glass layer a piece of information lives on determines its visual weight.

**Law 6 — Touch Is Spatial**  
Long-press reveals depth. Swipe navigates layers. Pinch zooms into the digital twin. The interaction model mirrors physical space manipulation.

**Law 7 — Accessibility Is Not a Feature, It's a Foundation**  
Every design decision passes through WCAG 2.2 AA before any aesthetic choice. Contrast, motion reduction, haptics, voice — all are first-class, not afterthoughts.

---

### Design Language Keywords

```
GLASS · DEPTH · PHYSICS · LIVE · SPATIAL · CALM · PRECISE · WARM · INTELLIGENT
```

---

## C1 — DESIGN TOKENS: FOUNDATION

### Token Naming Convention

```
{category}-{subcategory}-{variant}-{state}

Examples:
  color-surface-glass-default
  space-inset-md
  radius-card-lg
  motion-spring-standard
  shadow-elevation-3
  glass-blur-heavy
```

### Token Tiers

```
TIER 1 — Primitive Tokens (raw values, never used directly in components)
TIER 2 — Semantic Tokens (purpose-named aliases of primitives)
TIER 3 — Component Tokens (component-scoped aliases of semantic tokens)
```

---

### Border Radius Tokens

```css
/* Primitive */
--radius-0:   0px;
--radius-1:   4px;
--radius-2:   8px;
--radius-3:   12px;
--radius-4:   16px;
--radius-5:   20px;
--radius-6:   24px;
--radius-7:   32px;
--radius-8:   40px;
--radius-9:   48px;
--radius-full: 9999px;

/* Semantic */
--radius-chip:       var(--radius-full);   /* Tags, status pills */
--radius-button:     var(--radius-3);      /* All buttons */
--radius-button-sm:  var(--radius-2);      /* Small/icon buttons */
--radius-input:      var(--radius-3);      /* Form inputs */
--radius-card:       var(--radius-5);      /* Standard cards */
--radius-card-lg:    var(--radius-7);      /* Hero cards, featured panels */
--radius-modal:      var(--radius-7);      /* Bottom sheets, modals */
--radius-modal-lg:   var(--radius-8);      /* Full-page overlays */
--radius-panel:      var(--radius-4);      /* Sidebar panels, inline panels */
--radius-avatar:     var(--radius-full);   /* User avatars */
--radius-avatar-sq:  var(--radius-3);      /* Square avatars (property images) */
--radius-badge:      var(--radius-full);   /* Notification badges */
--radius-toast:      var(--radius-4);      /* Toast notifications */
--radius-tooltip:    var(--radius-2);      /* Tooltips */
--radius-fab:        var(--radius-full);   /* Floating action buttons */
```

---

### Border Width Tokens

```css
/* Primitive */
--border-0:   0px;
--border-1:   0.5px;    /* Hairline — retina only */
--border-2:   1px;      /* Standard thin */
--border-3:   1.5px;    /* Medium */
--border-4:   2px;      /* Bold */

/* Semantic */
--border-glass:        var(--border-2);     /* Glass panel edges */
--border-glass-inner:  var(--border-1);     /* Inner glass dividers */
--border-input:        var(--border-2);     /* Form input borders */
--border-input-focus:  var(--border-3);     /* Focused input */
--border-card:         var(--border-1);     /* Card hairlines */
--border-divider:      var(--border-1);     /* List dividers */
--border-focus-ring:   var(--border-4);     /* Keyboard focus ring */
```

---

### Z-Index Tokens

```css
/* Layer System — matches GLASS OS 7 layers */
--z-environment:   0;      /* Z-0: Living background */
--z-background:    10;     /* Z-1: Secondary backgrounds */
--z-surface:       20;     /* Z-2: Primary surfaces */
--z-elevated:      30;     /* Z-3: Elevated cards */
--z-floating:      40;     /* Z-4: Floating panels */
--z-overlay:       50;     /* Z-5: Overlays, modals */
--z-critical:      60;     /* Z-6: Critical alerts */
--z-system:        70;     /* Z-7: System chrome */

/* Application-level additions */
--z-dropdown:      35;
--z-tooltip:       65;
--z-toast:         68;
--z-sidebar:       25;
--z-header:        22;
--z-fab:           38;
--z-drawer:        45;
--z-fullscreen:    55;
```

---

### Opacity Tokens

```css
/* Primitive */
--opacity-0:    0;
--opacity-4:    0.04;
--opacity-8:    0.08;
--opacity-12:   0.12;
--opacity-16:   0.16;
--opacity-20:   0.20;
--opacity-24:   0.24;
--opacity-32:   0.32;
--opacity-40:   0.40;
--opacity-48:   0.48;
--opacity-56:   0.56;
--opacity-64:   0.64;
--opacity-72:   0.72;
--opacity-80:   0.80;
--opacity-88:   0.88;
--opacity-92:   0.92;
--opacity-96:   0.96;
--opacity-100:  1;

/* Semantic */
--opacity-glass-surface:     var(--opacity-12);   /* Glass panel fill */
--opacity-glass-heavy:       var(--opacity-24);   /* Heavy glass */
--opacity-glass-border:      var(--opacity-20);   /* Glass border */
--opacity-glass-border-top:  var(--opacity-32);   /* Top highlight */
--opacity-glass-tint:        var(--opacity-8);    /* Module color tint */
--opacity-overlay:           var(--opacity-48);   /* Modal scrim */
--opacity-overlay-heavy:     var(--opacity-64);   /* Full-page scrim */
--opacity-disabled:          var(--opacity-40);   /* Disabled states */
--opacity-placeholder:       var(--opacity-40);   /* Input placeholder */
--opacity-skeleton:          var(--opacity-12);   /* Loading skeleton */
--opacity-hover:             var(--opacity-8);    /* Hover overlay */
--opacity-pressed:           var(--opacity-16);   /* Press state */
--opacity-focus:             var(--opacity-20);   /* Focus ring fill */
--opacity-selected:          var(--opacity-12);   /* Selected state fill */
```

---

## C2 — COLOR SYSTEM

### Palette Architecture

```
GLASS OS Color System
├── Neutral Scale (13 steps: N0–N1200)
├── Module Colors (12 unique hues)
├── Semantic Colors (status, feedback, state)
├── Glass Tints (module × mode × intensity)
├── Gradient Library
└── Living Background Palette (LPBE sky colors)
```

---

### Neutral Scale

```css
/* Pure Neutrals — HSL-based for consistent lightness */
--neutral-0:     hsl(220, 15%, 98%);   /* #F7F8FA — Near white */
--neutral-50:    hsl(220, 14%, 96%);   /* #F2F4F7 */
--neutral-100:   hsl(220, 13%, 91%);   /* #E6E9F0 */
--neutral-200:   hsl(220, 12%, 84%);   /* #D1D6E3 */
--neutral-300:   hsl(220, 11%, 72%);   /* #AEB7CC */
--neutral-400:   hsl(220, 10%, 58%);   /* #8A95AE */
--neutral-500:   hsl(220, 9%, 46%);    /* #6B778F */
--neutral-600:   hsl(220, 10%, 36%);   /* #515D75 */
--neutral-700:   hsl(220, 12%, 28%);   /* #3C4A62 */
--neutral-800:   hsl(220, 14%, 20%);   /* #2A3548 */
--neutral-900:   hsl(220, 16%, 14%);   /* #1C2535 */
--neutral-1000:  hsl(220, 18%, 10%);   /* #141C2B */
--neutral-1100:  hsl(220, 20%, 7%);    /* #0D1420 */
--neutral-1200:  hsl(220, 22%, 4%);    /* #080E18 */

/* Warm Neutrals — for text and surfaces */
--warm-0:    hsl(40, 20%, 98%);    /* #FAFAF8 */
--warm-50:   hsl(40, 18%, 95%);    /* #F5F4F0 */
--warm-100:  hsl(40, 15%, 89%);    /* #E8E5DC */
--warm-200:  hsl(40, 12%, 78%);    /* #CCC7B8 */
--warm-300:  hsl(40, 10%, 62%);    /* #A39D90 */
--warm-400:  hsl(40, 9%, 48%);     /* #7D796E */
--warm-500:  hsl(40, 8%, 36%);     /* #5D5A52 */
```

---

### Module Color System

Each of the 12 modules has a distinct hue. Every module color has 5 weights (100–900) for use across both light and dark modes.

```css
/* MODULE 1 — HOME DASHBOARD — Azure Blue */
--module-home-100:  hsl(210, 90%, 92%);   /* #D6EEFF */
--module-home-200:  hsl(210, 85%, 80%);   /* #9DD3FF */
--module-home-300:  hsl(210, 80%, 65%);   /* #5EAEFF */
--module-home-400:  hsl(210, 75%, 52%);   /* #2E8FEC */
--module-home-500:  hsl(210, 75%, 42%);   /* #1470C4 */  /* Primary */
--module-home-600:  hsl(210, 75%, 33%);   /* #0D569A */
--module-home-700:  hsl(210, 75%, 25%);   /* #093F73 */
--module-home-800:  hsl(210, 75%, 16%);   /* #06284A */
--module-home-900:  hsl(210, 75%, 10%);   /* #04192E */

/* MODULE 2 — PROPERTY — Warm Amber */
--module-property-100:  hsl(36, 90%, 92%);
--module-property-200:  hsl(36, 85%, 80%);
--module-property-300:  hsl(36, 80%, 65%);
--module-property-400:  hsl(36, 78%, 52%);
--module-property-500:  hsl(36, 75%, 42%);   /* Primary */
--module-property-600:  hsl(36, 75%, 33%);
--module-property-700:  hsl(36, 75%, 25%);
--module-property-800:  hsl(36, 75%, 16%);
--module-property-900:  hsl(36, 75%, 10%);

/* MODULE 3 — DIGITAL TWIN — Electric Indigo */
--module-twin-100:  hsl(252, 90%, 94%);
--module-twin-200:  hsl(252, 85%, 84%);
--module-twin-300:  hsl(252, 80%, 70%);
--module-twin-400:  hsl(252, 75%, 57%);
--module-twin-500:  hsl(252, 72%, 47%);   /* Primary */
--module-twin-600:  hsl(252, 72%, 37%);
--module-twin-700:  hsl(252, 72%, 27%);
--module-twin-800:  hsl(252, 72%, 18%);
--module-twin-900:  hsl(252, 72%, 11%);

/* MODULE 4 — FAMILY — Rose Pink */
--module-family-100:  hsl(340, 85%, 93%);
--module-family-200:  hsl(340, 80%, 83%);
--module-family-300:  hsl(340, 75%, 70%);
--module-family-400:  hsl(340, 70%, 57%);
--module-family-500:  hsl(340, 68%, 46%);   /* Primary */
--module-family-600:  hsl(340, 68%, 36%);
--module-family-700:  hsl(340, 68%, 26%);
--module-family-800:  hsl(340, 68%, 17%);
--module-family-900:  hsl(340, 68%, 10%);

/* MODULE 5 — ARIA AI — Violet */
--module-aria-100:  hsl(280, 85%, 94%);
--module-aria-200:  hsl(280, 80%, 84%);
--module-aria-300:  hsl(280, 75%, 71%);
--module-aria-400:  hsl(280, 70%, 58%);
--module-aria-500:  hsl(280, 68%, 47%);   /* Primary */
--module-aria-600:  hsl(280, 68%, 37%);
--module-aria-700:  hsl(280, 68%, 27%);
--module-aria-800:  hsl(280, 68%, 18%);
--module-aria-900:  hsl(280, 68%, 11%);

/* MODULE 6 — SECURITY — Crimson Red */
--module-security-100:  hsl(0, 85%, 93%);
--module-security-200:  hsl(0, 80%, 82%);
--module-security-300:  hsl(0, 75%, 68%);
--module-security-400:  hsl(0, 70%, 55%);
--module-security-500:  hsl(0, 68%, 44%);   /* Primary */
--module-security-600:  hsl(0, 68%, 34%);
--module-security-700:  hsl(0, 68%, 25%);
--module-security-800:  hsl(0, 68%, 16%);
--module-security-900:  hsl(0, 68%, 10%);

/* MODULE 7 — ENERGY — Emerald Green */
--module-energy-100:  hsl(152, 80%, 92%);
--module-energy-200:  hsl(152, 75%, 80%);
--module-energy-300:  hsl(152, 70%, 65%);
--module-energy-400:  hsl(152, 65%, 50%);
--module-energy-500:  hsl(152, 62%, 38%);   /* Primary */
--module-energy-600:  hsl(152, 62%, 29%);
--module-energy-700:  hsl(152, 62%, 21%);
--module-energy-800:  hsl(152, 62%, 14%);
--module-energy-900:  hsl(152, 62%, 8%);

/* MODULE 8 — INVENTORY / M-SCAN — Teal */
--module-inventory-100:  hsl(185, 80%, 92%);
--module-inventory-200:  hsl(185, 75%, 80%);
--module-inventory-300:  hsl(185, 70%, 64%);
--module-inventory-400:  hsl(185, 65%, 49%);
--module-inventory-500:  hsl(185, 62%, 38%);   /* Primary */
--module-inventory-600:  hsl(185, 62%, 29%);
--module-inventory-700:  hsl(185, 62%, 21%);
--module-inventory-800:  hsl(185, 62%, 14%);
--module-inventory-900:  hsl(185, 62%, 9%);

/* MODULE 9 — MAINTENANCE — Burnt Orange */
--module-maintenance-100:  hsl(22, 85%, 93%);
--module-maintenance-200:  hsl(22, 80%, 82%);
--module-maintenance-300:  hsl(22, 75%, 67%);
--module-maintenance-400:  hsl(22, 70%, 53%);
--module-maintenance-500:  hsl(22, 68%, 41%);   /* Primary */
--module-maintenance-600:  hsl(22, 68%, 32%);
--module-maintenance-700:  hsl(22, 68%, 23%);
--module-maintenance-800:  hsl(22, 68%, 15%);
--module-maintenance-900:  hsl(22, 68%, 9%);

/* MODULE 10 — FINANCES — Gold */
--module-finances-100:  hsl(45, 90%, 92%);
--module-finances-200:  hsl(45, 85%, 80%);
--module-finances-300:  hsl(45, 80%, 65%);
--module-finances-400:  hsl(45, 78%, 52%);
--module-finances-500:  hsl(45, 75%, 42%);   /* Primary */
--module-finances-600:  hsl(45, 75%, 33%);
--module-finances-700:  hsl(45, 75%, 24%);
--module-finances-800:  hsl(45, 75%, 16%);
--module-finances-900:  hsl(45, 75%, 10%);

/* MODULE 11 — DOCUMENTS — Slate Blue */
--module-documents-100:  hsl(220, 70%, 93%);
--module-documents-200:  hsl(220, 65%, 83%);
--module-documents-300:  hsl(220, 60%, 70%);
--module-documents-400:  hsl(220, 55%, 57%);
--module-documents-500:  hsl(220, 52%, 46%);   /* Primary */
--module-documents-600:  hsl(220, 52%, 36%);
--module-documents-700:  hsl(220, 52%, 26%);
--module-documents-800:  hsl(220, 52%, 17%);
--module-documents-900:  hsl(220, 52%, 10%);

/* MODULE 12 — MARKETPLACE — Lime Green */
--module-marketplace-100:  hsl(88, 75%, 92%);
--module-marketplace-200:  hsl(88, 70%, 80%);
--module-marketplace-300:  hsl(88, 65%, 65%);
--module-marketplace-400:  hsl(88, 60%, 50%);
--module-marketplace-500:  hsl(88, 58%, 39%);   /* Primary */
--module-marketplace-600:  hsl(88, 58%, 30%);
--module-marketplace-700:  hsl(88, 58%, 22%);
--module-marketplace-800:  hsl(88, 58%, 14%);
--module-marketplace-900:  hsl(88, 58%, 9%);
```

---

### Semantic Color Tokens

```css
/* Status Colors */
--color-status-success-light:  hsl(152, 65%, 48%);
--color-status-success-dark:   hsl(152, 70%, 42%);
--color-status-warning-light:  hsl(38, 90%, 50%);
--color-status-warning-dark:   hsl(38, 85%, 55%);
--color-status-danger-light:   hsl(0, 70%, 52%);
--color-status-danger-dark:    hsl(0, 75%, 58%);
--color-status-info-light:     hsl(210, 75%, 50%);
--color-status-info-dark:      hsl(210, 80%, 60%);
--color-status-neutral-light:  hsl(220, 12%, 54%);
--color-status-neutral-dark:   hsl(220, 12%, 62%);

/* Status Surface Colors (background fills) */
--color-status-success-surface-light:  hsl(152, 65%, 94%);
--color-status-success-surface-dark:   hsl(152, 40%, 14%);
--color-status-warning-surface-light:  hsl(38, 90%, 94%);
--color-status-warning-surface-dark:   hsl(38, 50%, 14%);
--color-status-danger-surface-light:   hsl(0, 70%, 94%);
--color-status-danger-surface-dark:    hsl(0, 50%, 14%);
--color-status-info-surface-light:     hsl(210, 75%, 94%);
--color-status-info-surface-dark:      hsl(210, 50%, 14%);

/* Property Health Score Colors */
--color-health-excellent:  hsl(152, 70%, 42%);   /* 85–100 */
--color-health-good:       hsl(96, 65%, 42%);    /* 70–84 */
--color-health-fair:       hsl(45, 80%, 48%);    /* 50–69 */
--color-health-poor:       hsl(22, 75%, 48%);    /* 25–49 */
--color-health-critical:   hsl(0, 70%, 50%);     /* 0–24 */

/* Interactive States */
--color-interactive-focus:    hsl(210, 90%, 55%);    /* Focus ring */
--color-interactive-hover:    rgba(255, 255, 255, 0.08);
--color-interactive-pressed:  rgba(255, 255, 255, 0.16);
--color-interactive-selected: rgba(255, 255, 255, 0.12);
--color-interactive-drag:     rgba(255, 255, 255, 0.20);
```

---

### Dark Mode Color Roles

```css
[data-theme="dark"] {
  /* Background layers */
  --color-bg-environment:   var(--neutral-1200);   /* Living background base */
  --color-bg-base:          var(--neutral-1100);   /* App shell */
  --color-bg-surface:       var(--neutral-1000);   /* Card surface */
  --color-bg-elevated:      var(--neutral-900);    /* Elevated card */
  --color-bg-floating:      var(--neutral-800);    /* Floating panel */
  --color-bg-overlay:       rgba(8, 14, 24, 0.80); /* Modal backdrop */
  
  /* Glass surfaces */
  --color-glass-fill:       rgba(255, 255, 255, 0.06);
  --color-glass-fill-heavy: rgba(255, 255, 255, 0.10);
  --color-glass-border:     rgba(255, 255, 255, 0.12);
  --color-glass-border-top: rgba(255, 255, 255, 0.24);
  --color-glass-shine:      rgba(255, 255, 255, 0.04);
  
  /* Text */
  --color-text-primary:     hsl(220, 15%, 94%);   /* #EEF0F5 */
  --color-text-secondary:   hsl(220, 10%, 68%);   /* #A6AEBA */
  --color-text-tertiary:    hsl(220, 8%, 48%);    /* #72798A */
  --color-text-disabled:    hsl(220, 6%, 34%);    /* #515866 */
  --color-text-inverse:     hsl(220, 20%, 8%);    /* For light backgrounds */
  --color-text-link:        hsl(210, 85%, 65%);
  --color-text-link-hover:  hsl(210, 85%, 75%);
  
  /* Icons */
  --color-icon-primary:     hsl(220, 12%, 88%);
  --color-icon-secondary:   hsl(220, 10%, 60%);
  --color-icon-tertiary:    hsl(220, 8%, 42%);
  --color-icon-disabled:    hsl(220, 6%, 32%);
  
  /* Borders */
  --color-border-subtle:    rgba(255, 255, 255, 0.06);
  --color-border-default:   rgba(255, 255, 255, 0.10);
  --color-border-strong:    rgba(255, 255, 255, 0.18);
  --color-border-focus:     hsl(210, 90%, 60%);
}
```

---

### Light Mode Color Roles

```css
[data-theme="light"] {
  /* Background layers */
  --color-bg-environment:   var(--neutral-50);
  --color-bg-base:          var(--neutral-0);
  --color-bg-surface:       #FFFFFF;
  --color-bg-elevated:      #FFFFFF;
  --color-bg-floating:      #FFFFFF;
  --color-bg-overlay:       rgba(8, 14, 24, 0.50);
  
  /* Glass surfaces */
  --color-glass-fill:       rgba(255, 255, 255, 0.55);
  --color-glass-fill-heavy: rgba(255, 255, 255, 0.75);
  --color-glass-border:     rgba(255, 255, 255, 0.80);
  --color-glass-border-top: rgba(255, 255, 255, 0.95);
  --color-glass-shine:      rgba(255, 255, 255, 0.40);
  
  /* Text */
  --color-text-primary:     hsl(220, 20%, 12%);
  --color-text-secondary:   hsl(220, 12%, 36%);
  --color-text-tertiary:    hsl(220, 8%, 54%);
  --color-text-disabled:    hsl(220, 6%, 68%);
  --color-text-inverse:     hsl(220, 15%, 96%);
  --color-text-link:        hsl(210, 80%, 40%);
  --color-text-link-hover:  hsl(210, 80%, 30%);
  
  /* Icons */
  --color-icon-primary:     hsl(220, 18%, 16%);
  --color-icon-secondary:   hsl(220, 12%, 40%);
  --color-icon-tertiary:    hsl(220, 8%, 58%);
  --color-icon-disabled:    hsl(220, 6%, 70%);
  
  /* Borders */
  --color-border-subtle:    rgba(0, 0, 0, 0.06);
  --color-border-default:   rgba(0, 0, 0, 0.10);
  --color-border-strong:    rgba(0, 0, 0, 0.18);
  --color-border-focus:     hsl(210, 85%, 42%);
}
```

---

### Living Background Palette (LPBE)

```css
/* Sky gradient stops used by Living Property Background Engine */

/* Dawn (05:00–06:30) */
--lpbe-dawn-horizon:  hsl(22, 75%, 55%);     /* Warm peach */
--lpbe-dawn-mid:      hsl(30, 60%, 70%);     /* Pale orange */
--lpbe-dawn-zenith:   hsl(210, 45%, 35%);    /* Deep blue */

/* Morning (06:30–10:00) */
--lpbe-morning-horizon:  hsl(195, 65%, 72%);  /* Sky blue */
--lpbe-morning-mid:      hsl(205, 55%, 82%);
--lpbe-morning-zenith:   hsl(210, 70%, 45%);

/* Midday (10:00–14:00) */
--lpbe-midday-horizon:   hsl(200, 60%, 78%);
--lpbe-midday-mid:       hsl(205, 65%, 85%);
--lpbe-midday-zenith:    hsl(215, 75%, 42%);  /* Deep blue sky */

/* Afternoon (14:00–18:00) */
--lpbe-afternoon-horizon: hsl(195, 55%, 70%);
--lpbe-afternoon-mid:     hsl(200, 50%, 78%);
--lpbe-afternoon-zenith:  hsl(210, 65%, 40%);

/* Golden Hour (18:00–19:30) */
--lpbe-golden-horizon:    hsl(32, 85%, 58%);  /* Gold */
--lpbe-golden-mid:        hsl(20, 70%, 60%);  /* Warm orange */
--lpbe-golden-zenith:     hsl(260, 40%, 35%); /* Dusk purple */

/* Dusk (19:30–21:00) */
--lpbe-dusk-horizon:      hsl(12, 65%, 48%);  /* Deep orange */
--lpbe-dusk-mid:          hsl(280, 35%, 30%); /* Purple */
--lpbe-dusk-zenith:       hsl(240, 35%, 15%); /* Dark navy */

/* Night (21:00–04:00) */
--lpbe-night-horizon:     hsl(235, 30%, 12%);
--lpbe-night-mid:         hsl(230, 28%, 8%);
--lpbe-night-zenith:      hsl(225, 25%, 5%);  /* Near black */

/* Winter variants — desaturated + cooler */
--lpbe-winter-offset-hue:   -15deg;
--lpbe-winter-offset-sat:   -20%;
--lpbe-winter-offset-light: -8%;

/* Summer variants — saturated + warmer */
--lpbe-summer-offset-hue:   +5deg;
--lpbe-summer-offset-sat:   +10%;
--lpbe-summer-offset-light: +5%;

/* Overcast — drastically desaturated */
--lpbe-overcast-sat: 10%;
--lpbe-overcast-light-boost: 15%;

/* Rain */
--lpbe-rain-sat: 15%;
--lpbe-rain-dark-offset: -20%;
```

---

## C3 — TYPOGRAPHY SYSTEM

### Font Stack

```css
/* Primary — SF Pro / Geist (system-native feel) */
--font-sans: 
  "SF Pro Display",
  "SF Pro Text",
  -apple-system,
  BlinkMacSystemFont,
  "Geist",
  "Inter",
  system-ui,
  sans-serif;

/* Monospace — for data, timestamps, addresses */
--font-mono:
  "SF Mono",
  "Geist Mono",
  "Fira Code",
  "Cascadia Code",
  ui-monospace,
  monospace;

/* Numeric — tabular figures for all numbers */
--font-numeric: var(--font-sans);
--font-feature-numeric: "tnum" 1, "zero" 1, "lnum" 1;

/* Display — hero headings only */
--font-display: var(--font-sans);
--font-feature-display: "ss01" 1, "cv01" 1;
```

---

### Type Scale

```css
/* Scale base: 16px, ratio 1.250 (Major Third) */

--text-2xs:   10px;   /* line-height: 14px — badges, micro labels */
--text-xs:    12px;   /* line-height: 16px — captions, metadata */
--text-sm:    13px;   /* line-height: 18px — secondary body, labels */
--text-base:  15px;   /* line-height: 22px — primary body text */
--text-md:    17px;   /* line-height: 24px — emphasized body */
--text-lg:    20px;   /* line-height: 28px — subheadings */
--text-xl:    24px;   /* line-height: 32px — section headers */
--text-2xl:   28px;   /* line-height: 36px — page titles */
--text-3xl:   34px;   /* line-height: 42px — hero titles */
--text-4xl:   40px;   /* line-height: 48px — display large */
--text-5xl:   48px;   /* line-height: 56px — display hero */
--text-6xl:   60px;   /* line-height: 68px — splash only */
--text-7xl:   72px;   /* line-height: 80px — onboarding hero */
```

---

### Font Weight Scale

```css
--weight-thin:       100;
--weight-extralight: 200;
--weight-light:      300;
--weight-regular:    400;
--weight-medium:     500;
--weight-semibold:   600;
--weight-bold:       700;
--weight-extrabold:  800;
--weight-black:      900;

/* Semantic weight roles */
--weight-body:       var(--weight-regular);
--weight-label:      var(--weight-medium);
--weight-emphasis:   var(--weight-semibold);
--weight-heading:    var(--weight-semibold);
--weight-display:    var(--weight-bold);
--weight-hero:       var(--weight-black);
--weight-numeric:    var(--weight-medium);  /* Numbers always medium+ */
--weight-button:     var(--weight-semibold);
--weight-badge:      var(--weight-bold);
```

---

### Letter Spacing Scale

```css
--tracking-tighter: -0.04em;   /* Hero display text */
--tracking-tight:   -0.02em;   /* Headings */
--tracking-snug:    -0.01em;   /* Subheadings */
--tracking-normal:   0em;      /* Body text */
--tracking-wide:     0.02em;   /* Uppercase labels */
--tracking-wider:    0.04em;   /* Caps, badges */
--tracking-widest:   0.08em;   /* Module title caps */
```

---

### Type Roles — Semantic Aliases

```css
/* Display */
--type-display-hero: {
  font-size: var(--text-7xl);
  font-weight: var(--weight-black);
  letter-spacing: var(--tracking-tighter);
  line-height: 80px;
}

--type-display-large: {
  font-size: var(--text-5xl);
  font-weight: var(--weight-bold);
  letter-spacing: var(--tracking-tight);
  line-height: 56px;
}

/* Headings */
--type-h1: { font-size: var(--text-3xl); font-weight: var(--weight-bold);     letter-spacing: var(--tracking-tight);  line-height: 42px; }
--type-h2: { font-size: var(--text-2xl); font-weight: var(--weight-semibold);  letter-spacing: var(--tracking-tight);  line-height: 36px; }
--type-h3: { font-size: var(--text-xl);  font-weight: var(--weight-semibold);  letter-spacing: var(--tracking-snug);   line-height: 32px; }
--type-h4: { font-size: var(--text-lg);  font-weight: var(--weight-semibold);  letter-spacing: var(--tracking-normal); line-height: 28px; }
--type-h5: { font-size: var(--text-md);  font-weight: var(--weight-medium);    letter-spacing: var(--tracking-normal); line-height: 24px; }
--type-h6: { font-size: var(--text-base); font-weight: var(--weight-medium);   letter-spacing: var(--tracking-normal); line-height: 22px; }

/* Body */
--type-body-lg:   { font-size: var(--text-md);   font-weight: var(--weight-regular); line-height: 26px; }
--type-body:      { font-size: var(--text-base);  font-weight: var(--weight-regular); line-height: 22px; }
--type-body-sm:   { font-size: var(--text-sm);    font-weight: var(--weight-regular); line-height: 18px; }
--type-body-xs:   { font-size: var(--text-xs);    font-weight: var(--weight-regular); line-height: 16px; }

/* Labels */
--type-label-lg:  { font-size: var(--text-sm);   font-weight: var(--weight-semibold); letter-spacing: var(--tracking-wide); text-transform: uppercase; }
--type-label:     { font-size: var(--text-xs);   font-weight: var(--weight-semibold); letter-spacing: var(--tracking-wider); text-transform: uppercase; }
--type-label-sm:  { font-size: var(--text-2xs);  font-weight: var(--weight-bold);     letter-spacing: var(--tracking-widest); text-transform: uppercase; }

/* Numeric */
--type-numeric-lg: { font-size: var(--text-3xl); font-weight: var(--weight-bold);   font-variant-numeric: tabular-nums; letter-spacing: var(--tracking-tight); }
--type-numeric:    { font-size: var(--text-xl);  font-weight: var(--weight-medium);  font-variant-numeric: tabular-nums; }
--type-numeric-sm: { font-size: var(--text-lg);  font-weight: var(--weight-medium);  font-variant-numeric: tabular-nums; }

/* Code / Mono */
--type-code: { font-family: var(--font-mono); font-size: var(--text-sm); font-weight: var(--weight-regular); }
--type-mono: { font-family: var(--font-mono); font-variant-numeric: tabular-nums slashed-zero; }
```

---

## C4 — SPACING & LAYOUT

### Spacing Scale

```css
/* Base unit: 4px */
--space-0:    0px;
--space-0-5:  2px;
--space-1:    4px;
--space-1-5:  6px;
--space-2:    8px;
--space-2-5:  10px;
--space-3:    12px;
--space-3-5:  14px;
--space-4:    16px;
--space-5:    20px;
--space-6:    24px;
--space-7:    28px;
--space-8:    32px;
--space-9:    36px;
--space-10:   40px;
--space-12:   48px;
--space-14:   56px;
--space-16:   64px;
--space-20:   80px;
--space-24:   96px;
--space-28:   112px;
--space-32:   128px;
--space-40:   160px;
--space-48:   192px;
--space-56:   224px;
--space-64:   256px;
```

---

### Semantic Spacing Tokens

```css
/* Inset (padding inside components) */
--inset-2xs:  var(--space-1) var(--space-2);         /* 4px 8px */
--inset-xs:   var(--space-1-5) var(--space-3);       /* 6px 12px */
--inset-sm:   var(--space-2) var(--space-4);         /* 8px 16px */
--inset-md:   var(--space-3) var(--space-4);         /* 12px 16px */
--inset-lg:   var(--space-4) var(--space-6);         /* 16px 24px */
--inset-xl:   var(--space-5) var(--space-8);         /* 20px 32px */
--inset-2xl:  var(--space-6) var(--space-10);        /* 24px 40px */
--inset-squish-sm: var(--space-1-5) var(--space-3);  /* vertical compress */
--inset-squish-md: var(--space-2) var(--space-4);
--inset-squish-lg: var(--space-3) var(--space-6);
--inset-stretch-sm: var(--space-3) var(--space-2);   /* vertical expand */
--inset-stretch-md: var(--space-4) var(--space-3);

/* Stack (vertical gap in lists, sections) */
--stack-2xs:  var(--space-1);    /* 4px */
--stack-xs:   var(--space-2);    /* 8px */
--stack-sm:   var(--space-3);    /* 12px */
--stack-md:   var(--space-4);    /* 16px */
--stack-lg:   var(--space-6);    /* 24px */
--stack-xl:   var(--space-8);    /* 32px */
--stack-2xl:  var(--space-12);   /* 48px */
--stack-3xl:  var(--space-16);   /* 64px */

/* Inline (horizontal gap in rows) */
--inline-2xs: var(--space-1);    /* 4px */
--inline-xs:  var(--space-1-5);  /* 6px */
--inline-sm:  var(--space-2);    /* 8px */
--inline-md:  var(--space-3);    /* 12px */
--inline-lg:  var(--space-4);    /* 16px */
--inline-xl:  var(--space-6);    /* 24px */
--inline-2xl: var(--space-8);    /* 32px */
```

---

### Layout Grid System

```css
/* Mobile — 375px+ */
--grid-mobile-columns:     4;
--grid-mobile-gutter:      16px;
--grid-mobile-margin:      16px;
--grid-mobile-column-width: calc((375px - 2 * 16px - 3 * 16px) / 4);

/* Tablet — 768px+ */
--grid-tablet-columns:     8;
--grid-tablet-gutter:      20px;
--grid-tablet-margin:      24px;

/* Desktop Small — 1024px+ */
--grid-desktop-sm-columns: 12;
--grid-desktop-sm-gutter:  24px;
--grid-desktop-sm-margin:  32px;
--grid-desktop-sm-sidebar: 72px;   /* Collapsed sidebar */

/* Desktop Large — 1280px+ */
--grid-desktop-lg-columns: 12;
--grid-desktop-lg-gutter:  24px;
--grid-desktop-lg-margin:  40px;
--grid-desktop-lg-sidebar: 260px;  /* Expanded sidebar */

/* Max content width */
--layout-max-width:        1440px;
--layout-content-max:      1200px;
--layout-reading-max:      680px;   /* Long-form text blocks */

/* Breakpoints */
--bp-xs:   375px;
--bp-sm:   430px;
--bp-md:   768px;
--bp-lg:   1024px;
--bp-xl:   1280px;
--bp-2xl:  1440px;
--bp-3xl:  1920px;
```

---

### Touch Target Tokens

```css
--touch-target-min:    44px;   /* WCAG 2.5.5 minimum */
--touch-target-sm:     44px;
--touch-target-md:     48px;
--touch-target-lg:     56px;
--touch-target-xl:     64px;   /* FAB */
```

---

## C5 — ELEVATION & DEPTH

### Shadow Scale

```css
/* The GLASS OS shadow system creates the illusion of depth on glass panels.
   Shadows are split into: ambient (soft spread) + directional (crisp drop) */

/* Level 0 — Flat, no elevation */
--shadow-0: none;

/* Level 1 — Subtle lift (cards at rest) */
--shadow-1:
  0px 1px 2px rgba(0, 0, 0, 0.04),
  0px 1px 4px rgba(0, 0, 0, 0.06);

/* Level 2 — Card elevated (hover state) */
--shadow-2:
  0px 2px 4px rgba(0, 0, 0, 0.06),
  0px 4px 12px rgba(0, 0, 0, 0.08),
  0px 0px 0px 1px rgba(255, 255, 255, 0.08);

/* Level 3 — Floating panel */
--shadow-3:
  0px 4px 8px rgba(0, 0, 0, 0.08),
  0px 8px 24px rgba(0, 0, 0, 0.12),
  0px 16px 40px rgba(0, 0, 0, 0.08),
  0px 0px 0px 1px rgba(255, 255, 255, 0.10);

/* Level 4 — Dropdown, popover */
--shadow-4:
  0px 8px 16px rgba(0, 0, 0, 0.10),
  0px 16px 40px rgba(0, 0, 0, 0.14),
  0px 32px 64px rgba(0, 0, 0, 0.10),
  0px 0px 0px 1px rgba(255, 255, 255, 0.12);

/* Level 5 — Modal, sheet */
--shadow-5:
  0px 16px 32px rgba(0, 0, 0, 0.14),
  0px 32px 64px rgba(0, 0, 0, 0.18),
  0px 64px 128px rgba(0, 0, 0, 0.12),
  0px 0px 0px 1px rgba(255, 255, 255, 0.14);

/* Inner shadow (inset glass highlight) */
--shadow-inner-top:
  inset 0px 1px 0px rgba(255, 255, 255, 0.20),
  inset 0px -1px 0px rgba(0, 0, 0, 0.08);

--shadow-inner-glass:
  inset 0px 1px 0px rgba(255, 255, 255, 0.24),
  inset 1px 0px 0px rgba(255, 255, 255, 0.08),
  inset -1px 0px 0px rgba(255, 255, 255, 0.04),
  inset 0px -1px 0px rgba(0, 0, 0, 0.12);

/* Glow shadows (for module-colored cards) */
--shadow-glow-home:        0px 8px 32px rgba(46, 143, 236, 0.20);
--shadow-glow-family:      0px 8px 32px rgba(196, 74, 126, 0.20);
--shadow-glow-security:    0px 8px 32px rgba(180, 32, 32, 0.20);
--shadow-glow-energy:      0px 8px 32px rgba(48, 180, 112, 0.20);
--shadow-glow-aria:        0px 8px 32px rgba(128, 64, 196, 0.20);
```

---

### Backdrop Blur Levels

```css
/* Used for glass panels — maps directly to glass physics layers */
--blur-none:     0px;
--blur-xs:       4px;     /* Subtle tint overlay */
--blur-sm:       8px;     /* Light glass card */
--blur-md:       16px;    /* Standard glass panel */
--blur-lg:       24px;    /* Heavy glass panel */
--blur-xl:       40px;    /* Modal backdrop */
--blur-2xl:      60px;    /* Full-screen overlay */
--blur-3xl:      80px;    /* Living background diffusion */
--blur-max:      100px;   /* Maximum blur (splash only) */
```

---

## C6 — GLASS PHYSICS

### The GLASS OS Physical Model

GLASS OS glass is modeled after real optical glass with four optical properties:

1. **Transmission** — how much of the background passes through
2. **Refraction** — how much the background is shifted/distorted
3. **Reflection** — how much the surface acts as a mirror
4. **Absorption** — how much the surface tints the light passing through

---

### Glass Tier Definitions

```
┌─────────────────────────────────────────────────────────────────┐
│  TIER        TRANSMISSION  REFRACTION  REFLECTION  BLUR         │
├─────────────────────────────────────────────────────────────────┤
│  Whisper     92%           1px         4%          4px          │
│  Light       85%           2px         6%          8px          │
│  Standard    75%           4px         8%          16px         │
│  Heavy       60%           6px         12%         24px         │
│  Opaque      40%           8px         16%         40px         │
│  Frosted     20%           12px        20%         60px         │
└─────────────────────────────────────────────────────────────────┘
```

---

### Glass CSS Recipes

```css
/* WHISPER GLASS — Ambient panels, background cards */
.glass-whisper {
  background: rgba(255, 255, 255, 0.04);
  backdrop-filter: blur(4px) saturate(120%);
  -webkit-backdrop-filter: blur(4px) saturate(120%);
  border: 1px solid rgba(255, 255, 255, 0.08);
  box-shadow: var(--shadow-inner-top);
}

/* LIGHT GLASS — Standard widget cards */
.glass-light {
  background: rgba(255, 255, 255, 0.06);
  backdrop-filter: blur(8px) saturate(140%);
  -webkit-backdrop-filter: blur(8px) saturate(140%);
  border: 1px solid rgba(255, 255, 255, 0.12);
  box-shadow: 
    var(--shadow-inner-glass),
    var(--shadow-2);
}

/* STANDARD GLASS — Primary panels, main cards */
.glass-standard {
  background: rgba(255, 255, 255, 0.08);
  backdrop-filter: blur(16px) saturate(160%);
  -webkit-backdrop-filter: blur(16px) saturate(160%);
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-top-color: rgba(255, 255, 255, 0.28);
  box-shadow:
    var(--shadow-inner-glass),
    var(--shadow-3);
}

/* HEAVY GLASS — Important cards, ARIA panel */
.glass-heavy {
  background: rgba(255, 255, 255, 0.10);
  backdrop-filter: blur(24px) saturate(180%) brightness(1.05);
  -webkit-backdrop-filter: blur(24px) saturate(180%) brightness(1.05);
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-top-color: rgba(255, 255, 255, 0.36);
  box-shadow:
    var(--shadow-inner-glass),
    var(--shadow-4);
}

/* OPAQUE GLASS — Modals, sheets */
.glass-opaque {
  background: rgba(20, 28, 44, 0.72);
  backdrop-filter: blur(40px) saturate(200%) brightness(0.95);
  -webkit-backdrop-filter: blur(40px) saturate(200%) brightness(0.95);
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-top-color: rgba(255, 255, 255, 0.28);
  box-shadow: var(--shadow-5);
}

/* FROSTED GLASS — Full-screen overlays */
.glass-frosted {
  background: rgba(8, 14, 24, 0.80);
  backdrop-filter: blur(60px) saturate(150%);
  -webkit-backdrop-filter: blur(60px) saturate(150%);
  border: none;
}

/* MODULE TINT VARIANTS — add on top of glass class */
.glass-tint-home        { --tint-color: var(--module-home-500);        }
.glass-tint-property    { --tint-color: var(--module-property-500);    }
.glass-tint-twin        { --tint-color: var(--module-twin-500);        }
.glass-tint-family      { --tint-color: var(--module-family-500);      }
.glass-tint-aria        { --tint-color: var(--module-aria-500);        }
.glass-tint-security    { --tint-color: var(--module-security-500);    }
.glass-tint-energy      { --tint-color: var(--module-energy-500);      }
.glass-tint-inventory   { --tint-color: var(--module-inventory-500);   }
.glass-tint-maintenance { --tint-color: var(--module-maintenance-500); }
.glass-tint-finances    { --tint-color: var(--module-finances-500);    }
.glass-tint-documents   { --tint-color: var(--module-documents-500);   }
.glass-tint-marketplace { --tint-color: var(--module-marketplace-500); }

[class*="glass-tint-"] {
  background: color-mix(
    in srgb,
    var(--tint-color) 6%,
    rgba(255, 255, 255, 0.06)
  );
}

/* LIGHT MODE overrides */
[data-theme="light"] .glass-standard {
  background: rgba(255, 255, 255, 0.60);
  backdrop-filter: blur(16px) saturate(180%);
  border: 1px solid rgba(255, 255, 255, 0.80);
  border-top-color: rgba(255, 255, 255, 0.95);
}

[data-theme="light"] .glass-heavy {
  background: rgba(255, 255, 255, 0.75);
  backdrop-filter: blur(24px) saturate(200%);
  border: 1px solid rgba(255, 255, 255, 0.90);
}

/* REDUCED MOTION — replace blur with solid */
@media (prefers-reduced-transparency: reduce) {
  .glass-standard {
    background: var(--color-bg-surface);
    backdrop-filter: none;
    border: 1px solid var(--color-border-default);
  }
}
```

---

### Glass Shine Animation

```css
/* Top-edge shimmer for premium glass panels */
@keyframes glass-shine {
  0%   { opacity: 0;    transform: translateX(-100%); }
  20%  { opacity: 0.15; }
  80%  { opacity: 0.15; }
  100% { opacity: 0;    transform: translateX(100%); }
}

.glass-shimmer::after {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 1px;
  background: linear-gradient(
    90deg,
    transparent 0%,
    rgba(255, 255, 255, 0.60) 50%,
    transparent 100%
  );
  animation: glass-shine 4s ease-in-out infinite;
  pointer-events: none;
}
```

---

## C7 — MOTION SYSTEM

### Spring Physics Foundation

GLASS OS uses spring physics exclusively. No cubic-bezier or linear easing exists in the design language. Every motion is described by mass, stiffness, and damping.

```
Spring Formula:
  F = -kx - bv
  where:
    k = stiffness (spring constant)
    b = damping coefficient  
    x = displacement
    v = velocity
```

---

### Spring Token Library

```typescript
// Spring tokens — defined as {stiffness, damping, mass}
// Used with Framer Motion or react-spring

export const springs = {
  // SNAP — Instant, high energy (alerts, badges)
  snap: {
    type: 'spring',
    stiffness: 800,
    damping: 40,
    mass: 0.6,
  },

  // BRISK — Fast, tight (buttons, chips, toggles)
  brisk: {
    type: 'spring',
    stiffness: 500,
    damping: 35,
    mass: 0.7,
  },

  // STANDARD — Default interaction (cards, navigation)
  standard: {
    type: 'spring',
    stiffness: 380,
    damping: 30,
    mass: 0.8,
  },

  // SMOOTH — Relaxed, composed (panels, drawers)
  smooth: {
    type: 'spring',
    stiffness: 280,
    damping: 28,
    mass: 1.0,
  },

  // FLOAT — Airy, slow (backgrounds, hero transitions)
  float: {
    type: 'spring',
    stiffness: 180,
    damping: 24,
    mass: 1.2,
  },

  // WOBBLY — Playful with overshoot (success states, celebration)
  wobbly: {
    type: 'spring',
    stiffness: 350,
    damping: 18,
    mass: 0.9,
  },

  // STIFF — No bounce (position corrections, resize)
  stiff: {
    type: 'spring',
    stiffness: 600,
    damping: 60,
    mass: 0.6,
  },

  // GENTLE — Barely visible motion (opacity fades, micro-text)
  gentle: {
    type: 'spring',
    stiffness: 120,
    damping: 20,
    mass: 1.5,
  },
} as const;
```

---

### Duration Scale (for CSS transitions — fallback only)

```css
--duration-instant:  50ms;
--duration-fast:     100ms;
--duration-normal:   200ms;
--duration-slow:     320ms;
--duration-slower:   480ms;
--duration-slowest:  640ms;
--duration-ambient:  1200ms;  /* Background transitions */
--duration-lpbe:     3000ms;  /* Living background transitions */
```

---

### Easing Tokens (CSS fallback when spring is unavailable)

```css
--ease-spring-out:    cubic-bezier(0.34, 1.56, 0.64, 1);   /* Spring-like */
--ease-spring-in-out: cubic-bezier(0.68, -0.55, 0.27, 1.55);
--ease-out:           cubic-bezier(0.0,  0.0,   0.2, 1.0);  /* Material decelerate */
--ease-in:            cubic-bezier(0.4,  0.0,   1.0, 1.0);  /* Material accelerate */
--ease-in-out:        cubic-bezier(0.4,  0.0,   0.2, 1.0);  /* Material standard */
--ease-linear:        linear;
```

---

### Animation Library

#### Entrance Animations

```typescript
// Card entrance — slides up + fades in
export const enterCard = {
  initial: { opacity: 0, y: 16, scale: 0.97 },
  animate: { opacity: 1, y: 0, scale: 1 },
  transition: springs.smooth,
};

// List item stagger
export const enterListItem = (index: number) => ({
  initial: { opacity: 0, x: -8 },
  animate: { opacity: 1, x: 0 },
  transition: { ...springs.standard, delay: index * 0.04 },
});

// Modal / sheet entrance — slides up from bottom
export const enterModal = {
  initial: { opacity: 0, y: 40 },
  animate: { opacity: 1, y: 0 },
  exit:    { opacity: 0, y: 40 },
  transition: springs.smooth,
};

// Full-screen page transition — slides in from right
export const enterPage = {
  initial: { opacity: 0, x: 20 },
  animate: { opacity: 1, x: 0 },
  exit:    { opacity: 0, x: -20 },
  transition: springs.standard,
};

// Panel from right (detail views)
export const enterPanel = {
  initial: { opacity: 0, x: 32 },
  animate: { opacity: 1, x: 0 },
  exit:    { opacity: 0, x: 32 },
  transition: springs.smooth,
};

// Dropdown / tooltip
export const enterDropdown = {
  initial: { opacity: 0, y: -4, scale: 0.96 },
  animate: { opacity: 1, y: 0,  scale: 1 },
  exit:    { opacity: 0, y: -4, scale: 0.96 },
  transition: springs.brisk,
};

// Toast notification
export const enterToast = {
  initial: { opacity: 0, y: -16, scale: 0.92 },
  animate: { opacity: 1, y: 0,   scale: 1 },
  exit:    { opacity: 0, y: -8,  scale: 0.96 },
  transition: springs.brisk,
};
```

#### Interaction Animations

```typescript
// Button press
export const pressButton = {
  whileTap: { scale: 0.96 },
  transition: springs.snap,
};

// Card hover
export const hoverCard = {
  whileHover: { scale: 1.01, y: -2 },
  transition: springs.standard,
};

// Toggle switch
export const toggleSwitch = (enabled: boolean) => ({
  animate: { x: enabled ? 20 : 0 },
  transition: springs.brisk,
});

// Badge pulse (new notifications)
export const pulseBadge = {
  animate: {
    scale: [1, 1.2, 1],
    opacity: [1, 0.8, 1],
  },
  transition: {
    duration: 0.6,
    ease: 'easeInOut',
    repeat: 2,
  },
};

// Health score number counter
export const countUp = (from: number, to: number) => ({
  animate: { value: to },
  initial: { value: from },
  transition: { duration: 1.2, ease: 'easeOut' },
});

// ARIA thinking indicator
export const ariaThinking = {
  animate: {
    opacity: [0.4, 1, 0.4],
    scale: [0.95, 1.05, 0.95],
  },
  transition: {
    duration: 1.5,
    repeat: Infinity,
    ease: 'easeInOut',
  },
};
```

#### Background / LPBE Animations

```typescript
// Sky gradient transition (time of day)
export const skyTransition = {
  transition: {
    duration: 3.0,
    ease: 'linear',
  },
};

// Particle system fade (rain, snow, stars)
export const particleFade = {
  initial: { opacity: 0 },
  animate: { opacity: 1 },
  exit:    { opacity: 0 },
  transition: { duration: 2.0, ease: 'easeInOut' },
};

// Digital Twin room focus
export const focusRoom = {
  animate: {
    scale: 1.02,
    filter: 'brightness(1.08)',
  },
  transition: springs.float,
};
```

---

### Reduced Motion System

```css
@media (prefers-reduced-motion: reduce) {
  /* Replace spring physics with instant snap */
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
  
  /* Keep opacity transitions — they aid comprehension */
  .motion-safe-fade {
    transition-duration: 150ms !important;
  }
}

/* CSS class to disable all motion (per-user preference toggle) */
[data-motion="none"] * {
  animation: none !important;
  transition: none !important;
}

[data-motion="reduced"] * {
  animation-duration: 50ms !important;
  transition-duration: 50ms !important;
}
```

---

## C8 — ICONOGRAPHY

### Icon System Architecture

```
Icon System
├── PRV Custom Icons (property domain specific)
├── SF Symbols subset (iOS-native, used on Apple platforms)
├── Lucide Icons (open-source, used cross-platform)
└── Module Identifiers (12 unique module glyphs)
```

---

### Icon Grid Specification

```
┌────────────────────────────────────────────────────────────┐
│  SIZE     CANVAS   STROKE   PADDING   CORNER   USE CASE    │
├────────────────────────────────────────────────────────────┤
│  12px     12×12    1.0px    1px       0.5px    Badges       │
│  16px     16×16    1.25px   1.5px     0.75px   Dense lists  │
│  20px     20×20    1.5px    2px       1px      Inline text  │
│  24px     24×24    1.75px   2px       1px      Default UI   │
│  28px     28×28    1.75px   2.5px     1.25px   Tab bar      │
│  32px     32×32    2.0px    3px       1.5px    Cards        │
│  40px     40×40    2.0px    4px       2px      Section hdr  │
│  48px     48×48    2.25px   5px       2px      Hero cards   │
│  64px     64×64    2.5px    6px       3px      Empty state  │
│  96px     96×96    3.0px    8px       4px      Onboarding   │
└────────────────────────────────────────────────────────────┘
```

---

### Module Identifier Glyphs

```
Module           Icon Name          SF Symbol              Lucide
─────────────────────────────────────────────────────────────────────
Home Dashboard   house.fill         house.fill             Home
Property         building.fill      building.2.fill        Building2
Digital Twin     cube.transparent   cube.transparent       Box3d
Family           person.3.fill      person.3.fill          Users
ARIA             brain.head.profile sparkles               Sparkles
Security         lock.shield.fill   lock.shield.fill       ShieldCheck
Energy           bolt.circle.fill   bolt.circle.fill       Zap
Inventory        archivebox.fill    archivebox.fill        Archive
Maintenance      wrench.screwdriver.fill wrench.fill       Wrench
Finances         banknote.fill      banknote.fill          Banknote
Documents        folder.fill        folder.fill            FolderOpen
Marketplace      cart.fill          cart.fill              ShoppingCart
```

---

### Icon Animation States

```typescript
// Icon entrance (for module header icons)
export const iconEntrance = {
  initial: { scale: 0, rotate: -10 },
  animate: { scale: 1, rotate: 0 },
  transition: springs.wobbly,
};

// Icon press response
export const iconPress = {
  whileTap: { scale: 0.85 },
  transition: springs.snap,
};

// Loading spinner (replaces default icon)
export const iconSpin = {
  animate: { rotate: 360 },
  transition: {
    duration: 1.0,
    ease: 'linear',
    repeat: Infinity,
  },
};

// Status icon swap (e.g., lock → unlock)
export const iconSwap = {
  initial: { scale: 0, opacity: 0 },
  animate: { scale: 1, opacity: 1 },
  exit:    { scale: 0, opacity: 0 },
  transition: springs.brisk,
};
```

---

## C9 — COMPONENT LIBRARY: ATOMS

### Button Component

```
BUTTON VARIANTS:
  - primary      (filled, module color)
  - secondary    (glass, subtle border)
  - ghost        (no background, text only)
  - destructive  (red, used for delete/revoke)
  - glass        (frosted fill, no border tint)
  - icon         (square, icon only)
  - fab          (circular, floating action)

BUTTON SIZES:
  - xs    height: 28px  padding: 8px 12px   text: 12px
  - sm    height: 36px  padding: 10px 16px  text: 13px
  - md    height: 44px  padding: 12px 20px  text: 15px (default)
  - lg    height: 52px  padding: 14px 24px  text: 17px
  - xl    height: 64px  padding: 18px 32px  text: 20px

BUTTON STATES:
  - default   (resting)
  - hover     (+8% lightness, shadow-2)
  - focused   (2px ring, 2px offset, color-interactive-focus)
  - pressed   (scale: 0.96, -4% lightness)
  - loading   (icon replaced by spinner, text hidden, disabled)
  - disabled  (opacity: 0.40, no pointer events)
  - success   (green fill, checkmark icon, 1.5s then reverts)
  - error     (red fill, X icon, 1.5s then reverts)
```

```css
/* Base button styles */
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--inline-sm);
  font-family: var(--font-sans);
  font-weight: var(--weight-button);
  letter-spacing: var(--tracking-snug);
  border-radius: var(--radius-button);
  border: none;
  cursor: pointer;
  text-decoration: none;
  white-space: nowrap;
  transition: none;  /* Handled by spring physics */
  -webkit-tap-highlight-color: transparent;
  user-select: none;
}

.btn-primary {
  background: var(--module-color-500);
  color: white;
  box-shadow: var(--shadow-2);
}

.btn-secondary {
  background: var(--color-glass-fill);
  backdrop-filter: blur(8px);
  color: var(--color-text-primary);
  border: 1px solid var(--color-glass-border);
  box-shadow: var(--shadow-inner-top), var(--shadow-1);
}

.btn-ghost {
  background: transparent;
  color: var(--color-text-secondary);
}

.btn-destructive {
  background: var(--module-security-500);
  color: white;
}

.btn:disabled {
  opacity: var(--opacity-disabled);
  cursor: not-allowed;
  pointer-events: none;
}

/* Sizes */
.btn-xs  { height: 28px; padding: 0 var(--space-3);  font-size: var(--text-xs); }
.btn-sm  { height: 36px; padding: 0 var(--space-4);  font-size: var(--text-sm); }
.btn-md  { height: 44px; padding: 0 var(--space-5);  font-size: var(--text-base); }
.btn-lg  { height: 52px; padding: 0 var(--space-6);  font-size: var(--text-md); }
.btn-xl  { height: 64px; padding: 0 var(--space-8);  font-size: var(--text-lg); }

/* FAB */
.btn-fab {
  width: 64px;
  height: 64px;
  border-radius: var(--radius-full);
  background: var(--module-home-500);
  box-shadow: var(--shadow-4), var(--shadow-glow-home);
  position: fixed;
  bottom: calc(var(--space-6) + env(safe-area-inset-bottom));
  right: var(--space-6);
  z-index: var(--z-fab);
}
```

---

### Input Component

```
INPUT VARIANTS:
  - text, email, password, number, tel, search
  - select (custom dropdown trigger)
  - textarea (multi-line)
  
INPUT SIZES:
  - sm    height: 36px   text: 13px
  - md    height: 44px   text: 15px (default)
  - lg    height: 52px   text: 17px

INPUT STATES:
  - empty      (placeholder shown)
  - filled     (value present)
  - focused    (border highlight + glow)
  - error      (red border + error message below)
  - success    (green border + checkmark)
  - disabled   (opacity 0.40)
  - read-only  (no border, lighter background)
```

```css
.input {
  width: 100%;
  height: 44px;
  padding: var(--inset-md);
  font-family: var(--font-sans);
  font-size: var(--text-base);
  font-weight: var(--weight-regular);
  color: var(--color-text-primary);
  background: var(--color-glass-fill);
  backdrop-filter: blur(8px);
  border: var(--border-input) solid var(--color-border-default);
  border-radius: var(--radius-input);
  box-shadow: var(--shadow-inner-top);
  outline: none;
}

.input::placeholder {
  color: var(--color-text-tertiary);
  opacity: var(--opacity-placeholder);
}

.input:focus {
  border-color: var(--color-border-focus);
  border-width: var(--border-input-focus);
  box-shadow:
    var(--shadow-inner-top),
    0px 0px 0px 3px rgba(46, 143, 236, 0.15);
}

.input--error {
  border-color: var(--module-security-400);
}

.input--error:focus {
  box-shadow:
    var(--shadow-inner-top),
    0px 0px 0px 3px rgba(180, 32, 32, 0.15);
}

.input-label {
  display: block;
  font-size: var(--text-sm);
  font-weight: var(--weight-medium);
  color: var(--color-text-secondary);
  margin-bottom: var(--stack-xs);
}

.input-hint {
  font-size: var(--text-xs);
  color: var(--color-text-tertiary);
  margin-top: var(--stack-xs);
}

.input-error-text {
  font-size: var(--text-xs);
  color: var(--module-security-400);
  margin-top: var(--stack-xs);
  display: flex;
  align-items: center;
  gap: var(--inline-xs);
}
```

---

### Badge / Status Chip

```
BADGE VARIANTS:
  - status    (success, warning, danger, info, neutral)
  - module    (each of 12 modules)
  - count     (numeric notification count)
  - health    (1–100 score chip)
  
BADGE SIZES:
  - xs    height: 16px   text: 10px
  - sm    height: 20px   text: 11px (default)
  - md    height: 24px   text: 12px
  - lg    height: 28px   text: 13px
```

```css
.badge {
  display: inline-flex;
  align-items: center;
  gap: var(--inline-xs);
  border-radius: var(--radius-badge);
  font-weight: var(--weight-badge);
  letter-spacing: var(--tracking-wide);
  text-transform: uppercase;
  white-space: nowrap;
  line-height: 1;
}

.badge-sm { height: 20px; padding: 0 var(--space-2); font-size: var(--text-2xs); }
.badge-md { height: 24px; padding: 0 var(--space-3); font-size: var(--text-xs); }

.badge-success { background: var(--color-status-success-surface-dark); color: var(--color-status-success-dark); }
.badge-warning { background: var(--color-status-warning-surface-dark); color: var(--color-status-warning-dark); }
.badge-danger  { background: var(--color-status-danger-surface-dark);  color: var(--color-status-danger-dark); }
.badge-info    { background: var(--color-status-info-surface-dark);    color: var(--color-status-info-dark); }
.badge-neutral { background: rgba(255,255,255,0.08); color: var(--color-text-secondary); }

/* Notification count badge */
.badge-count {
  min-width: 20px;
  height: 20px;
  padding: 0 var(--space-1-5);
  border-radius: var(--radius-full);
  background: var(--module-security-500);
  color: white;
  font-size: var(--text-2xs);
  font-weight: var(--weight-black);
}

/* Health score badge */
.badge-health-excellent { background: rgba(48, 180, 112, 0.15); color: var(--color-health-excellent); }
.badge-health-good      { background: rgba(110, 180, 64, 0.15); color: var(--color-health-good); }
.badge-health-fair      { background: rgba(210, 160, 48, 0.15); color: var(--color-health-fair); }
.badge-health-poor      { background: rgba(210, 96, 48, 0.15);  color: var(--color-health-poor); }
.badge-health-critical  { background: rgba(180, 32, 32, 0.15);  color: var(--color-health-critical); }
```

---

### Toggle / Switch

```
TOGGLE SIZES:
  - sm    28×17px   knob: 13px
  - md    36×22px   knob: 18px (default)
  - lg    44×27px   knob: 23px

TOGGLE STATES:
  - off-default, off-hover, off-focused
  - on-default,  on-hover,  on-focused
  - disabled-off, disabled-on
```

```css
.toggle-track {
  position: relative;
  display: inline-flex;
  width: 36px;
  height: 22px;
  border-radius: var(--radius-full);
  background: var(--color-border-strong);
  cursor: pointer;
  transition: background 200ms ease;
}

.toggle-track[data-checked="true"] {
  background: var(--module-energy-500);
}

.toggle-knob {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 18px;
  height: 18px;
  border-radius: var(--radius-full);
  background: white;
  box-shadow: var(--shadow-2);
  /* Position animation handled by spring via JS */
}

.toggle-track:focus-visible {
  outline: var(--border-focus-ring) solid var(--color-interactive-focus);
  outline-offset: 2px;
}

.toggle-track[data-disabled="true"] {
  opacity: var(--opacity-disabled);
  cursor: not-allowed;
}
```

---

### Slider

```css
.slider-track {
  position: relative;
  height: 4px;
  border-radius: var(--radius-full);
  background: var(--color-border-default);
  cursor: pointer;
}

.slider-fill {
  position: absolute;
  left: 0;
  top: 0;
  height: 100%;
  border-radius: var(--radius-full);
  background: var(--module-color-400);
}

.slider-thumb {
  position: absolute;
  top: 50%;
  transform: translate(-50%, -50%);
  width: 22px;
  height: 22px;
  border-radius: var(--radius-full);
  background: white;
  box-shadow: var(--shadow-3);
  border: 2px solid var(--module-color-400);
  cursor: grab;
}

.slider-thumb:active {
  cursor: grabbing;
  transform: translate(-50%, -50%) scale(1.15);
}
```

---

### Avatar

```
AVATAR SIZES:
  - 2xs   16px
  - xs    24px
  - sm    32px
  - md    40px (default)
  - lg    48px
  - xl    64px
  - 2xl   80px
  - 3xl   96px

AVATAR VARIANTS:
  - image     (photo)
  - initials  (text fallback)
  - icon      (role icon)
  - property  (building photo, square)
  
AVATAR STATES:
  - online     (green ring)
  - away       (yellow ring)
  - offline    (gray ring)
  - active     (blue ring + pulse)
```

---

### Skeleton Loader

```css
@keyframes skeleton-shimmer {
  0%   { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.skeleton {
  border-radius: var(--radius-2);
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 0.04) 0%,
    rgba(255, 255, 255, 0.08) 50%,
    rgba(255, 255, 255, 0.04) 100%
  );
  background-size: 200% 100%;
  animation: skeleton-shimmer 1.6s ease-in-out infinite;
}

.skeleton-text     { height: 14px; border-radius: var(--radius-full); }
.skeleton-heading  { height: 20px; border-radius: var(--radius-full); }
.skeleton-card     { border-radius: var(--radius-card); }
.skeleton-avatar   { border-radius: var(--radius-full); }
.skeleton-icon     { border-radius: var(--radius-2); }
```

---

## C10 — COMPONENT LIBRARY: MOLECULES

### Glass Card

The core building block of the GLASS OS UI.

```
CARD VARIANTS:
  - standard     (default widget card)
  - hero         (featured, full-width)
  - compact      (dense list card)
  - action       (interactive, tappable)
  - status       (colored top-border accent)
  - module       (module-tinted)
  - metric       (large number display)
  - media        (image-heavy)
  
CARD STATES:
  - default
  - hover   (translateY(-2px), shadow-3)
  - focused (focus ring)
  - pressed (scale 0.98, shadow-1)
  - loading (skeleton overlay)
  - empty   (empty state illustration)
  - error   (error indicator)
```

```css
.card {
  position: relative;
  overflow: hidden;
  border-radius: var(--radius-card);
  padding: var(--inset-lg);
}

/* Extends .glass-standard */
.card-glass {
  composes: glass-standard;
}

.card-status-accent {
  border-top: 3px solid var(--module-color-400);
}

.card-metric {
  display: flex;
  flex-direction: column;
  gap: var(--stack-xs);
}

.card-metric__value {
  font-size: var(--text-3xl);
  font-weight: var(--weight-bold);
  font-variant-numeric: tabular-nums;
  letter-spacing: var(--tracking-tight);
  color: var(--color-text-primary);
}

.card-metric__label {
  font-size: var(--text-xs);
  font-weight: var(--weight-semibold);
  letter-spacing: var(--tracking-wider);
  text-transform: uppercase;
  color: var(--color-text-tertiary);
}

.card-metric__delta {
  display: inline-flex;
  align-items: center;
  gap: var(--inline-xs);
  font-size: var(--text-sm);
  font-weight: var(--weight-medium);
}

.card-metric__delta--up    { color: var(--color-health-good); }
.card-metric__delta--down  { color: var(--color-status-danger-dark); }
.card-metric__delta--flat  { color: var(--color-text-tertiary); }
```

---

### Toast Notification

```
TOAST VARIANTS:
  - success, warning, error, info, neutral
  - with-action (has secondary CTA)
  - persistent  (does not auto-dismiss)
  - loading     (spinner icon, persists)

TOAST BEHAVIOR:
  - auto-dismiss: 4000ms (success/info), 6000ms (warning/error)
  - position: top-center mobile, top-right desktop
  - max-visible: 3 (older ones slide out below)
  - swipe-to-dismiss on mobile
```

```css
.toast {
  display: flex;
  align-items: flex-start;
  gap: var(--inline-md);
  max-width: 380px;
  padding: var(--inset-md);
  border-radius: var(--radius-toast);
  composes: glass-heavy;
  box-shadow: var(--shadow-4);
  z-index: var(--z-toast);
}

.toast__icon {
  flex-shrink: 0;
  width: 20px;
  height: 20px;
  margin-top: 1px;
}

.toast__body {
  flex: 1;
  min-width: 0;
}

.toast__title {
  font-size: var(--text-sm);
  font-weight: var(--weight-semibold);
  color: var(--color-text-primary);
  line-height: 18px;
}

.toast__description {
  font-size: var(--text-xs);
  color: var(--color-text-secondary);
  margin-top: var(--stack-2xs);
  line-height: 16px;
}

.toast__action {
  composes: btn btn-ghost btn-xs;
  margin-top: var(--stack-xs);
  padding-left: 0;
  color: var(--color-text-link);
}

.toast__close {
  flex-shrink: 0;
  width: 20px;
  height: 20px;
  color: var(--color-icon-tertiary);
  cursor: pointer;
}
```

---

### Health Score Ring

```
The Property Health Score™ ring — signature PRV HOUSE component.
Displays the 0–100 property health score as a circular progress ring.

VARIANTS:
  - small    64px outer diameter
  - default  96px outer diameter
  - large    128px outer diameter
  - hero     160px outer diameter (dashboard hero)

SEGMENTS (7 factors, visible as arc segments within ring):
  1. Maintenance          (blue-gray)
  2. Safety & Security    (red)
  3. Energy Efficiency    (green)
  4. Document Status      (slate)
  5. System Health        (amber)
  6. Insurance            (purple)
  7. Financial            (gold)
```

```tsx
// Health Ring SVG structure
// Total circumference = 2π × r where r = (outerDiameter/2 - strokeWidth/2)
// Segment arc = (factorScore / 100) × circumference

<svg viewBox="0 0 96 96">
  {/* Background track */}
  <circle cx="48" cy="48" r="40" 
    fill="none" 
    stroke="rgba(255,255,255,0.06)" 
    strokeWidth="8" />
  
  {/* Score arc */}
  <circle cx="48" cy="48" r="40"
    fill="none"
    stroke={healthColor}
    strokeWidth="8"
    strokeDasharray={circumference}
    strokeDashoffset={circumference * (1 - score/100)}
    strokeLinecap="round"
    transform="rotate(-90 48 48)" />
  
  {/* Center score */}
  <text x="48" y="52" textAnchor="middle"
    fontSize="22" fontWeight="700" fill={healthColor}>
    {score}
  </text>
</svg>
```

---

### ARIA Chat Bubble

```
ARIA message types:
  - user-text          (right-aligned, glass)
  - aria-text          (left-aligned, violet glass)
  - aria-card          (inline data card)
  - aria-action        (action prompt with buttons)
  - aria-chart         (mini data visualization)
  - aria-alert         (critical alert bubble)
  - system-message     (centered, labeled)

ARIA visual states:
  - thinking    (three-dot pulse animation)
  - streaming   (text cursor blinking, text appears character by character)
  - complete    (full message shown)
  - error       (red tint, retry option)
```

---

### Navigation Tab Bar

```
Mobile bottom tab bar — 5 items.

ITEMS:
  1. Home         (house.fill)
  2. Property     (building.2.fill)
  3. ARIA         (sparkles — center, elevated FAB-style)
  4. Family       (person.3.fill)
  5. More         (grid.2x2.fill)

STATES:
  - inactive     (icon 60% opacity, no label — collapsed)
  - active       (icon 100%, module color, label shown, indicator dot)
  - pressed      (scale 0.90, spring.snap)
  - badge        (count badge overlaid top-right of icon)

DIMENSIONS:
  - height: 49px + safe-area-inset-bottom
  - item min-width: 44px
  - icon size: 28px
  - active label: 10px, weight 600
  - background: glass-opaque
  - blur: 40px
  - border-top: 1px rgba(255,255,255,0.10)
```

---

### Sidebar Navigation (Tablet / Desktop)

```
COLLAPSED STATE (tablet):
  - width: 72px
  - items: icon only
  - tooltip on hover

EXPANDED STATE (desktop):
  - width: 260px
  - items: icon + label + badge
  - section headers visible

ITEM HEIGHT: 44px
ITEM PADDING: 0 12px
ITEM BORDER-RADIUS: 10px

ACTIVE STATE:
  - background: module color + 12% opacity glass
  - icon: module color (full opacity)
  - label: text-primary

HOVER STATE:
  - background: rgba(255,255,255,0.06)
  - transition: spring.brisk

HEADER (Expanded):
  - Property name + address
  - Property selector dropdown trigger
  - Health score ring (small, 40px)
```

---

### Modal / Sheet

```
VARIANTS:
  - center-modal    (dialog, max-width 480px, vertically centered)
  - bottom-sheet    (slides up, handles rounded top corners)
  - side-sheet      (slides from right, 40% viewport width on desktop)
  - full-screen     (mobile full-page overlay)

PARTS:
  - backdrop     (glass-frosted scrim, tap to dismiss)
  - container    (glass-opaque)
  - header       (title + close button)
  - body         (scrollable)
  - footer       (sticky, action buttons)
  - drag-handle  (bottom-sheet only, 36×4px pill)

SCROLL:
  - body scrolls independently
  - header/footer remain sticky
  - overscroll-behavior: contain
  - rubber-band scroll on iOS
```

---

### Form Field Group

```
LAYOUT PATTERNS:
  - stacked       (label above input — default)
  - inline        (label left, input right — 40%/60%)
  - floating      (label floats inside input — for glass forms)
  - grouped       (multiple inputs in bordered group)

VALIDATION:
  - real-time on blur (after first submit attempt)
  - inline error messages
  - error summary at top (on submit)
  - success state on valid
```

---

### Empty State

```
PARTS:
  - illustration   (64–96px icon or simple SVG scene)
  - heading        (h4 weight, text-primary)
  - description    (body-sm, text-secondary, max 2 lines)
  - cta            (primary button)
  - secondary-cta  (ghost link, optional)

CONTEXTS:
  - no-data        (first visit, no items yet)
  - filtered-empty (search/filter returned nothing)
  - offline        (network error)
  - permission     (user doesn't have access)
  - loading-failed (fetch error, retry option)

SIZES:
  - compact    (inside cards, 100px height)
  - standard   (full section, 240px height)
  - full-page  (entire view, 50vh height)
```

---

## C11 — COMPONENT LIBRARY: ORGANISMS

### Dashboard Widget Grid

```
GRID SYSTEM:
  - Mobile:  1-col, full-width widgets
  - Tablet:  2-col grid, some widgets span 2
  - Desktop: 3-col grid with variable spans

WIDGET SIZES:
  - 1×1   standard card, ~160px height
  - 2×1   wide card, ~160px height
  - 1×2   tall card, ~340px height
  - 2×2   featured card, ~340px height

REORDERING:
  - Long-press to enter reorder mode
  - Drag handle appears
  - Other widgets shift with spring physics
  - Tap elsewhere or press Done to confirm

WIDGET LOADING:
  - Staggered entrance: index × 40ms delay
  - Each widget fades in + slides up 16px
  - Skeleton shown during data fetch
```

---

### Property Selector

```
TRIGGER:
  - Current property name + address (truncated)
  - Thumbnail (40×40px, square)
  - Chevron down icon

DROPDOWN CONTENT:
  - Property list (photo + name + address)
  - Health score badge per property
  - "+ Add property" at bottom

MULTI-PROPERTY BEHAVIOR:
  - Last visited remembered per device
  - Active property highlighted
  - Switching triggers global data reload
  - Transition: fade out old data, skeleton, fade in new
```

---

### ARIA Panel

```
STATES:
  - collapsed     (pill bar at bottom of screen)
  - peek          (40% height bottom sheet)
  - expanded      (70% height bottom sheet)
  - full-screen   (100% sheet with keyboard)

COLLAPSED (pill trigger):
  - Height: 48px
  - Background: glass-heavy + violet tint
  - Content: sparkles icon + "Ask ARIA..." label
  - Tap to expand to peek state

PEEK STATE:
  - Shows 3 quick-action chips above input
  - Input field active
  - Recent context card (last query summary)

EXPANDED STATE:
  - Full conversation history
  - Context indicator (what ARIA knows)
  - Rich response cards (inline)
  - Typing indicator

QUICK ACTIONS (context-aware):
  - Adapt to current screen/module
  - Examples when in Energy module:
    "What's my usage trend?"
    "Optimize for low cost"
    "Schedule off-peak tasks"
```

---

### Notification Center

```
ENTRY POINT:
  - Bell icon in header, with count badge
  - Swipe down on home screen (native gesture)

CONTENT SECTIONS:
  - Critical (red accent, shown first)
  - New (unseen, blue dot)
  - Earlier (seen, no dot)

ITEM ANATOMY:
  - Module icon + module color
  - Title (semibold, 1 line)
  - Description (regular, 2 lines max)
  - Timestamp (relative: "2m ago", "Yesterday")
  - Action chips (optional: "View", "Dismiss", "Snooze")

ACTIONS:
  - Swipe right → mark read
  - Swipe left  → dismiss
  - Long press  → action menu (snooze, details, settings)
  - Tap         → navigate to source
```

---

### Property Health Dashboard Card

```
ANATOMY:
  - Health Ring (hero size, 160px) — centered
  - Score number large inside ring
  - Status label below ring: "Excellent", "Good", etc.
  - Factor breakdown: 7 rows, each with:
    - Factor name
    - Mini progress bar
    - Score out of 100
    - Trend arrow
  - "View Full Report" link

DATA REFRESH:
  - Recalculated when: new maintenance task, new document, energy report, inspection
  - Last updated timestamp shown
  - Animated counter when score changes
```

---

### M-SCAN™ Scan Interface

```
SCAN STATES:
  - idle         (camera view, overlay frame)
  - scanning     (animated corner brackets, status text)
  - detecting    (pulse animation on detected region)
  - processing   (spinner, "Reading nameplate...")
  - success      (result card slides up, confetti if first scan)
  - error        (retry prompt, manual entry alternative)
  - manual-entry (form fallback)

CAMERA OVERLAY:
  - Glass panel at top: flash toggle, gallery import, close
  - Guide frame: animated corner brackets, 240×160px region
  - Bottom: "Aim at the nameplate" instruction text

RESULT CARD (slides up after success):
  - Appliance photo (from scan or database)
  - Brand + Model + Serial
  - Warranty status + expiry
  - Manual link
  - "Add to Inventory" primary CTA
  - "Scan Another" ghost CTA
```

---

### Energy Sankey Diagram

```
A living data visualization showing energy flow through the property.

NODES:
  - Source: Grid, Solar PV, Battery
  - Distribution: HVAC, Appliances, EV Charger, Lights, Other
  - Sink: Wasted (heat loss), Exported (to grid)

VISUAL PROPERTIES:
  - Node height proportional to wattage
  - Flow ribbons: gradient from source color to destination color
  - Ribbon width: proportional to power flow
  - Animated: flow particles travel along ribbons (1 particle/500W)

INTERACTION:
  - Hover/tap node: highlight connected flows, show tooltip
  - Tap ribbon: show flow detail panel
  - Toggle: Real-time vs 24h average vs monthly

RESPONSIVE:
  - Mobile: vertical layout (sources top, sinks bottom)
  - Desktop: horizontal layout
```

---

## C12 — COMPONENT LIBRARY: TEMPLATES

### Page Template: Module Home

```
STRUCTURE:
  Header (sticky):
    - Back navigation (if nested)
    - Module title + module icon (colored)
    - Right actions (search, filter, more)
  
  Hero Section:
    - Module summary card (glass-heavy, 2×2 or full-width)
    - Key metric(s) prominent
    - Quick actions row (3–4 chips)
  
  Content Grid:
    - Widget grid (see C11 Dashboard Widget Grid)
    - Lazy-loaded below fold
  
  FAB (if primary action):
    - Module-colored
    - Contextual to module
    
  Bottom safe area:
    - Tab bar clearance: 49px + inset
```

---

### Page Template: Detail View

```
STRUCTURE:
  Navigation Header:
    - Back chevron + parent name
    - Entity title (truncated 1 line)
    - Action menu (ellipsis)
  
  Hero:
    - Large image/icon or 3D preview
    - Title + subtitle
    - Status badge(s)
    - Quick actions (2–3 buttons)
  
  Sections (collapsible):
    - Each section: header + glass card content
    - Divider between sections
  
  Sticky Footer (when actions exist):
    - Primary CTA (full-width or right-aligned)
    - Secondary CTA
```

---

### Page Template: Form / Wizard

```
STRUCTURE:
  Progress Header:
    - Step indicator (dots or fraction "Step 2 of 5")
    - Cancel / Back
    - Skip (if optional step)
  
  Content Area:
    - Step title (h2)
    - Step description (body, secondary)
    - Form fields
  
  Sticky Footer:
    - Primary: "Continue" / "Next"
    - Secondary: "Back" (unless step 1)
  
  TRANSITIONS between steps:
    - Current step: slides left (exits)
    - New step: enters from right
    - Spring: smooth
    - Background gradient: subtly shifts to new module color
```

---

### Page Template: Full-Screen Camera

```
STRUCTURE:
  Overlay Header (glassmorphic bar):
    - Close button (left)
    - Title (center, white)
    - Supplemental action (right)
  
  Camera Viewport:
    - Full screen
    - Overlay frame guides (optional)
  
  Control Bar (bottom, above safe area):
    - Left: Gallery / Library picker
    - Center: Shutter / Capture
    - Right: Flash toggle / Mode switch
  
  Status Text:
    - 24px above control bar
    - Instruction or result text
```

---

### Page Template: Settings Section

```
STRUCTURE:
  Section Title (label-lg, uppercase, tertiary color)
  
  Glass Card:
    - List of settings rows
    - Each row: icon + label + control (toggle/chevron/value)
    - Hairline dividers between rows (not at top/bottom)
    - Last row has no divider
  
  Section Footer:
    - Optional description text (body-xs, tertiary)
    
  Row Variants:
    - toggle-row    (label + switch)
    - nav-row       (label + chevron)
    - value-row     (label + current value + chevron)
    - action-row    (label + destructive/accent color)
    - info-row      (label + info text, no interaction)
    - link-row      (label + external link icon)
```

---

## C13 — DARK MODE SYSTEM

Dark mode is the primary design mode for GLASS OS. The living property background is most impactful against dark surfaces.

### Dark Mode Fundamentals

```
BASE SURFACES
────────────────────────────────────────────────────
Z-0  Environment:  #080E18  (hsl 220, 22%, 4%)
Z-1  Background:   #0D1420  (hsl 220, 20%, 7%)
Z-2  Surface:      #141C2B  (hsl 220, 18%, 10%)
Z-3  Elevated:     #1C2535  (hsl 220, 16%, 14%)
Z-4  Float:        #2A3548  (hsl 220, 14%, 20%)
Z-5  Overlay:      rgba(8, 14, 24, 0.80)
────────────────────────────────────────────────────

GLASS LAYERS (dark mode)
────────────────────────────────────────────────────
Glass fill:        rgba(255, 255, 255, 0.06)
Glass fill heavy:  rgba(255, 255, 255, 0.10)
Glass border:      rgba(255, 255, 255, 0.10)
Glass border top:  rgba(255, 255, 255, 0.24)
Glass tint base:   rgba(255, 255, 255, 0.04)
────────────────────────────────────────────────────

TEXT (dark mode)
────────────────────────────────────────────────────
Primary:    hsl(220, 15%, 94%)   — #EEF0F5
Secondary:  hsl(220, 10%, 68%)   — #A6AEBA
Tertiary:   hsl(220, 8%, 48%)    — #72798A
Disabled:   hsl(220, 6%, 34%)    — #515866
────────────────────────────────────────────────────
```

---

### Dark Mode Living Background

At night (21:00–04:00), the living background transitions to:
- Deep navy sky with subtle star field
- Milky Way band if clear weather
- Moon phase indicator (lunar calendar integrated)
- City lights reflection on cloud base if urban location

```css
/* Dark LPBE — Night */
.lpbe-night {
  background: radial-gradient(
    ellipse at 30% 20%,
    hsl(235, 30%, 14%) 0%,
    hsl(230, 28%, 8%) 50%,
    hsl(225, 25%, 5%) 100%
  );
}
```

---

## C14 — LIGHT MODE SYSTEM

Light mode is designed for daytime use in bright environments. Glass is more opaque and surfaces are warm-white.

### Light Mode Fundamentals

```
BASE SURFACES (Light)
────────────────────────────────────────────────────
Z-0  Environment:  hsl(220, 14%, 96%)  — #F2F4F7
Z-1  Background:   hsl(220, 15%, 98%)  — #F7F8FA
Z-2  Surface:      #FFFFFF
Z-3  Elevated:     #FFFFFF (shadow differentiated)
Z-4  Float:        #FFFFFF
Z-5  Overlay:      rgba(8, 14, 24, 0.50)
────────────────────────────────────────────────────

GLASS LAYERS (light mode)
────────────────────────────────────────────────────
Glass fill:        rgba(255, 255, 255, 0.60)
Glass fill heavy:  rgba(255, 255, 255, 0.80)
Glass border:      rgba(255, 255, 255, 0.80)
Glass border top:  rgba(255, 255, 255, 0.95)
────────────────────────────────────────────────────

TEXT (light mode)
────────────────────────────────────────────────────
Primary:    hsl(220, 20%, 12%)   — #191F2E
Secondary:  hsl(220, 12%, 36%)   — #515D75
Tertiary:   hsl(220, 8%, 54%)    — #7F8898
Disabled:   hsl(220, 6%, 68%)    — #A4ABBE
────────────────────────────────────────────────────
```

---

### Light Mode Shadows (adjusted for white surfaces)

```css
[data-theme="light"] {
  --shadow-1:
    0px 1px 2px rgba(0, 0, 0, 0.06),
    0px 1px 4px rgba(0, 0, 0, 0.08);

  --shadow-2:
    0px 2px 4px rgba(0, 0, 0, 0.08),
    0px 4px 12px rgba(0, 0, 0, 0.10);

  --shadow-3:
    0px 4px 8px rgba(0, 0, 0, 0.08),
    0px 8px 24px rgba(0, 0, 0, 0.12),
    0px 16px 40px rgba(0, 0, 0, 0.06);

  --shadow-4:
    0px 8px 16px rgba(0, 0, 0, 0.10),
    0px 16px 40px rgba(0, 0, 0, 0.12),
    0px 32px 64px rgba(0, 0, 0, 0.08);
}
```

---

### Automatic Mode (System)

```css
/* Follows OS preference */
@media (prefers-color-scheme: dark) {
  :root { color-scheme: dark; }
  /* Dark mode tokens applied */
}

@media (prefers-color-scheme: light) {
  :root { color-scheme: light; }
  /* Light mode tokens applied */
}

/* User override takes precedence */
[data-theme="dark"]  { /* force dark */ }
[data-theme="light"] { /* force light */ }
[data-theme="auto"]  { /* follow system */ }
```

---

## C15 — ACCESSIBILITY SYSTEM

### Color Contrast Requirements

```
All text must meet WCAG 2.2 AA minimum:
  - Normal text (<18pt / <14pt bold):  4.5:1 contrast ratio
  - Large text (≥18pt / ≥14pt bold):  3.0:1 contrast ratio
  - UI components and focus indicators: 3.0:1

PRV HOUSE targets AAA where possible:
  - Body text:    7.0:1 (AAA)
  - UI text:      4.5:1 (AA)
  - Decorative:   no requirement

VERIFIED COMBINATIONS (dark mode):
  text-primary on glass-standard:   7.2:1  ✓ AAA
  text-secondary on glass-standard: 4.8:1  ✓ AA
  text-tertiary on glass-standard:  3.1:1  ✓ AA (large only)
  white on module-home-500:         4.6:1  ✓ AA
  white on module-energy-500:       5.2:1  ✓ AA
  white on module-security-500:     5.8:1  ✓ AA
```

---

### Focus Management

```css
/* Visible focus ring — all interactive elements */
:focus-visible {
  outline: 2px solid var(--color-interactive-focus);
  outline-offset: 2px;
  border-radius: inherit;
}

/* Remove default focus for mouse users */
:focus:not(:focus-visible) {
  outline: none;
}

/* High contrast mode */
@media (forced-colors: active) {
  :focus-visible {
    outline: 3px solid ButtonText;
  }
  
  .glass-standard,
  .glass-heavy {
    background: Canvas;
    border: 1px solid ButtonText;
    forced-color-adjust: none;
  }
}
```

---

### Screen Reader Support

```
ARIA PATTERNS REQUIRED:

Navigation:
  - role="navigation" on sidebar and tab bar
  - aria-label="Main navigation" on primary nav
  - aria-current="page" on active item
  - role="menuitem" on nav items

Live Regions:
  - aria-live="polite" on toast container
  - aria-live="assertive" on critical alerts
  - aria-live="polite" on ARIA AI responses
  - aria-busy="true" while loading

Cards:
  - role="article" or role="listitem"
  - aria-label includes key metric if no visible heading
  - Interactive cards: role="button" or <button>

Forms:
  - All inputs: id + aria-labelledby (or <label for>)
  - Error state: aria-describedby pointing to error element
  - aria-invalid="true" on error inputs
  - Required: aria-required="true"

Modals:
  - role="dialog" aria-modal="true"
  - aria-labelledby pointing to modal title
  - Focus trap while open
  - Return focus to trigger on close

Progress:
  - role="progressbar" aria-valuenow aria-valuemin aria-valuemax
  - Health ring: "Property health score: 84 out of 100, Good"
```

---

### Touch Accessibility

```
Minimum touch targets: 44×44px (WCAG 2.5.5)
All interactive elements meet this requirement via:
  - Padding expansion (visual size can be smaller)
  - ::after pseudo-element expansion where needed

Pointer accuracy:
  - Draggable elements: 44px minimum hit area
  - Slider thumbs: 22px visual, 44px hit area
  - Bottom nav items: min 44px wide
```

---

### Motion Accessibility

```
Three motion preference levels:
1. Full motion    (default)
2. Reduced motion (prefers-reduced-motion: reduce)
3. No motion      (user sets in-app preference)

Reduced motion changes:
  - Spring animations → instant (0ms)
  - LPBE background transitions → disabled (static gradient)
  - Skeleton shimmer → static opacity
  - Particle effects → hidden
  - Page transitions → fade only (150ms)
  - Counter animations → instant
  - Parallax → disabled
  
Kept in all modes (essential for comprehension):
  - Focus indicators
  - Opacity state changes (hover, press, disable)
  - Error/success color changes
```

---

## C16 — RESPONSIVE SYSTEM

### Breakpoint Strategy

```
Design philosophy: Content-first breakpoints, not device-first.
Four viewport tiers:

MOBILE     375–767px    Single column, bottom nav, full-screen sheets
TABLET     768–1023px   Two column, sidebar collapsed (icons), side sheets
DESKTOP    1024–1279px  Three column, sidebar expanded (260px), center modals
WIDE       1280px+      Three column, wider content area, optional fourth column
```

---

### Component Responsive Behavior

```
COMPONENT          MOBILE               TABLET                DESKTOP
────────────────────────────────────────────────────────────────────────
Navigation         Bottom tab bar       Side icon bar (72px)  Side full bar (260px)
Header             Compact (44px)       Standard (52px)       Standard (52px)
Card Grid          1 column             2 columns             3 columns
Modal              Bottom sheet         Side sheet or center  Center dialog
Property selector  Full-width top       Dropdown in sidebar   Dropdown in sidebar
ARIA Panel         Bottom sheet         Side panel (320px)    Persistent panel (320px)
Health Ring        Small (96px)         Default (96px)        Hero (128px)
Digital Twin       Full-screen viewer   Split: twin + info    Split: twin + info
Notifications      Full-screen          Dropdown (400px)      Dropdown (400px)
Settings           Full-screen pages    Two-pane split        Two-pane split
────────────────────────────────────────────────────────────────────────
```

---

### Fluid Type Scale

```css
/* Type scales with viewport for key display sizes */

/* Dashboard hero score */
.health-score-hero {
  font-size: clamp(32px, 5vw, 56px);
}

/* Onboarding title */
.onboarding-title {
  font-size: clamp(28px, 4vw, 48px);
}

/* Property name heading */
.property-heading {
  font-size: clamp(22px, 2.5vw, 32px);
}

/* Section header */
.section-heading {
  font-size: clamp(18px, 2vw, 24px);
}
```

---

### Safe Area Insets

```css
/* iOS safe areas */
:root {
  --safe-area-top:    env(safe-area-inset-top,    0px);
  --safe-area-right:  env(safe-area-inset-right,  0px);
  --safe-area-bottom: env(safe-area-inset-bottom, 0px);
  --safe-area-left:   env(safe-area-inset-left,   0px);
}

/* Components that respect safe areas */
.tab-bar {
  padding-bottom: calc(var(--space-2) + var(--safe-area-bottom));
  height: calc(49px + var(--safe-area-bottom));
}

.page-header {
  padding-top: calc(var(--space-3) + var(--safe-area-top));
}

.floating-elements {
  bottom: calc(var(--space-6) + var(--safe-area-bottom));
}
```

---

*End of Phase C — GLASS OS™ Design System*  
*Version 1.0 — All tokens, physics, components, and modes specified*  
*Proceed to Phase D — Figma Master Package*
