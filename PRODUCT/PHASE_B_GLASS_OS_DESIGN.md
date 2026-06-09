# PHASE B — GLASS OS MASTER DESIGN
## PRV HOUSE — Complete Screen Specifications
### Production-Grade UX/UI Specification

**Document version:** 1.0  
**Constitution references:** PRV_HOUSE_VISION_V2_v1.0 Chapter 5 & 9

---

> Every screen specification follows this structure:
> **Layout → Components → Interactions → States → Animations → Accessibility → Mobile / Tablet / Desktop**

---

# TABLE OF CONTENTS

- [B0. Design Foundations](#b0-design-foundations)
- [B1. Authentication](#b1-authentication)
- [B2. Onboarding](#b2-onboarding)
- [B3. Home Dashboard](#b3-home-dashboard)
- [B4. Property Dashboard](#b4-property-dashboard)
- [B5. Digital Twin](#b5-digital-twin)
- [B6. Family Ecosystem](#b6-family-ecosystem)
- [B7. ARIA Property Brain](#b7-aria-property-brain)
- [B8. Security Center](#b8-security-center)
- [B9. Energy Center](#b9-energy-center)
- [B10. Inventory (M-SCAN™)](#b10-inventory)
- [B11. Maintenance Center](#b11-maintenance-center)
- [B12. Marketplace](#b12-marketplace)
- [B13. Settings](#b13-settings)

---

# B0. DESIGN FOUNDATIONS

## Screen Dimensions Reference

```
MOBILE (iPhone):
  SE 3rd gen:      375 × 667 pt (base reference for minimum layout)
  Standard (15):   390 × 844 pt
  Pro (16 Pro):    393 × 852 pt  (primary design target)
  Max (16 Pro Max):430 × 932 pt

TABLET (iPad):
  iPad mini 6:     744 × 1133 pt
  iPad (10th gen): 820 × 1180 pt
  iPad Air 11:     834 × 1194 pt
  iPad Pro 11:     834 × 1194 pt  (primary tablet target)
  iPad Pro 13:     1024 × 1366 pt

DESKTOP (Web):
  Minimum:         1024 pt wide
  Standard:        1440 pt wide  (primary desktop target)
  Wide:            1920 pt wide
  4K:              2560 pt wide

BREAKPOINTS:
  xs:   < 375pt   (SE minimum support)
  sm:   375–767pt (mobile)
  md:   768–1023pt (tablet portrait)
  lg:   1024–1439pt (tablet landscape / small desktop)
  xl:   1440–1919pt (desktop)
  2xl:  ≥ 1920pt  (wide)
```

## Glass Layer Reference

```
All screens use the 7-layer depth system from GLASS OS™:

Z-0  ENVIRONMENT:  LPBE background (always active)
Z-1  AMBIENT:      Blurred environmental echo elements
Z-2  FOUNDATION:   Page structural glass (sidebars, page bg)
Z-3  CONTENT BASE: Cards, module containers
Z-4  INTERACTIVE:  Hover/active states, selected items
Z-5  OVERLAY:      Modals, sheets, drawers
Z-6  NAVIGATION:   Tab bar, sidebar, top bar
Z-7  SYSTEM:       Alerts, toasts, ARIA panel

Glass CSS base:
  backdrop-filter: blur(40px) saturate(180%);
  background: rgba(10, 10, 15, 0.45);
  border: 1px solid rgba(255, 255, 255, 0.12);
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.15),
              inset 0 1px 0 rgba(255, 255, 255, 0.08);
```

## Safe Areas & Spacing

```
MOBILE:
  Top safe area:    Dynamic Island / notch height (respect always)
  Bottom safe area: Home indicator bar (34pt on notch devices)
  Side margins:     16pt minimum
  Content padding:  16pt standard, 24pt for cards

DESKTOP/TABLET:
  Sidebar width:    280pt (expanded) / 72pt (collapsed)
  Content max-width: 1200pt (centered on wide screens)
  Content padding:  24pt
  Card gap:         16pt
```

---

# B1. AUTHENTICATION

## B1.1 Login Screen

### Layout
```
FULL SCREEN — LPBE active behind everything

STRUCTURE (mobile, 393 × 852pt):
  [LPBE Background — full screen, always active]
  
  GLASS CARD (centered, 340 × auto):
    border-radius: 28pt
    margin-top: auto (vertical centered with keyboard offset)
    padding: 32pt
    
    LOGO ZONE (top):
      PRV icon mark (42 × 42pt, gold gradient fill)
      "PRV HOUSE" wordmark (22pt, weight 600, cream)
      "The Property Operating System" (12pt, weight 400, 50% opacity)
      margin-bottom: 36pt
    
    SOCIAL AUTH ZONE:
      [Sign in with Apple]       h:52pt, full-width, white bg, Apple logo
      [Sign in with Google]      h:52pt, full-width, glass bg, Google logo
      [Sign in with Microsoft]   h:52pt, full-width, glass bg, MS logo
      gap between buttons: 10pt
      
    DIVIDER (28pt top/bottom margin):
      [—————  or  —————]
      text: "or continue with email" (11pt, 40% opacity)
    
    EMAIL FIELD:
      height: 52pt
      left-icon: envelope (18pt, 60% opacity)
      placeholder: "Email address" (15pt, 40% opacity)
      keyboard: email
      autocomplete: email
      
    PASSWORD FIELD (16pt gap from email):
      height: 52pt
      left-icon: lock (18pt, 60% opacity)
      right-accessory: [eye toggle] + [Face ID / fingerprint icon]
      placeholder: "Password" (15pt, 40% opacity)
      keyboard: default, secure
      
    FORGOT PASSWORD (8pt below password, right-aligned):
      "Forgot password?" (13pt, gold, tap → reset flow)
      
    SIGN IN BUTTON (24pt below, full-width):
      height: 56pt
      background: linear-gradient(135deg, #C9A84C, #E8C878)
      text: "Sign In" (17pt, weight 600, white)
      border-radius: 16pt
      
    PASSKEY OPTION (16pt below button, centered):
      icon: key (SF Symbol style, 16pt)
      text: "Sign in with passkey" (14pt, 70% opacity)
      
    REGISTER LINK (20pt below, centered):
      "New to PRV HOUSE? " + "Create account" (gold)
      font: 14pt
      
  BOTTOM (outside card):
    "Privacy Policy · Terms" (11pt, 30% opacity, centered)
    bottom padding: 20pt + safe area
```

### Components
```
GlassCard          — base glass container
GlassInput         — field with glass treatment, focus ring (gold), label transitions
GoldButton         — primary CTA, gradient fill
GlassButton        — secondary actions
SocialAuthButton   — platform-specific (Apple white, Google/MS glass)
PasskeyButton      — text + key icon inline
Divider            — with centered label
LogoLockup         — icon + wordmark + tagline
```

### Interactions
```
EMAIL / PASSWORD FIELDS:
  Focus: label rises to top of field (floating label pattern)
         gold border glow activates (box-shadow: 0 0 0 2px #C9A84C80)
         
SIGN IN BUTTON:
  Press: scale(0.97) + darken 5% + haptic (medium impact)
  Release: spring back to 1.0
  Loading: text replaced with activity indicator (spinner, white)
  Success: button scales to 0 + property scene reveals

SOCIAL AUTH:
  Press: same as button
  Opens: system auth sheet (not blocking PRV HOUSE UI)
  
FORGOT PASSWORD:
  Tap: underline + scale(1.02) brief
  Opens: bottom sheet modal

PASSKEY:
  Tap: Face ID / Touch ID prompt appears
  Success: direct to dashboard with glass dissolve transition

BACKGROUND (LPBE):
  Parallax: subtle 3-5pt parallax on device tilt (iOS gyroscope)
  Time-accurate: shows current astronomical lighting for default city
```

### States
```
DEFAULT:           Fields empty, all visible
EMAIL ENTERED:     Password field softly highlights (draw attention)
LOADING:           Button spinner, fields disabled
ERROR:             Field border pulses to amber-red
                   Error message appears below field (slide in, 13pt, #EF4444)
                   Card shakes once (spring: stiffness 800, damping 15)
WRONG_PASSWORD:    "Incorrect email or password" (generic, security best practice)
LOCKED_OUT:        "Too many attempts. Try in 15 minutes." + countdown
MFA_REQUIRED:      Transition to MFA screen (card slides left out, new slides in)
SUCCESS:           Card dissolves + property scene expands
```

### Animations
```
ENTRANCE (app opens to login):
  0ms:    LPBE starts loading (background progressive reveal)
  200ms:  Glass card slides up from -20pt + fades in (opacity 0→1)
          spring(stiffness: 280, damping: 28)
  400ms:  Logo assembles (icon draws in, text fades in left-to-right)
  600ms:  Social buttons stagger in (0, 80, 160ms offset)
  800ms:  Email/password fields stagger in (80, 160ms offset)
  1000ms: Secondary elements (divider, links) fade in

ERROR SHAKE:
  Duration: 400ms
  Keyframes: 0pt → -8pt → 8pt → -5pt → 5pt → -3pt → 3pt → 0pt
  Easing: spring(stiffness: 800, damping: 15)

SUCCESS TRANSITION:
  Button: scale to 0 (200ms, spring)
  Card: opacity 0 + scale(1.05) (300ms)
  LPBE background: cross-fade to user's property scene (800ms)
  Dashboard: slides in from right (500ms, spring standard)
```

### Accessibility
```
WCAG AA compliance minimum, AAA for text contrast
VoiceOver / TalkBack:
  Fields: aria-label="Email address", aria-required="true"
  Button: aria-label="Sign in", aria-disabled during loading
  Error: aria-live="assertive" for error messages
  
Dynamic Type: supports xs → xxxl (layout reflows, min-touch 44pt maintained)
Reduced Motion: all animations → simple opacity fade only
High Contrast: glass becomes solid dark (#1C1C2A), borders become white
Keyboard Navigation: tab order: email → password → sign in → social buttons
```

### Mobile / Tablet / Desktop

```
MOBILE (393pt):    Full-screen glass card, keyboard pushes content up
TABLET (834pt):    Card centered, max-width 440pt, more background visible
DESKTOP (1440pt):  Split layout: left 50% = property image montage (static),
                   right 50% = login card (centered in panel)
                   Left panel uses LPBE — same beautiful background
```

---

## B1.2 MFA Challenge Screen

```
LAYOUT: Full screen (same LPBE background)

GLASS CARD (340pt wide, smaller than login):
  Back button (top left, small glass pill)
  
  Icon: Shield with lock (64pt, gold gradient)
  Title: "Two-Factor Authentication" (20pt, Playfair)
  Subtitle: "Enter the 6-digit code from your authenticator app" (14pt, 70%)
  
  OTP INPUT (custom, 6 individual boxes):
    Each box: 44 × 52pt, glass, border-radius 12pt
    Focus: active box gets gold border
    Auto-advance: cursor moves to next box automatically on input
    Paste support: paste 6-digit code → all boxes fill
    
  Resend / method options:
    "Use a different method" → shows available methods
    "Use recovery code" → text input replaces OTP boxes
    
  VERIFY BUTTON: full-width, gold, same as login
  
STATES:
  ENTERING: boxes fill left to right
  VERIFYING: spinner in button
  ERROR: boxes shake + clear + error message
         "Wrong code. 2 attempts remaining."
  SUCCESS: shield animates → checkmark → dashboard transition
  
BIOMETRIC OPTION (if registered):
  Face ID icon at bottom: "Sign in with Face ID instead"
  Tapping triggers immediate biometric prompt
```

---

# B2. ONBOARDING

## B2.1 Onboarding Shell (persistent across all steps)

```
PERSISTENT ELEMENTS:
  Progress bar (glass, top safe area, below status bar):
    5 segments, filled = gold, unfilled = glass
    Animated fill on step advance
    
  Back button (glass pill, top-left):
    Visible from step 2+
    Tap: previous step (spring slide back)
    
  Skip button (glass pill, top-right):
    Visible on optional steps (3, 4, 5)
    Text: "Skip" (14pt, 60% opacity)
    
BACKGROUND:
  Changes per step (smooth 600ms LPBE cross-fade):
  Step 1: Architectural dawn scene
  Step 2: Property type illustration (changes on selection)
  Step 3: Satellite map of entered address (fades in on address confirm)
  Step 4: Same as step 3
  Step 5: Smart home device glow scene
  Step 6: ARIA constellation scene
```

## B2.2 Step 1 — Welcome

```
CONTENT (full screen, no glass card):
  
  TOP HALF:
    PRV HOUSE logo mark (large, 80pt, gold, centered at 35% from top)
    Soft glow halo behind logo (animated, breathing pulse)
    
  BOTTOM HALF:
    Glass panel rising from bottom (partial, 400pt height):
      Title: "Welcome to PRV HOUSE" (28pt, Playfair Display, cream)
      Subtitle: "Your property, finally understood." (16pt, 65% opacity)
      
      Name field:
        placeholder: "Your first name" (returns to "Hey [name]!" in ARIA)
        
      Language selector (6 pills in 2×3 grid):
        [🇷🇴 Română] [🇬🇧 English] [🇫🇷 Français]
        [🇳🇱 Nederlands] [🇮🇹 Italiano] [🇵🇱 Polski]
        Selected: glass pill + gold border + checkmark
        Auto-selected: from device locale
        
      [Get Started →] — gold button, 56pt, full-width

INTERACTIONS:
  Logo: subtle rotate animation on first appearance (0° → 5° → 0°, spring)
  Language select: pill scales 1.0 → 1.04 → 1.0 on tap
  Name field: keyboard appears → panel extends upward (keyboard avoidance)
```

## B2.3 Step 2 — Property Type

```
CONTENT:
  Header (24pt, Playfair): "What type of property?"
  Subtext (14pt, 65%): "We'll customize PRV HOUSE for your home"
  
  PROPERTY TYPE CARDS (horizontal scroll, 3 visible + peek):
    Each card: 180 × 200pt, glass, border-radius 20pt
    Content:
      Illustration (80pt, property type illustration)
      Label (16pt, semibold, cream)
      Descriptor (12pt, 60% opacity): e.g. "With garden & garage"
      
    Types: House · Apartment · Villa · Vacation Home · Land · Commercial
    
    Selected state:
      Scale: 1.04
      Border: 1.5px gold gradient
      Glow: subtle gold shadow
      Checkmark: appears top-right (20pt circle, gold fill)
      
BACKGROUND SYNC:
  Selecting "House" → background transitions to residential scene
  Selecting "Apartment" → urban building facade
  Selecting "Villa" → luxury residence
  (All transitions: 600ms LPBE cross-fade)

[Continue →] activates only after selection
```

## B2.4 Step 3 — Property Address

```
CONTENT:
  Header: "Where is your property?"
  
  SEARCH FIELD (glass, 56pt, full-width):
    left icon: location pin (PRV custom, gold)
    placeholder: "Enter address or postcode"
    keyboard: default
    As user types (3+ chars):
      Autocomplete dropdown (glass, below field)
      Up to 5 suggestions with formatted address
      Each suggestion: primary address + secondary (city/country)
      
  MAP PREVIEW (appears after address selection):
    Height: 200pt
    Type: Satellite 3D, centered on property
    Property highlighted (soft pulse circle)
    border-radius: 16pt
    
  CONFIRM CARD (below map, appears after address selected):
    "Is this your property?"
    Full formatted address
    [Yes, this is it →] [Change address]
    
WHAT HAPPENS NEXT (visible text below):
  "I'll use this to monitor local weather, energy rates, 
   and market data for your property."
  ARIA icon + text (reassurance about data use)
```

## B2.5 Step 4 — Property Details

```
CONTENT:
  Header: "Tell me about your home"
  Subtext: "The more I know, the better I can help."
  
  GLASS FORM (scrollable):
    Property nickname:
      Pre-filled: "Our Home" (editable)
      Helper: "A name only you see"
      
    Year built: (optional)
      Year picker (scroller, default: 2000)
      Helper: "Helps predict maintenance needs"
      
    Size:
      Two-button toggle: [m²] [sq ft]
      Numeric input
      
    Floors: 
      Stepper: [−] [1] [+]
      
    How do you use it?
      Segmented: [Live In] [Rent Out] [Both]
      
  FORM ANIMATION:
    Fields appear staggered (100ms offset each)
    Each from opacity 0 + translateY(12pt) → 1 + 0

SKIP INDICATOR:
  At bottom: "You can add this later in settings"
  Contextual — not pressuring, reassuring
```

## B2.6 Step 5 — Smart Home Connect

```
CONTENT:
  Header: "Do you have smart devices?"
  Subtext: "Connect your existing smart home — optional"
  
  PLATFORM TILES (2×3 grid):
    Each tile: glass card, 150 × 100pt
    Content: platform logo + name + "X,000+ devices"
    
    [Apple Home]      [Google Home]
    [Amazon Alexa]    [Home Assistant]
    [Samsung SmartThings] [Matter devices]
    
    Tap tile → OAuth sheet (not navigating away)
    Connected state: green "Connected ✓" badge
    
  SKIP OPTION (below grid):
    Large glass button: "Connect later →"
    Text: "You can connect any time in Settings > Integrations"
    
CONNECTED STATE (after OAuth):
  Animation: devices discovered with count
  Sample: 3 device cards animate in with room assignment prompt
  "Found 12 devices. Assign them to rooms after setup."
  
  [Finish device setup →] (in Smart Home after onboarding)
```

## B2.7 Step 6 — Meet ARIA

```
FULL SCREEN EXPERIENCE — no standard layout

BACKGROUND: Deep space constellation (ARIA signature)
  Dark background: #080810
  Stars: subtle procedural star field (slow parallax)
  Constellation: ARIA's signature — dots connect to form abstract pattern
  Color: deep indigo + gold accent stars

CENTER:
  ARIA Animation (custom Lottie):
    Duration: 3 seconds, loops gently
    Constellation dots → assemble → pulse → breathe
    
  ARIA SPEECH (typewriter animation, 30ms/character):
    "Hello. I'm ARIA."
    [500ms pause]
    "I'll learn everything about your home —
     every room, every appliance, every system."
    [300ms pause]
    "I'll protect it, optimize it, and tell you
     exactly what it needs."
    [400ms pause]
    "I'm ready when you are."
    
BOTTOM:
  [Explore PRV HOUSE →] — gold button (appears after ARIA finishes speaking)
  [Go to my home] — text link (appears 2s after button)
  
  Subtext: "ARIA learns over time. The more you use PRV HOUSE,
           the better I understand your property."
  
FIRST ARIA INSIGHT (if enough data from onboarding):
  Glass chip appears above button:
  ARIA icon + "Based on your property's age, I'll suggest a maintenance
  schedule as your first step."
  
AUDIO: Optional ambient spatial music (very subtle, 20% volume)
       Respect device silent mode — no audio if silent
```

---

# B3. HOME DASHBOARD

## Layout Architecture

```
MOBILE (393pt wide):

[STATUS BAR — transparent, content adapts to background]

[TOP BAR — glass, Z-6]:
  Left:  PRV icon (24pt) + property name (tap → switcher)
  Right: Bell (notifications badge) + Avatar (account menu)
  Height: 44pt + top safe area

[SCROLL AREA — main content]:

  [PROPERTY HERO — 220pt height]:
    Full-width card
    Background: property photo (parallax on scroll: moves at 0.4× speed)
    Glass overlay (gradient, bottom-heavy)
    Content:
      Property name (22pt, Playfair, top-left)
      Address (13pt, 60%, below name)
      
      HEALTH INDEX RING (bottom-right of card):
        Outer ring: 64pt diameter, 4pt stroke
        Color: score-dependent (green/amber/red)
        Inner: score number (28pt, bold, cream)
        Label: "Health" (10pt, below ring)
        
      BOTTOM STRIP (inside card, above card edge):
        3 stat pills (glass, inline):
        [⚡ 3.2kW] [🔒 Armed] [🌡 21°C]
        
  [WIDGET GRID — scroll continues]:
    All widgets: glass cards
    
    ROW 1 — Half-width pair (gap: 12pt):
      ENERGY WIDGET (left, 170pt wide, 140pt tall):
        Header: "Energy" (12pt label)
        Value: "3.2 kW" (28pt, bold)
        Subtitle: "−12% vs. yesterday" (12pt, green)
        Mini sparkline (bottom, 40pt height, SVG path)
        Tap → Energy Center
        
      SECURITY WIDGET (right, 170pt wide, 140pt tall):
        Header: "Security" (12pt label)
        Status: large icon (shield ✓ or shield !) 36pt
        Label: "Armed" (16pt, semibold)
        Subtext: "No events tonight" (12pt, 60%)
        Tap → Security Center
    
    ROW 2 — Full-width:
      ARIA INSIGHT CARD (full width, 100pt min height):
        Left: ARIA constellation icon (40pt)
        Right:
          Label: "ARIA Insight" (11pt, gold)
          Text: insight content (14pt, cream, 2-3 lines)
        Bottom-right: [Action button] (if actionable) + [×] dismiss
        Background: slightly different glass tint (subtle indigo tint)
    
    ROW 3 — Half-width pair:
      MAINTENANCE WIDGET:
        "Maintenance" label
        Large number: "3 overdue" (red) or "Next: Dec 15"
        Subtext: "5 tasks this month"
        Tap → Maintenance Center
        
      PROJECTS WIDGET:
        "Projects" label
        Active project name (if any)
        Progress bar (glass track, gold fill)
        "2 active" count
        Tap → Projects
    
    ROW 4 — Full-width:
      SMART HOME QUICK CONTROLS:
        Header: "Home Controls" (12pt) + [Edit] link
        4–6 device tiles (horizontal scroll if overflow):
          Each: 72 × 72pt, glass
          Device icon (24pt) + name (10pt) + state
          Toggle state on tap
          
    ROW 5 — Half-width pair:
      FINANCE WIDGET:
        "This Month" label
        Amount: "€1,240" (spend or P&L depending on property type)
        Vs. budget indicator
        
      FAMILY WIDGET:
        "Family" label
        Avatar stack (members home)
        "3 home · 1 away" label
        Tap → Family
    
    ROW 6 — Full-width:
      WEATHER IMPACT (ARIA contextual):
        "Weather Update" — shows when ARIA has weather-based insight
        e.g., "Heavy rain Thursday — I'll pause irrigation"
        [Review] action button

  [BOTTOM PADDING: 100pt (tab bar + FAB clearance)]

[TAB BAR — glass, Z-6]:
  Height: 49pt + bottom safe area
  Tabs: [Home] [Property] [Smart] [Manage] [More]
  Active: tab icon gold + label visible
  Inactive: icon 60% opacity, no label

[ARIA FAB — Z-7]:
  Position: right 20pt, above tab bar
  Size: 56 × 56pt circle
  Background: gold gradient
  Icon: ARIA constellation (white, 24pt)
  State: pulsing ring if insight pending (gold ring, 2s animation)
```

### States

```
LOADING STATE:
  Skeleton screens per widget (shimmer animation)
  Hero card: gradient placeholder
  All text replaced with rounded pill skeletons
  shimmer: 1.5s loop, left-to-right, opacity 0.3→0.6→0.3
  
ERROR STATE (network):
  Widgets show: "Connection issue" (small, 12pt)
  Retry button (small, glass)
  Cached data shown with: "Last updated 2h ago" label
  
EMPTY STATE (new user, no data):
  Replace widgets with Setup Checklist widget (full-width):
    "Set up your home" header
    Progress bar (steps completed / total)
    Next step highlighted with [→] CTA
    
CRITICAL ALERT STATE:
  Alert banner slides from top (glass, red-amber tint):
    [Alert icon] Event description [View →]
  Dashboard content dims to 70% opacity
  Banner dismisses when alert resolved or manually dismissed
  
MULTI-PROPERTY:
  Property switcher (top bar, property name tap):
    Sheet from bottom: list of properties
    Each: mini property card (photo thumbnail + name + health score)
    Current: gold checkmark
    [+ Add Property] at bottom of list
```

### Animations

```
DASHBOARD ENTER (from login or tab tap):
  Background: LPBE cross-fade from previous scene (if any)
  Top bar: fades in + slides down from -20pt (150ms)
  Hero card: slides up from +30pt + fades in (300ms, spring standard)
  Widgets: stagger in — each 60ms offset, translateY(20pt)→0 + opacity 0→1
  FAB: scale 0→1 from center (400ms, spring wobbly)
  Total entrance: ~800ms
  
SCROLL BEHAVIOR:
  Hero photo: parallax (0.4× scroll rate)
  Top bar: blurs progressively as content scrolls under it
  Hero card: slight scale reduction as scrolled past (1.0 → 0.98)
  
WIDGET REFRESH:
  Data update: number ticks (count-up animation, 400ms)
  Status change: icon morphs (Lottie: e.g., shield unlocked → locked)
  Alert appears: slides from top (spring smooth)
  
FAB PULSE (insight pending):
  Ring animation: scale(1.0)→scale(1.4), opacity 1→0, 2s loop
  Stop when ARIA panel opened
```

### Accessibility

```
VoiceOver / TalkBack:
  Dashboard navigation: "Home Dashboard, [property name]"
  Health score: "Property health score, 78 out of 100, Good"
  Each widget: meaningful aria-label, not just "card"
  ARIA FAB: "Open ARIA assistant, 3 insights available"
  
Focus order: top-to-bottom, left-to-right within rows
  
Skip navigation: "Skip to main content" hidden link (keyboard users)
  
Color-blind safe:
  Health score not conveyed by color alone (+ number + label)
  Security status not conveyed by color alone (+ icon + text)
  All color indicators have text labels
  
Dynamic Type: hero maintains aspect, widget grid adapts (1-column below lg text size)
```

### Tablet Layout (iPad)

```
SIDEBAR (280pt, left):
  Module navigation (see A5 Navigation System)
  
MAIN CONTENT:
  Top bar: property name + controls
  Content area (remaining width):
    Widget grid: 3-column (vs. 2-column mobile)
    Hero: full width, taller (280pt)
    Widgets: more data visible per widget
    ARIA: right panel opens on FAB tap (not full-screen)
```

### Desktop Layout (1440pt)

```
SIDEBAR (280pt, left): Full navigation
  
TOP BAR: Search + property + account
  
MAIN CONTENT (remaining width, max 1200pt centered):
  Dashboard grid: 4-column widget layout
  Hero: wider, no scroll (dashboard visible above fold)
  
ARIA: Right panel (380pt) slides in from right
  Does not cover main content (shifts main content left)
  
MULTI-PANE:
  Left: Navigation
  Center: Dashboard
  Right: ARIA / detail (contextual)
```

---

# B4. PROPERTY DASHBOARD

## Layout

```
ENTRY: Animated expand from dashboard property hero card

TOP: Property hero (full-width, 260pt, parallax)
  Property name (large, Playfair)
  Address + type badge
  HEALTH INDEX ring (larger, 80pt, with score + label)
  [Edit property] button (top-right, glass pill)

HORIZONTAL TAB NAVIGATION (glass segmented, sticky on scroll):
  [Overview] [Rooms] [Digital Twin] [Documents] [History]
  Active: gold indicator line below
  
--- OVERVIEW TAB ---

STATS GRID (2×2):
  [Area: 280m²] [Built: 2015] [Floors: 2] [Rooms: 8]
  Each: glass mini-card with icon + label + value
  
CONSTRUCTION DETAILS (accordion):
  [▶ Structure] → concrete frame + brick infill
  [▶ Insulation] → mineral wool 140mm
  [▶ Roof] → pitched tile
  [▶ Windows] → double-glazed, aluminium
  [▶ Heating/Cooling] → Gas + split A/C
  
MAP SECTION (160pt, satellite 3D, property centered, non-interactive)

CO-OWNERS (if any):
  Avatar stack + names
  [Manage members] link

HEALTH INDEX BREAKDOWN (expandable):
  Progress bars per category:
    Structural:    ████████░░  82%  [Details]
    Systems:       ██████████  96%  [Details]
    Smart Home:    ███████░░░  74%  [Details]
    Energy:        ████████░░  81%  [Details]
    Security:      ████████░░  78%  [Details]
    Documents:     █████░░░░░  52%  [Details]
    Financial:     ██████████  92%  [Details]

--- ROOMS TAB ---

FLOOR SELECTOR (glass pills, horizontal scroll):
  [All Floors] [Ground Floor] [1st Floor] [2nd Floor]
  
ROOM GRID (2 columns mobile, 3 columns tablet):
  Each room card (glass, 160 × 180pt):
    Room photo (top half, 90pt)
    Room name (14pt, semibold)
    Room type icon (small, 16pt)
    Stats: [3 items] [2 devices] [1 alert]
    Alert indicator: amber dot if any issues
    
  Tap → Room Detail:
    Room photo hero
    Edit name/type
    Gallery (all room photos, add new)
    INVENTORY section (items in this room, scrollable list)
    DEVICES section (smart home devices in room)
    CONDITION LOG (notes on room condition, date-stamped)
    Maintenance linked to room

--- DOCUMENTS TAB ---

SEARCH BAR (glass, top):
  "Search all documents..." (finds by OCR text content)
  
CATEGORY ACCORDION:
  LEGAL (3 docs):    [▼] → document cards
  FINANCIAL (7):     [▼] → document cards
  TECHNICAL (4):     [▼] → document cards
  PERMITS (2):       [▼] → document cards
  MANUALS (12):      [▼] → document cards
  
DOCUMENT CARD (horizontal, glass):
  Left: category color icon (40pt circle)
  Center: name + date added + expiry (if applicable)
  Right: expiry badge (green/amber/red) + chevron
  
  Expiry states:
    >90 days: subtle grey badge
    <90 days: amber badge "Expires in 67 days"
    <30 days: red badge "Expires in 12 days" + bell icon
    Expired:  grey strikethrough-style + "Expired"

DOCUMENT DETAIL (modal sheet):
  PDF viewer (in-app, full-screen option)
  Metadata sidebar: category, added date, expiry, file size
  Actions: [Share] [Download] [Edit details] [Delete]
  ARIA note: if document has AI-extracted insights

--- HISTORY TAB ---

TIMELINE (vertical, reverse chronological):
  Entry types (each with distinct icon + color):
    🔧 Maintenance completed (blue)
    🏗️ Project milestone (purple)
    💰 Transaction (green/red)
    📄 Document added (gold)
    👤 Member added/removed (teal)
    🔌 Device added (indigo)
    ⚠️ Alert resolved (amber)
    
  Each entry:
    Icon circle (32pt, color-coded)
    Title (14pt, semibold)
    Date/time (12pt, 60%)
    Summary (13pt, 2 lines max)
    Tap → source record (maintenance task, document, etc.)
    
  Filter bar (glass pills):
    [All] [Maintenance] [Projects] [Finance] [Documents]
```

### States

```
LOADING:      Skeleton rooms in grid, skeleton documents in accordion
EMPTY ROOMS:  "No rooms added yet" + [Add first room] CTA
EMPTY DOCS:   "Your document vault is empty" + [Upload first document] CTA
TWIN NOT SET UP: "Digital Twin not created" + [Set Up Twin] CTA
OFFLINE:      Cached data with "Viewing cached data" banner
```

---

# B5. DIGITAL TWIN

## Layout

```
ENTRY: Expanding transition from Property Dashboard → Digital Twin tab

TWIN VIEWER (full-screen):
  
  TOP BAR (glass, Z-6):
    ← Back (to property)
    Property name
    Navigation mode toggle: [Overview] [Walk] [Fly] [AR] [VR]
    Settings (gear icon)
    
  MAIN AREA (3D canvas, full-screen):
    Three.js / React Three Fiber scene
    Property model loaded (GLB/GLTF format)
    
    OVERVIEW MODE:
      Isometric/top-down view
      All floors visible (toggle floor selector)
      Rooms labeled (floating glass labels)
      Devices shown as glowing dots
      Sensor overlay rings (colored by status)
      
    WALK MODE (first person):
      Point of view inside property
      Look around: touch drag (mobile) / mouse (desktop)
      Move: swipe up/down (mobile) / WASD (desktop)
      Room transition: tap room label → smooth camera fly-to
      
    FLY MODE:
      Free camera (orbit controls)
      Pinch: zoom
      Two-finger drag: pan
      One-finger drag: orbit
      
  SIDE PANEL (glass, 280pt, slides from right on layer toggle):
    LAYER TOGGLES:
      [●] Rooms & Labels
      [●] IoT Sensors (real-time data)
      [●] Smart Devices
      [●] System X-Ray (pipes, wiring)
      [●] AI Overlay (ARIA annotations)
      [●] Energy Heat Map
      [●] Occupancy Map
      
  BOTTOM CONTROL BAR (glass, Z-6):
    Floor selector: [B] [G] [1] [2] — glass pills
    Current floor label
    Screenshot (camera icon)
    Measurement tool (ruler icon, toggle)
    
  OBJECT INTERACTION:
    Tap object → pop-up card (glass, 280pt wide):
      Object name + category
      Room location
      If item: warranty status, last maintained
      If device: current state + controls
      If system element: last inspection, material
      Actions: [View in Inventory] [Maintenance] [Document]
      [×] dismiss
      
  SENSOR OVERLAY (when IoT layer active):
    Temperature: color gradient overlay per room
    Motion: pulsing circles at sensor locations
    Door state: door 3D model opens/closes with real lock state
    Light state: room illumination matches real light state
```

### States

```
TWIN_NOT_CREATED:
  Full-screen prompt:
    "Bring your home to life in 3D"
    3 setup options (cards):
      [LiDAR Scan — most accurate (iPhone Pro)]
      [Photo Reconstruction — standard (any iPhone)]
      [Floor Plan Import — basic]
    [Start setup]
    
TWIN_PROCESSING:
  Progress screen:
    "Building your Digital Twin..."
    Progress ring + step description
    Estimated time remaining
    "This can take 15–30 minutes. We'll notify you when ready."
    
TWIN_READY:
  First-time: guided animation tour of all twin features
  "Welcome to your Digital Twin" with 3 interactive callouts
  
OFFLINE:
  3D model loads from cached files (always available offline)
  IoT data: "Using last known sensor states"
  
LOADING:
  Fade-in reveal as 3D model progressively loads (LOD streaming)
  "Building your world..." — not a spinner, but progressive reveal
```

### Animations

```
ROOM TRANSITION (Walk mode):
  Camera: smooth cubic-bezier fly from current position to new room
  Duration: 600ms
  Feel: walking through a doorway, not teleporting
  
LAYER TOGGLE:
  Layer adds: elements fade in from transparency
  Layer removes: elements fade to transparency
  Duration: 400ms, staggered if multiple elements
  
SENSOR PULSE:
  Motion sensor active: growing circle from sensor point
  Scale: 1.0 → 2.0, opacity: 0.8 → 0, 1.5s loop
  
OBJECT SELECTION:
  Object: slight highlight (emission boost, 300ms)
  Pop-up card: rises from tap point (not from edge)
  spring(stiffness: 280, damping: 28)
  
DOOR ANIMATION:
  Lock state changes: door 3D model rotates on hinge axis
  Smooth: 500ms, easeInOut
```

---

# B6. FAMILY ECOSYSTEM

## Layout

```
BACKGROUND: Warm evening interior — living room ambiance (LPBE)
Emotional tone: connected, intimate, private

TOP BAR (glass):
  "Family" (20pt, Playfair)
  [+ Invite] button (gold pill, top right)
  
FAMILY MAP SECTION (full-width, 220pt):
  Background: simplified floor plan of current property
  Overlay: glass panel over map
  
  PRESENCE AVATARS (positioned on floor plan):
    Each member: circular avatar (40pt)
    Position: approximates room from occupancy sensor
    Animated: soft pulse if recently active
    Away: greyed avatar + "Away" label
    
  LEGEND (bottom-right of map):
    Color dots: [●] Home [○] Away
    
MEMBERS LIST (below map):
  Section headers: [Family] [Tenants] [Guests] [Service Providers]
  
  MEMBER CARD (glass, horizontal, 72pt height):
    Left: Avatar (52pt circle, status ring: green=home, grey=away)
    Center:
      Name (15pt, semibold)
      Role badge (glass pill, 11pt): PARTNER / ADULT CHILD / etc.
      Presence: "Home · Kitchen area" or "Away · Left 2h ago"
    Right:
      3 permission icons (12pt, muted):
        🏠 Smart Home / 🔒 Security / 📄 Documents
      Chevron →
      
  TAP MEMBER → MEMBER DETAIL (push navigation):

MEMBER DETAIL PAGE:
  HERO:
    Large avatar (88pt, centered)
    Name (24pt, Playfair)
    Role badge (gold pill)
    [Edit] button (top-right)
    
  PRESENCE CARD (glass):
    Current status (large icon)
    Location detail
    "Last active: 2 hours ago"
    
  PERMISSIONS SECTION:
    Each module as a toggle row (glass table rows):
    
    [Smart Home]  [●━━━━━] [Full access  ▾] [Rooms: All ▾]
    [Security]    [●━━━━━] [View cameras] [Arm: Yes]
    [Doors]       [●━━━━━] [Front door]  [Schedule: Set ▾]
    [Documents]   [○━━━━━] [No access]
    [Finances]    [○━━━━━] [No access]
    [Energy]      [●━━━━━] [View only]
    [Maintenance] [●━━━━━] [Create & view]
    [ARIA]        [●━━━━━] [Basic]
    
    [Advanced permissions →] (full per-room, per-action matrix)
    
  ACCESS SCHEDULE:
    Toggle: [Always] [Set schedule]
    If schedule: 7-day grid
    Each day: time range picker (glass sliders)
    Visual: heatmap of accessible hours
    
  ACTIVITY LOG (last 30 days):
    Chronological events:
    "Arrived home (17:34)"
    "Disarmed security (17:35)"
    "Living room lights on (17:36)"
    "Left home (08:12)"
    [Show full history →]
    
  DANGER ZONE:
    [Remove [Name] from property] (red, destructive)
    Confirmation: "This will revoke all access immediately."
```

### Elderly Parent Specific View (when role = ELDERLY_PARENT)

```
EXTRA CARD in Member Detail:
  "Care Features" section:
  
  DAILY CHECK-IN:
    Toggle (default: ON)
    Expected motion by: [09:00 ▾] (configurable)
    Alert if no motion by: [10:00 ▾]
    Alert to: [Family member ▾] (who gets notified)
    
  MEDICATION REMINDER:
    Add medications + times
    Confirmation method: [ARIA voice] [App button]
    Non-confirmation: notify [family member]
    
  SIMPLIFIED APP MODE:
    Toggle: "Show simplified interface for [Name]"
    When ON: their PRV HOUSE app shows only:
      - Large ARIA button ("Ask for help")
      - Big temperature display
      - Simple light/door controls
      - SOS button (always visible, large, red)
```

---

# B7. ARIA PROPERTY BRAIN

## Layout (Full Panel)

```
ENTRY ANIMATION:
  FAB tapped → panel rises from bottom (full-screen sheet)
  Background: ARIA constellation replaces LPBE behind glass
  
TOP BAR (glass):
  ← Close (swipe down or × button)
  "ARIA" (18pt, Playfair) centered
  Property selector: [Our Home ▾] (glass pill)
  
PROPERTY CONTEXT BAR (glass strip, 44pt):
  Horizontal: [Health: 78] [Energy: 3.2kW] [Security: Armed] [Alerts: 0]
  Real-time indicators, updates every 30s
  Tap any → opens relevant module
  
INSIGHTS SECTION (collapsible, above conversation):
  DEFAULT: collapsed (shows count only)
  "3 insights waiting" + chevron
  
  EXPANDED:
    Horizontal scroll of insight cards (180pt wide each):
    Each card: glass, category color tint
      ARIA icon (small) + category label (MAINTENANCE/ENERGY/SECURITY)
      1-2 line insight text
      [Action button] + [Dismiss]
      
CONVERSATION AREA (flex-grow, scrollable):
  
  ARIA MESSAGES (left-aligned):
    Glass bubble (max 300pt wide, natural height)
    Top-left: ARIA constellation icon (20pt circle)
    Text: cream, 15pt, line-height 1.5
    Timestamp: below bubble, 11pt, 40% opacity
    
    INLINE CARDS (inside ARIA message when referencing items):
      Device card: icon + name + current state + [Control]
      Item card: photo + name + warranty status + [View]
      Cost card: amount + category + date
      Task card: priority chip + title + [Open]
      Action card: description + [Do this] + [Later]
      
  USER MESSAGES (right-aligned):
    Gold glass bubble
    Text: cream, 15pt
    
  THINKING STATE:
    Bubble with animated dots (●  ●  ●)
    Dots pulse in sequence (wave pattern, 400ms cycle)
    
  EMPTY STATE (no conversation yet):
    ARIA constellation centered (80pt)
    Text: "Ask me anything about your home." (16pt, centered, 60%)
    Suggestion chips below (horizontal scroll):
      [What needs attention?] [How's my energy?] [Find me a contractor]
      [What's my property worth?] [Check my warranties]
      
INPUT AREA (glass, floating above keyboard):
  [📎 Photo] — attach photo for ARIA to analyze
  [Text field] — "Ask ARIA..." (placeholder)
  [🎤 Voice] — tap to speak (waveform visualizer activates)
  [→ Send] — activates when text entered or voice recording
  
VOICE STATE:
  Input area expands to 100pt height
  Waveform visualizer (animated SVG, real-time amplitude)
  "Listening..." label
  [■ Stop] button
  Auto-stops on silence (2s)
  Sends automatically or shows transcript for review
```

### Conversation Examples (sample interactions)

```
EXAMPLE 1 — Query:
  User: "When was my boiler last serviced?"
  
  [Thinking: 1.2s]
  
  ARIA: "Your Bulex Logamax Plus boiler was last serviced on 
        March 14, 2024 by Marco P. (Plumbing Pro).
        
        [Task Card: Annual Boiler Service · March 2024 · Completed]
        
        It's now been 14 months — the recommended service interval
        is 12 months. Want me to schedule one?"
        
  Suggestion chips: [Yes, find a technician] [Remind me in 2 weeks] [Not now]
  
EXAMPLE 2 — Action:
  User: "My kitchen tap is dripping."
  
  ARIA: "I'll log this. The kitchen tap is in the main kitchen
        (ground floor, linked to your Grohe Essence faucet from 2020).
        
        Based on your property history, this is likely a worn cartridge —
        a common issue at 4+ years of use.
        
        Estimated fix: €60–€120 including parts.
        
        [Create Work Order: Dripping Kitchen Tap — HIGH]
        [Find a plumber near you] [I'll handle it myself]"
```

### States

```
LOADING (initial context load):
  Constellation animation plays
  "ARIA is checking in on your home..." (13pt, centered)
  
CONTEXT_INCOMPLETE (not enough data):
  ARIA: "I'm still learning about your property. The more
        you add, the better I can help. Try adding some inventory
        or connecting your smart home."
  
OFFLINE:
  Banner: "Working from cached knowledge. I can answer general
          questions but may have outdated property data."
  
API_ERROR:
  "I'm having trouble thinking right now. Try again in a moment."
  [Retry] button
  (No stack traces or technical errors shown to user)
  
PROCESSING_LONG (> 5s):
  Additional message: "This requires thinking through a lot of your
  property data. Just a moment more..."
```

---

# B8. SECURITY CENTER

## Layout

```
ENTRY: From Dashboard security widget or Smart/Security tab

ALERT BANNER (top, only when active alert):
  Red-amber glass, full-width, 52pt
  Alert type icon + description + [View →]
  Pulsing border animation (1.5s cycle)

LIVE VIEW SECTION:
  
  DEFAULT (single camera):
    Full-width, 16:9 ratio
    Glass overlay: camera name (bottom-left) + status (bottom-right)
    Controls (bottom bar, glass): [●] Record / [⊞] Grid / [⚙] Settings
    
  GRID VIEW (multi-camera, 2×2, 2×3 max):
    Each feed: glass border
    Active motion: border pulses amber
    Tap any → expands to full-screen feed
    
  NO CAMERAS: "Connect cameras to see live view"
              [Go to Integrations →]

ARMED STATE CARD (glass, full-width):
  Large status icon (shield, 48pt): green=armed, red=disarmed, amber=alert
  Status text: "HOME ARMED" / "AWAY ARMED" / "DISARMED"
  
  ARM/DISARM button:
    ARM: [Arm Home] [Arm Away] (glass pills, side by side)
    DISARM: [Disarm] (gold button, requires confirmation or PIN)
  
  Mode selector: [Home] [Away] [Night] [Off]
  Night mode: arms only perimeter sensors (not interior motion)

EVENTS SECTION:
  Filter chips: [All] [Motion] [Access] [Alarm] [Camera] [Sensor]
  
  Event cards (glass, horizontal):
    Left: event type icon in colored circle (32pt)
    Center: event description + room/location + time
    Right: camera thumbnail (if available, 52 × 52pt)
    
    Event types:
      Motion (amber): "Motion detected — Front garden"
      Access (green): "Emma unlocked Front Door"
      Alarm (red): "Intrusion alarm — triggered + silenced"
      Sensor (blue): "Window opened — Master Bedroom"
      
  Tap event:
    Expand in-place OR push to event detail:
      Camera clip (if available): inline video player
      Event details: device, time, duration
      Related events (same time window)
      Actions: [Mark as Reviewed] [Create Task] [Export]

ACCESS CONTROL SECTION:
  
  DOOR LIST (glass cards):
    Each door: photo + name + current state (locked/unlocked)
    [Lock] / [Unlock] toggle (requires intent tap, no accidental)
    
  ACCESS CODES:
    List of active codes:
    Each: name + code (hidden, tap to reveal) + valid period + [Revoke]
    [+ Create Code] → name, PIN, validity period, which doors
    
  SMART LOCK DETAIL:
    Battery level, firmware, last sync
    Full access history (who, when, method)
```

---

# B9. ENERGY CENTER

## Layout

```
BACKGROUND: Dynamic energy flow scene (dark, pulsing lines of energy)

ENERGY FLOW DIAGRAM (hero, full-width, 240pt):
  Interactive Sankey diagram:
  
  Left nodes:   [Grid] [Solar] [Battery]
  Center:       [Home]
  Right nodes:  [Heating] [Appliances] [EV] [Lights] [Other] [Export]
  
  Flow lines: animated (particles flowing along paths)
  Thickness: proportional to power flow
  Color: green (solar/battery), blue (grid), amber (high consumption)
  
  Tap any node → detail panel for that source/load

TIME SELECTOR (glass pills, below diagram):
  [Live] [Today] [This Week] [This Month] [This Year] [Custom]
  Live: data refreshes every 30s (subtle pulse on refresh)

STATS CARDS (below time selector, 2-column grid):
  [Total: 28.4 kWh] [Cost: €4.12]
  [Solar: 12.1 kWh] [Self-use: 67%]
  [Exported: 3.2 kWh] [Saved: €1.84]

CONSUMPTION CHART (full-width, 160pt):
  Bar chart or area chart (user toggle)
  X: time (hours/days depending on range)
  Y: kWh
  Hover/tap: tooltip with exact value
  Overlays: solar production (green area) + consumption (blue bars)
  
ARIA ENERGY INSIGHTS (glass card):
  Current insight or optimization opportunity
  "Your EV is charging at peak rate. Moving it to 23:00 saves €2.40 tonight."
  [Apply Automation] [Dismiss]

DEVICES BREAKDOWN (expandable):
  Shows top 5 consumers with percentage bars
  [Show all devices →]

BILLS & TARIFFS:
  Upload bill → OCR → add to history
  Current tariff settings
  Rate schedule (TOU if applicable)
```

---

# B10. INVENTORY (M-SCAN™)

## Layout

```
TOP SEARCH BAR (glass, sticky):
  Magnifying glass + "Search all items..."
  Right: [Scan item] (barcode icon, gold, 36pt) + [+ Add]

FILTER ROW (horizontal scroll, glass pills):
  [All] [Kitchen] [Living] [Master] [Appliances] [Electronics] [Furniture]
  [With warranty] [Recall alerts] [Expiring soon]

SECTIONS (accordion by category or room, user toggle top-right):
  
ITEMS GRID (default: 2-column) or LIST (user toggle):
  
  ITEM CARD — GRID VIEW (glass, 165 × 200pt):
    Photo (top 100pt, object-fit: cover)
    Brand + model name (12pt + 10pt, below photo)
    Room tag (glass pill, 10pt)
    
    Status indicators (bottom of card):
      Warranty: [●] (green/amber/red)
      Recall: [⚠] (orange, if active)
      Maintenance due: [🔧] (if any)
      
  ITEM CARD — LIST VIEW (full-width, 72pt):
    Left: item thumbnail (52 × 52pt, rounded)
    Center: brand + model (14pt semibold) + room (12pt, 60%)
    Right: warranty status chip
    
ITEM DETAIL (push navigation):

  HERO:
    Item photo gallery (swipeable, full-width)
    [+ Add photo] chip
    
  IDENTITY SECTION:
    Brand, model, serial number, barcode
    Category, subcategory, room
    [Edit] button
    
  WARRANTY CARD (glass, accent border):
    Warranty: Manufacturer · 2 years
    Purchased: March 15, 2022
    Expires: March 15, 2024 [EXPIRED]
    [View warranty document →]
    
  FINANCIAL SECTION:
    Purchase price, date, store
    Current estimated value (ARIA-calculated)
    Insurance value
    
  DOCUMENTS:
    Manual [PDF icon] [View]
    Receipt [Receipt icon] [View]
    Warranty cert [Cert icon] [View]
    
  MAINTENANCE HISTORY:
    Timeline of all maintenance related to this item
    [Create maintenance task for this item →]
    
  RECALL STATUS:
    Green checkmark: "No active recalls" (last checked: today)
    Or: Red warning: "ACTIVE RECALL" + details + action link
    
  ARIA DIAGNOSTICS:
    "Based on age (4 years) and your maintenance history,
     this dishwasher has a 65% probability of bearing issues
     within 18 months. Schedule a service check?"

SCAN SCREEN:
  Full-screen camera
  Frame guide (rounded rectangle overlay, 240 × 160pt)
  Animated scanline (subtle, moves up-down)
  [Switch to nameplate mode] pill (bottom)
  [Enter manually] text button (bottom)
  Flash toggle (top-right)
  
  Detection feedback:
    Barcode detected: vibration + green flash on frame
    Processing: spinner inside frame
```

---

# B11. MAINTENANCE CENTER

## Layout

```
VIEW TOGGLE (top-right): [Calendar] [List] [Kanban]

CALENDAR VIEW:
  Month grid (standard calendar layout)
  
  Days with tasks: dot indicator below date
  Dot colors: red (overdue) / amber (due today) / blue (upcoming)
  Multiple tasks on one day: dot stack (max 3 visible, "+N" if more)
  
  Today: highlighted (gold circle around date)
  
  TAP DAY → expands below calendar:
  Day detail (full-width, glass, slides down):
    [Task list for that day]
    Each task: priority chip + name + time (if scheduled) + quick actions
    
  MONTH SUMMARY (below calendar):
    "4 overdue · 2 due this week · 8 upcoming this month"
    Stats chips (glass pills with counts)

LIST VIEW:
  Sections:
    [OVERDUE (3)] → red badge
      Task cards (glass, full-width)
    [TODAY (1)]
      Task cards
    [THIS WEEK (4)]
      Task cards
    [THIS MONTH (12)]
      Task cards
    [FUTURE]
      Task cards (grouped by month)
      
  TASK CARD:
    Left: priority indicator bar (4pt, full height, color-coded)
    Center:
      Title (14pt, semibold)
      Room + item name (12pt, 60%)
      Due date (12pt, 60% — red if overdue)
    Right:
      Assigned avatar (if contractor) or wrench icon
      Chevron
      
  SWIPE ACTIONS (on task card):
    Swipe right → [Complete] (green)
    Swipe left → [Reschedule] [Delete] (amber, red)

WORK ORDER DETAIL (full screen):
  Status bar (top): progress track
  [CREATED] → [SCHEDULED] → [IN PROGRESS] → [COMPLETED]
  
  HEADER (glass card):
    Priority badge (large)
    Title (20pt, Playfair)
    Created: date + by whom
    
  DETAILS SECTION:
    Description
    Linked item (if any) — item mini-card
    Room
    Estimated cost (if set)
    
  TIMELINE SECTION:
    Chronological events for this work order
    "Marco P. accepted (Feb 3)" "Marco P. marked in-progress (Feb 5)"
    
  PHOTOS SECTION:
    Before photos: grid
    After photos: grid (adds when completing)
    [+ Add photo] chips
    
  CONTRACTOR SECTION:
    Contractor card (if assigned):
      Avatar + name + PRV-VERIFIED badge + rating
      [Message] [Call] [View profile]
    [+ Find contractor] (if not assigned) → Marketplace
    
  COST SECTION:
    Estimated vs. actual
    Invoice upload
    [Record payment] if PRV PAY not used
    
  [MARK COMPLETE] (gold button, bottom, sticky)
  When tapped: requires completion photos + sign-off
```

---

# B12. MARKETPLACE

## Layout

```
BACKGROUND: Warm urban/residential street scene (LPBE)

HERO SEARCH (top, prominent):
  Glass search bar (56pt, rounded):
    Icon: magnifying glass
    Placeholder: "What do you need help with?"
  
  [📍 My location] [⭐ PRV-Verified] [📅 Available today]
  Filter pills below search (horizontal scroll)

QUICK CATEGORIES (horizontal scroll, full-width section):
  Category pills with icons (glass, 100pt wide):
    🔧 Plumbing · ⚡ Electric · 🔥 Heating · 🏗️ Renovation
    🌿 Garden · 🔒 Security · ☀️ Solar · 🧹 Cleaning · [More]

ARIA RECOMMENDATIONS (if property context available):
  Glass card with gold accent border:
    ARIA icon + "Recommended for your home"
    Subtext: "Based on your maintenance history and property age"
    
  Horizontal scroll of provider cards (220pt wide):
    Provider photo + PRV-VERIFIED badge
    Name + specialty
    Rating + job count
    "Handles [type] in your area"
    [Request Quote]

ALL PROVIDERS (filtered list):
  Sort: [Relevance] [Rating] [Distance] [Price ▾]
  
  PROVIDER CARD (glass, full-width, 100pt):
    Left: provider photo (70 × 70pt, circle)
    Center:
      Name (15pt, semibold)
      Business + specialty (13pt, 60%)
      Rating: ★ 4.9 · 124 jobs · PRV-VERIFIED badge
    Right:
      Price range: "€80–€150/hr"
      [Quick Quote]
      
PROVIDER PROFILE (full screen):
  HERO (280pt):
    Cover photo (action/work photo)
    Glass overlay gradient
    Provider name + business (large, Playfair)
    PRV-VERIFIED badge
    Rating chip
    
  STATS ROW (4 glass chips):
    ★ 4.9 · 124 jobs · ≤1h response · 5y experience
    
  SERVICES SECTION:
    List of offered services + price ranges
    
  PORTFOLIO GRID (2-column photo grid):
    Work examples
    
  REVIEWS (filtered — most relevant shown first):
    Each review: rating + text + date + similar job badge
    
  PRV-VERIFIED BREAKDOWN:
    ✓ Identity verified
    ✓ Insurance valid (until Dec 2026)
    ✓ License: Class 1 Electrician
    ✓ Background check passed
    ✓ 124 jobs completed on PRV
    
  AVAILABILITY CALENDAR (simplified):
    Next 2 weeks, green = available, grey = booked
    Tap available day → request time slot
    
  BOTTOM CTA (sticky):
    [Request Quote — Free, no commitment]
    Gold button, full-width

JOB CREATION (from work order or fresh):
  ARIA JOB BRIEF (auto-generated):
    Glass card:
      "ARIA has prepared a job brief for your contractor."
      [Preview & Edit]
      
  BRIEF PREVIEW:
    Property: [name] · [address]
    Job description (ARIA-written, user-editable)
    Relevant photos (from inventory / maintenance)
    Access instructions: [auto-generated]
    Timeline: requested by [date]
    Budget: [range if set]
    [Send to contractor]
```

---

# B13. SETTINGS

## Layout

```
BACKGROUND: Minimal — deep obsidian gradient, very subtle noise texture
Feeling: Precise, trustworthy

PROFILE HEADER (glass card, 200pt):
  User photo (80pt circle, tap to change)
  Name (20pt, Playfair)
  Email (13pt, 65% opacity)
  Tier badge (PREMIUM glass pill + gold)
  "3 properties" count
  [Manage Plan →] gold text link

SECTIONS (glass table view, section headers):

ACCOUNT
  ○ Personal Information
  ○ Security & Privacy
  ○ Connected Accounts
  ○ Sessions & Devices
  ○ Notifications
  ○ Language & Region
  ○ Data & Export

PROPERTIES
  ○ Manage Properties
  ○ Property Members & Sharing
  ○ Data Sync

ARIA & AI
  ○ ARIA Preferences
  ○ Automation Level (1–4)
  ○ ARIA Memory
  ○ AI Data Processing

DISPLAY & EXPERIENCE
  ○ Theme (Obsidian / Pearl / Auto)
  ○ Background Engine (on/off + quality)
  ○ Reduce Motion
  ○ Dashboard Layout

INTEGRATIONS
  ○ Smart Home Platforms
  ○ Energy Meters
  ○ Security Systems
  ○ Calendar Sync
  ○ API & Webhooks

BILLING
  ○ Current Plan
  ○ Payment Method
  ○ Invoices
  ○ Referral Program

SUPPORT
  ○ Help Center
  ○ Contact Support
  ○ Report a Bug
  ○ Community
  ○ What's New

LEGAL
  ○ Privacy Policy
  ○ Terms of Service
  ○ Data Processing Agreement

[LOG OUT] — glass button, centered, 60% opacity, muted
[DELETE ACCOUNT] — only in Security & Privacy section, requires MFA

ROW DESIGN (each setting row):
  Left: icon (24pt, glass circle background)
  Center: label (15pt) + description (12pt, 60%, optional)
  Right: chevron or toggle or value chip

TOGGLE ROWS:
  Standard iOS/Material switch style (gold when on, glass track)

THEME SELECTION:
  3 option cards (glass):
    [Obsidian — dark] [Pearl — light] [Auto — system]
    Preview: mini screenshot of dashboard in each theme
    Selected: gold border

NOTIFICATIONS (detailed):
  Per-module toggles + per-type within module
  CRITICAL: always on (cannot disable — explained why)
  ARIA Insights: frequency slider (Minimal / Normal / Proactive)
  Quiet Hours: time range + exceptions (CRITICAL always through)
```

---

*End of Phase B — Glass OS Master Design*

**Document status:** Complete v1.0  
**Next:** Phase C — Design System Complete Specification
