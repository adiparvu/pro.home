# PHASE A — PRODUCT BLUEPRINT
## PRV HOUSE — The Property Operating System
### Production-Grade Product Specification

**Document version:** 1.0  
**Status:** Active  
**Constitution references:** PRV_HOUSE_VISION_v1.0 · PRV_HOUSE_VISION_V2_v1.0

---

# TABLE OF CONTENTS

- [A1. Information Architecture](#a1-information-architecture)
- [A2. User Personas](#a2-user-personas)
- [A3. User Journey Maps](#a3-user-journey-maps)
- [A4. Critical User Flows](#a4-critical-user-flows)
- [A5. Navigation System](#a5-navigation-system)
- [A6. Module Relationships](#a6-module-relationships)
- [A7. Feature Hierarchy — MVP / V2 / V3](#a7-feature-hierarchy)
- [A8. Permission Matrix Validation](#a8-permission-matrix-validation)
- [A9. Module Specifications](#a9-module-specifications)

---

# A1. INFORMATION ARCHITECTURE

## Complete Sitemap

```
PRV HOUSE
│
├── AUTH
│   ├── Login
│   │   ├── Email + Password
│   │   ├── Magic Link
│   │   ├── Apple Sign In
│   │   ├── Google Sign In
│   │   ├── Microsoft Sign In
│   │   └── Passkey
│   ├── Register
│   │   ├── Email Registration
│   │   └── OAuth Registration
│   ├── Forgot Password
│   ├── Reset Password
│   ├── MFA Setup
│   │   ├── TOTP Setup
│   │   └── Hardware Key Setup
│   └── MFA Challenge
│
├── ONBOARDING (new users only)
│   ├── Step 1 — Welcome + Language
│   ├── Step 2 — Property Type
│   ├── Step 3 — Property Address
│   ├── Step 4 — Property Details
│   ├── Step 5 — Smart Home Connect (optional)
│   └── Step 6 — Meet ARIA
│
├── HOME DASHBOARD
│   ├── Property Hero + Health Score
│   ├── Energy Widget
│   ├── Security Widget
│   ├── ARIA Insight Card
│   ├── Maintenance Widget
│   ├── Project Widget
│   ├── Finance Widget
│   ├── Family Presence Widget
│   ├── Smart Home Quick Controls
│   └── Notifications Panel
│
├── PROPERTIES
│   ├── Portfolio View (multi-property)
│   ├── Property Overview
│   │   ├── Profile (address, details, photos)
│   │   ├── Health Index breakdown
│   │   ├── Quick stats
│   │   └── Co-owner management
│   ├── Rooms & Spaces
│   │   ├── Floor plan view
│   │   ├── Room list
│   │   └── Room detail
│   │       ├── Photos
│   │       ├── Items (inventory)
│   │       ├── Devices (smart home)
│   │       ├── Condition log
│   │       └── Notes
│   ├── Systems
│   │   ├── HVAC
│   │   ├── Electrical
│   │   ├── Plumbing
│   │   ├── Structure
│   │   └── Other systems
│   ├── Documents
│   │   ├── Legal
│   │   ├── Financial
│   │   ├── Technical
│   │   ├── Permits
│   │   └── Manuals & Warranties
│   ├── Digital Twin
│   │   ├── 3D View
│   │   ├── IoT Layer
│   │   ├── Systems Layer
│   │   ├── AI Layer
│   │   └── Time Machine
│   ├── History & Timeline
│   └── Property Settings
│
├── INVENTORY (M-SCAN™)
│   ├── All Items
│   ├── By Room
│   ├── By Category
│   │   ├── Appliances
│   │   ├── Furniture
│   │   ├── Electronics
│   │   ├── Systems & Equipment
│   │   └── Outdoor
│   ├── Warranties
│   │   ├── Active
│   │   ├── Expiring Soon (< 90 days)
│   │   └── Expired
│   ├── Recalls
│   │   ├── Active Recalls
│   │   └── Cleared
│   ├── Item Detail
│   │   ├── Identity (brand, model, serial)
│   │   ├── Documents (manual, receipt, warranty)
│   │   ├── Maintenance history
│   │   ├── Financial (purchase, current value)
│   │   └── ARIA diagnostics
│   └── Import / Scan
│       ├── Barcode / QR scan
│       ├── Nameplate photo (M-SCAN™)
│       ├── Receipt OCR import
│       └── Manual entry
│
├── MAINTENANCE
│   ├── Calendar View
│   ├── List View (by status)
│   │   ├── Overdue
│   │   ├── Due This Month
│   │   ├── Upcoming (3 months)
│   │   └── Completed
│   ├── Work Orders
│   │   ├── Open
│   │   ├── In Progress
│   │   ├── Completed
│   │   └── Cancelled
│   ├── Work Order Detail
│   │   ├── Description & priority
│   │   ├── Photos (before/after)
│   │   ├── Assigned contractor
│   │   ├── Schedule & costs
│   │   └── Notes & sign-off
│   ├── Predictive Alerts (ARIA)
│   ├── Maintenance Templates
│   │   ├── Annual schedule
│   │   └── Seasonal checklists
│   └── History Archive
│
├── SMART HOME
│   ├── Overview (all devices status)
│   ├── By Room
│   ├── Device Detail
│   │   ├── Controls
│   │   ├── History / events
│   │   ├── Automations linked
│   │   └── Settings
│   ├── Scenes
│   │   ├── Active scenes
│   │   └── Scene editor
│   ├── Automations
│   │   ├── Active automations
│   │   └── Automation builder
│   ├── Energy (device-level)
│   └── Integrations
│       ├── Apple Home
│       ├── Google Home
│       ├── Amazon Alexa
│       ├── Home Assistant
│       ├── SmartThings
│       └── Matter devices
│
├── SECURITY
│   ├── Live View (cameras)
│   ├── Event Log
│   │   ├── All events
│   │   ├── Motion
│   │   ├── Access
│   │   └── Alarms
│   ├── Access Control
│   │   ├── Smart Locks
│   │   ├── Access Codes
│   │   ├── Digital Keys
│   │   └── Access History
│   ├── Alarm System
│   │   ├── Status + arm/disarm
│   │   ├── Zones
│   │   └── History
│   ├── Camera Management
│   │   ├── Camera list
│   │   ├── Recording settings
│   │   └── Storage
│   └── Security Settings
│
├── ENERGY
│   ├── Overview Dashboard
│   │   ├── Energy flow diagram
│   │   ├── Today / This month / This year
│   │   └── Cost breakdown
│   ├── Electricity
│   │   ├── Consumption chart
│   │   ├── Peak analysis
│   │   └── Tariff settings
│   ├── Gas
│   ├── Water
│   ├── Solar
│   │   ├── Production
│   │   ├── Self-consumption rate
│   │   └── Export revenue
│   ├── Battery
│   │   ├── State of charge
│   │   └── Charge/discharge history
│   ├── EV Charging
│   │   ├── Session history
│   │   └── Schedule
│   ├── Optimization (ARIA)
│   │   ├── Recommendations
│   │   ├── Automated schedules
│   │   └── Savings achieved
│   └── Bills & Providers
│
├── GARDEN
│   ├── Garden Map
│   ├── Plants
│   │   ├── Plant library
│   │   ├── Care schedules
│   │   └── Health log
│   ├── Irrigation
│   │   ├── Zone control
│   │   ├── Schedule
│   │   └── Water usage
│   ├── Pool & Spa
│   │   ├── Chemistry log
│   │   ├── Equipment
│   │   └── Maintenance
│   └── Outdoor Equipment
│
├── PROJECTS
│   ├── Active Projects
│   ├── Planned Projects
│   ├── Completed Archive
│   ├── Project Detail
│   │   ├── Overview
│   │   ├── Phases & Tasks
│   │   ├── Budget tracker
│   │   ├── Documents
│   │   ├── Team
│   │   ├── Progress photos
│   │   └── Communication log
│   └── New Project Wizard
│
├── FINANCE
│   ├── Overview (P&L)
│   ├── Transactions
│   │   ├── Income
│   │   └── Expenses
│   ├── Insurance
│   │   ├── Policies
│   │   └── Claims
│   ├── Valuation
│   │   ├── Current estimate
│   │   └── History chart
│   ├── Mortgage & Loans
│   ├── Tax
│   │   ├── Deductible expenses
│   │   └── Reports
│   └── Budget Planner
│
├── MARKETPLACE
│   ├── Search
│   ├── Categories
│   ├── ARIA Recommendations
│   ├── Provider Profile
│   │   ├── Portfolio
│   │   ├── Reviews
│   │   ├── Availability
│   │   └── Quote request
│   ├── My Jobs
│   │   ├── Active
│   │   ├── Scheduled
│   │   └── Completed
│   ├── Job Detail
│   │   ├── Brief & scope
│   │   ├── Quotes received
│   │   ├── Communication
│   │   ├── Progress
│   │   └── Payment
│   └── My Contractors (saved)
│
├── FAMILY
│   ├── Family Map (presence)
│   ├── Members List
│   ├── Member Detail
│   │   ├── Profile
│   │   ├── Permissions (module by module)
│   │   ├── Access schedule
│   │   └── Activity log
│   ├── Invite Member
│   ├── Guest Management
│   └── Family Activity Feed
│
├── ARIA
│   ├── Conversation
│   ├── Insights Feed
│   │   ├── Urgent
│   │   ├── Recommended
│   │   └── Informational
│   ├── Morning Briefing
│   ├── ARIA Memory
│   │   ├── What ARIA knows
│   │   └── Preferences
│   └── Automation Level Settings
│
└── SETTINGS
    ├── Account
    │   ├── Profile
    │   ├── Security & Privacy
    │   ├── Connected Accounts
    │   ├── Sessions & Devices
    │   ├── Notifications
    │   └── Data & Export
    ├── Properties
    │   ├── Manage properties
    │   └── Property settings
    ├── ARIA & AI
    ├── Display & Design
    ├── Integrations
    ├── Billing
    └── Support & Legal
```

---

# A2. USER PERSONAS

## Persona 1 — The Premium Homeowner (Primary)
**Name:** Alexandru M., 41, Bucharest  
**Property:** Villa, 280m², purchased 2019  
**Tech comfort:** High  
**Pain:** Manages everything in Gmail, WhatsApp, and memory. Has had 3 expensive emergency repairs in 2 years.  
**Goal:** Total control and zero surprises.  
**Quote:** *"I spend €15,000/year on my home and I have no idea where it all goes."*

---

## Persona 2 — The Portfolio Owner (Secondary)
**Name:** Monica D., 48, Amsterdam  
**Property:** Primary residence + 2 rental apartments  
**Tech comfort:** Medium-High  
**Pain:** Manages tenants via WhatsApp, uses Excel for finances, misses maintenance.  
**Goal:** Professional management without a property manager.  
**Quote:** *"I need one place to see everything — all 3 properties, all tenants, all costs."*

---

## Persona 3 — The Family Manager (Secondary)
**Name:** Elena P., 36, Brussels  
**Property:** House with partner + 2 children + elderly mother in annexe  
**Tech comfort:** Medium  
**Pain:** Home runs smoothly only because she remembers everything. No delegation possible.  
**Goal:** Share the load with her partner and know her mother is safe.  
**Quote:** *"I'm the operating system of this house. I need help."*

---

## Persona 4 — The Property Manager (B2B)
**Name:** Bogdan S., 33, Cluj  
**Portfolio:** Manages 40 properties for 12 owners  
**Tech comfort:** High  
**Pain:** Coordinates via phone, email, WhatsApp. Spreadsheets for every owner. Manual reports.  
**Goal:** Professional platform that makes him look like a premium service provider.  
**Quote:** *"My clients trust me, but the tools I use are embarrassing."*

---

## Persona 5 — The Tech Early Adopter (Influencer Persona)
**Name:** Radu V., 29, Iași  
**Property:** Apartment, 90m², fully smart home equipped  
**Tech comfort:** Very High  
**Pain:** 8 apps for one apartment. No unified view. Automation logic split across Alexa + Home Assistant + Google.  
**Goal:** One platform that replaces everything.  
**Quote:** *"I want Apple-level elegance for my home. It doesn't exist yet."*

---

## Persona 6 — The Vacation Home Owner (Niche)
**Name:** Isabelle L., 52, Paris (vacation home in Provence)  
**Property:** Primary Paris apartment + vacation home  
**Tech comfort:** Medium  
**Pain:** Vacation home is dark for 8 months/year. Break-ins, maintenance surprises, short-term rental management.  
**Goal:** Complete remote visibility and control.  
**Quote:** *"I want to open my app in Paris and see exactly what's happening in Provence right now."*

---

# A3. USER JOURNEY MAPS

## Journey 1 — New Homeowner (Alexandru, Persona 1)

```
STAGE          TOUCHPOINT         ACTION                 EMOTION       OPPORTUNITY
─────────────────────────────────────────────────────────────────────────────────
AWARENESS      Instagram ad       Sees PRV HOUSE demo    Curious       Show the "6 apps → 1" message
               Word of mouth      Friend recommends      Interested    Referral program
               
CONSIDERATION  Website            Watches product video  Impressed     Show LPBE + ARIA demo
               App Store          Reads reviews          Cautious      Show real user testimonials
               
SIGNUP         App Store          Downloads app          Hopeful       Onboarding must be instant magic
               Onboarding Step 1  Enters name + language Easy          Language auto-detect from device
               
FIRST VALUE    Onboarding Step 3  Adds property address  Engaged       Map shows property, weather activates
               Scan first item    M-SCAN™ finds manual   "WOW"         This is the first WOW moment
               
ENGAGEMENT     Day 3              ARIA morning briefing  Delighted     Personalised to their property
               Week 1             Connects smart devices Invested      Device grid populates
               Week 2             Receives predictive    Relieved      "ARIA saved me"
                                  maintenance alert
                                  
RETENTION      Month 1            Pays for Premium       Committed     Value clear before paywall
               Month 3            Invites partner        Expanded      Family value multiplies retention
               Month 6            Uses Marketplace       Habitual      Contractor booked via app
               
ADVOCACY       Month 9            Recommends to friend   Proud         PRV referral reward active
               Year 1             Leaves App Store       Ambassador    Prompt at anniversary milestone
                                  review
```

---

## Journey 2 — Portfolio Owner (Monica, Persona 2)

```
STAGE          TOUCHPOINT         ACTION                 EMOTION       OPPORTUNITY
─────────────────────────────────────────────────────────────────────────────────
AWARENESS      LinkedIn ad        "Property OS for       Intrigued     B2B messaging: professional
               (targeted)         landlords"                           control, not homeowner apps
               
TRIAL          Portfolio view     Sees 3 properties      Impressed     Portfolio dashboard in first 60s
               Finance module     Sees P&L per property  Relieved      Replace her Excel immediately
               
ONBOARDING     Setup 3 properties Quick import flow      Efficient     Bulk import + CSV support
               Add tenants        Tenant invite flow     Smooth        WhatsApp-like simplicity
               
ACTIVATION     First rent payment Tenant pays in-app    Trusted       Payment confirmation SMS
               Maintenance alert  Routes to correct      Relieved      Auto-routes by property
                                  property
                                  
RETENTION      Month 2            Monthly auto-report    Delighted     Replaces 3 hours of Excel work
               Month 4            Tenants rate 4.9★      Proud         Tenant satisfaction visible
               
EXPANSION      Month 6            Adds 4th property      Invested      Upgrade to Portfolio plan
               Year 1             Refers other landlord  Advocate      Referral = 2 months free
```

---

## Journey 3 — Emergency Scenario (Any Persona)

```
TRIGGER        Water leak detected by sensor at 03:00

03:00:01  Sensor fires → PRV HOUSE receives event
03:00:03  ARIA classifies: CRITICAL — active water leak
03:00:05  Push notification sent to Owner (priority, breaks DND)
03:00:05  Security camera in area activates automatically
03:00:08  Owner opens notification → sees camera feed + leak location on twin
03:00:15  ARIA screen: "Leak detected: kitchen sink area. Est. 0.8L/min."
03:00:15  ARIA shows: [Shut Off Water Main] [Call Plumber Now] [Dismiss]
03:00:20  Owner taps [Shut Off Water Main] → smart valve closes
03:00:22  Confirmation: "Water main valve closed. Leak stopped."
03:00:30  ARIA: "I've found 2 emergency plumbers available now.
          Marcus P. (★4.9, 12 min away) - tap to call directly."
03:01:00  Plumber called, arrives 03:13
03:15:00  Work order auto-created: "Emergency pipe repair — kitchen"
03:30:00  Plumber completes repair, marks done in PRV HOUSE
03:30:00  Insurance documentation auto-prepared: photos, timeline, costs
03:31:00  ARIA: "Incident documented. Ready for insurance if needed."

OUTCOME: Emergency resolved in 30 minutes. Fully documented.
         Pre-PRV HOUSE: 2-3 hours of panic, water damage, no documentation.
```

---

# A4. CRITICAL USER FLOWS

## Flow 1 — Account Registration & First Login
```
START: App opened, no account

1. Welcome screen (LPBE active)
   → [Create Account] primary CTA
   → [Sign In] secondary

2a. OAuth path (Apple / Google / Microsoft):
   → Tap provider button
   → System auth sheet
   → Permissions granted
   → Account created
   → → Onboarding Flow (Flow 3)

2b. Email path:
   → Email field
   → Password field (strength meter, HIBP check)
   → [Create Account]
   → Verification email sent
   → "Check your email" screen (resend option, 60s countdown)
   → Click link in email → deep link → app opens
   → → Onboarding Flow (Flow 3)

2c. Magic Link path:
   → Email field
   → [Send Magic Link]
   → "Check your email" screen
   → Click link → deep link → authenticated
   → → Onboarding Flow (Flow 3)

EDGE CASES:
- Email already registered → "Account exists. Sign in instead?" [Sign In]
- Weak password → inline error before submit
- Email not received → resend after 60s, then "try a different method"
- App killed during verification → resume on reopen (deep link still valid)
- Link expired (>15 min) → "Link expired. Request a new one" [Resend]
```

---

## Flow 2 — MFA Setup
```
TRIGGER: First login, or manually in Settings > Security

1. "Protect your account" screen
   → Explains why MFA matters (one sentence)
   → [Set Up Now] [Skip for now — not recommended]

2a. Passkey path:
   → "Set up a passkey for passwordless login"
   → Platform biometric prompt (Face ID / fingerprint)
   → Passkey created + synced to iCloud/Google
   → Success: "Passkey ready. You can now log in with Face ID."
   → [Continue]

2b. Authenticator App path:
   → QR code displayed
   → "Open your authenticator app and scan this code"
   → 6-digit code entry field
   → Submit → verify → success
   → Recovery codes displayed (8 codes)
   → MANDATORY: [I've saved these codes] checkbox before continuing

2c. SMS path (shown with warning):
   → "SMS is less secure than authenticator apps. Use only as backup."
   → Phone number entry
   → SMS sent → 6-digit verification
   → Warning: "SMS can be intercepted. Consider adding an authenticator app."

EDGE CASES:
- Wrong TOTP code → "Incorrect code. Codes change every 30 seconds."
- Authenticator not synced (clock drift) → show clock sync link
- Lost phone → recovery codes flow
- Can't access any method → support flow with identity verification
```

---

## Flow 3 — Onboarding (New User, No Property)
```
PRECONDITION: Authenticated, no properties added

STEP 1 — Welcome (30 seconds max)
  → LPBE: Beautiful architectural scene
  → "Welcome to PRV HOUSE" + ARIA animation
  → Name field + language selector (6 flags)
  → [Get Started]

STEP 2 — Property Type (10 seconds)
  → Full-screen illustrated card selector
  → Types: House / Apartment / Villa / Vacation Home / Land / Commercial
  → Tap to select → card scales up + gold border
  → [Continue]

STEP 3 — Property Address (30 seconds)
  → Address search (autocomplete, Google Places)
  → User types 3+ chars → suggestions appear
  → Select address → map preview shows (satellite 3D)
  → Confirm: "Is this your property?" → [Yes, continue] [Change]

STEP 4 — Property Details (60 seconds — skippable)
  → 5 fields with smart defaults:
    Property name (pre-filled: "Our Home")
    Year built (optional — helps ARIA predict maintenance)
    Area in m² (optional)
    Floors (optional)
    How do you use it? Live in / Rent out / Both
  → [Save & Continue] or [Skip for now]

STEP 5 — Connect Smart Home (skippable)
  → "Do you have smart home devices?"
  → 6 platform tiles + [Connect later]
  → If connected: device discovery (15s)
    → "Found 12 devices. Let's place them in rooms."
    → 3 sample devices shown with room assignment
    → [Finish setup later]
  → If skipped: continue

STEP 6 — Meet ARIA
  → Constellation animation
  → ARIA speaks: "I'm ready to learn about your home."
  → First ARIA suggestion based on what was entered
  → [Take a quick tour (2 min)] or [Go to my home]

EDGE CASES:
- Address not found (rural property) → manual GPS pin on map
- Property type wrong → can change in settings any time
- Smart home connect fails → skip with "Try again in Settings > Integrations"
- User exits mid-onboarding → resume where left off on next open
- Multiple devices → sync progress via account
```

---

## Flow 4 — M-SCAN™ Appliance Scan
```
ENTRY POINTS:
A. Dashboard → "+" button → "Scan Appliance"
B. Inventory → "+" → "Scan"
C. Room view → "+" → "Add Item" → "Scan"

SCAN FLOW:
1. Camera opens with frame guide
   "Point at nameplate, barcode, or QR code"
   
2a. Barcode / QR detected:
   → Scan succeeds (< 1 second)
   → "Found: Bosch SMS68TI01E Dishwasher"
   → Data loaded: brand, model, manual, warranty period
   → [Confirm] → proceed to Step 4

2b. Nameplate photo (M-SCAN™ AI):
   → "Hold steady — capturing nameplate"
   → Photo taken + AI processing (3-8 seconds)
   → Loading state: "ARIA is reading this..."
   → Result: extracted brand, model, serial number
   → Confidence: if < 70% → show fields for manual correction
   → [Confirm or edit] → proceed to Step 4

2c. Manual entry fallback:
   → Button visible always: "Enter manually"
   → Category selector → brand → model search → or free text

3. Item not found in database:
   → "I don't have data for this model."
   → [Enter details manually] or [Search online]
   → Partial match: "Did you mean one of these?"
   → User can still save with basic details

4. Item Detail Review:
   → Pre-populated form:
     Name (editable), Brand, Model, Serial No.
     Room assignment (dropdown)
     Purchase date (optional, date picker)
     Purchase price (optional)
     Warranty end date (auto-calculated if start entered)
   → Photos: "Add a photo of this item" (optional)
   → [Save to Inventory]

5. Saved confirmation:
   → Item card animates into inventory
   → "Saved to [Room]. Warranty expires [Date]."
   → ARIA: "I found the manual for this item. Saved to Documents."
   → [Scan another] [Done]

EDGE CASES:
- Nameplate unreadable (dirty/damaged) → "Can't read this nameplate. Try manual entry."
- Camera permission denied → prompt to enable in Settings
- Offline scanning → queue scans, sync when online
- Duplicate item → "This serial number is already in your inventory. Update it?"
- Recall detected → immediate alert overlay: "SAFETY ALERT: Active recall on this product."
```

---

## Flow 5 — Create & Assign Maintenance Work Order
```
TRIGGER OPTIONS:
A. Predictive alert from ARIA (most common)
B. Manual: Maintenance → "+" 
C. Device diagnostic alert
D. During inventory item review

FLOW:
1. Work Order creation:
   Title (ARIA pre-fills for predictive tasks)
   Description (ARIA pre-fills based on context)
   Property & Room assignment
   Item link (optional, searchable inventory)
   Priority: CRITICAL / HIGH / MEDIUM / LOW (ARIA suggests)
   
2. Scheduling:
   "When do you need this done?"
   Date picker (calendar view, shows conflicts)
   Time preference: Morning / Afternoon / Flexible
   
3. "Find a contractor?" [Yes] [I'll handle this myself]

3a. YES → Marketplace matching:
   ARIA brief: prepares job scope from property context
   Matching: top 3 PRV-VERIFIED contractors shown
     Each card: name, rating, price range, availability, response time
   → [Request Quote from Selected]
   → Provider receives: job brief + property address + photo from inventory
   → Provider responds (24h target)
   → Owner sees: [Accept & Schedule] [Decline] [Counter-offer]

3b. NO → self-manage:
   → Cost estimate field (manual)
   → Notes field
   → [Save Work Order]

4. Scheduled work order:
   → Calendar entry created
   → Day-before reminder notification
   → Morning-of notification: "[Contractor] arrives at 10:00"
   → Auto-generated access code valid contractor arrival window ± 30 min

5. During job:
   → Contractor checks in (geofence, optional)
   → "Marco has arrived" notification to owner
   → Real-time chat in PRV HOUSE (no WhatsApp needed)

6. Completion:
   → Contractor marks done + uploads completion photos
   → Owner receives: [Review & Approve] notification
   → Owner reviews photos + marks approved
   → PRV PAY releases (if used) or manual payment recorded
   → Rating prompt (stars + optional comment)
   → Work order archived with full documentation

EDGE CASES:
- No contractors available → "No contractors matched. Expand radius or change date."
- Contractor cancels → immediate notification, re-match offered
- Cost overrun → Change order request from contractor → owner approval
- No-show → "Contractor hasn't checked in. Call them?" with one-tap call
- Job disputed → PRV support escalation
- Offline → work order saved locally, synced when online
```

---

## Flow 6 — Invite Family Member
```
ENTRY: Family → "+" (Owner only)

1. Choose role:
   [Partner] [Adult Child] [Teen] [Child] [Elderly Parent]
   [Tenant] [Guest] [Trusted Contact]
   Each with 1-sentence description and default permission summary

2. Basic info:
   Name
   Email (for invite link)
   Photo (optional)

3. Permission configuration (simplified):
   Smart Home: [All rooms] [Selected rooms] [None]
   Security:   [Full access] [View only] [None]
   Doors:      [All] [Front door only] [None]
   Documents:  [View] [None]
   Finances:   [View] [None]
   Maintenance:[Create & view] [View only] [None]
   
   Advanced toggle → granular control screen (per-module, per-room)

4. Schedule (optional):
   Access hours toggle: [Always] [Set schedule]
   If schedule: day picker + time range per day

5. Preview:
   "This is what [Name] will see in PRV HOUSE"
   Simplified visual of their permission level

6. Send invite:
   [Send invite by email] [Share link] [Copy code]
   Invite expires in: [24h] [7 days] [30 days] (default 7 days)

7. Invite sent:
   Pending member shown in Family list with "Invited" badge
   Owner can modify permissions while pending
   Owner can revoke invite

INVITED PERSON FLOW:
   Email arrives → "You've been invited to PRV HOUSE by [Owner]"
   CTA: [Accept Invitation]
   → App Store / web
   → Login or create account
   → Permissions preview: "You can access: [list]"
   → [Accept & Enter]
   → Lands in property view (scoped to their permissions)

EDGE CASES:
- Email already has PRV account → links to existing account, no new registration
- Invitee declines → owner notified, invitation removed
- Invite link expired → owner can resend from Family > Pending invites
- Role change after acceptance → in-app notification to member
- Remove member → data scoped to them is removed, logs kept for owner
```

---

## Flow 7 — ARIA Conversation
```
ENTRY POINTS:
A. Dashboard ARIA FAB (always visible)
B. Notification tap → "Ask ARIA about this"
C. Long-press any data element → "Ask ARIA"
D. Voice: "Hey ARIA"
E. Widget: ARIA insight card → expand

FLOW:
1. ARIA panel opens (glass sheet from bottom)
   Property context bar shows: health score, active alerts
   If has pending insight: shown as highlighted card at top
   
2. User initiates:
   A. Taps suggestion chip
   B. Types query
   C. Speaks (voice activates)
   
3. ARIA processes:
   Loading state: "Thinking..." with subtle animation (1-4 seconds)
   Retrieves from knowledge graph:
     - Property data (devices, inventory, maintenance history)
     - Relevant documents
     - Recent events
     - External context (weather, market data)
   
4. ARIA responds:
   Text response (typewriter animation, 30ms/char)
   Inline data cards (when referencing specific items)
   Action buttons (when suggesting specific action)
   
5. Follow-up:
   Suggestion chips for natural follow-up questions
   User continues conversation (full context maintained)
   
6. Action taken:
   If action approved: ARIA executes + confirms
   "I've created that work order. Want me to find a contractor?"
   
SPECIAL STATES:
- Voice active: waveform visualizer, hands-free response
- Multi-property: ARIA asks which property if ambiguous
- Offline: "I'm working from cached data. Some information may be outdated."
- Complex query (> 8 seconds): "This is taking a moment — your property data is large."
```

---

## Flow 8 — Emergency Protocol
```
TRIGGER: Critical security or safety event (smoke, intrusion, water leak)

AUTOMATIC SEQUENCE (no user input required):
1. Sensor/camera detects event
2. PRV HOUSE classifies severity (CRITICAL / HIGH / MEDIUM)
3. For CRITICAL:
   a. Push notification (breaks silent mode)
   b. Lock screen notification with photo
   c. Apple Watch + Android Wear alert (haptic)
   d. Family members notified simultaneously (per permissions)

USER RESPONSE FLOW:
4. User opens notification
5. Emergency screen shown (full-screen, not normal UI):
   Large: Event type + location (room/area)
   Live camera feed (if applicable)
   Property map with event location highlighted
   
6. Emergency action panel:
   Context-appropriate actions shown:
   Intrusion: [Lock All Doors] [Call Police] [Trigger Siren] [False Alarm]
   Fire: [Call Fire Dept] [Evacuate Guide] [Shut Off HVAC] [False Alarm]
   Leak: [Shut Off Water Main] [Call Emergency Plumber] [Log for Insurance]
   Medical: [Call Ambulance] [Call Emergency Contact] [Unlock Front Door]
   
7. Action execution:
   One tap → immediate execution
   Confirmation: "Done — [action taken] at [time]"
   
8. Post-event:
   ARIA auto-documents: timeline, photos, devices triggered, actions taken
   "Incident report ready. Want to share with insurance?"
   Work order auto-created (for damage events)

EDGE CASES:
- User unreachable → escalate to next family member in chain
- No internet (edge case) → PRV Bridge acts autonomously per pre-set rules
- Multiple simultaneous alerts → triage by severity, show most critical first
- False alarm → mark as false, ARIA notes pattern for sensitivity adjustment
```

---

## Flow 9 — Energy Optimization
```
TRIGGER: A. ARIA proactive suggestion
          B. User opens Energy module
          C. New device connected

FLOW:
1. Energy overview loads:
   Real-time Sankey diagram: Grid in → Appliances → Export
   Today / This week / This month tabs
   
2. ARIA Optimization Panel:
   If potential savings identified, banner appears:
   "I found 3 ways to save €127/month. View recommendations?"
   
3. Recommendations list:
   Each rec: Description + estimated saving + effort level + [Apply]
   
   Example recommendations:
   a. "Shift EV charging to 23:00–06:00 (off-peak tariff). Save €67/month."
      [Apply Automatically] [Do it once] [Dismiss]
   
   b. "Your fridge is running 18% above expected for its age. 
      Check seal integrity. Save €22/month if fixed."
      [Create Maintenance Task] [Dismiss]
   
   c. "Set washing machine to run at 14:00 on sunny days 
      (solar surplus peak). Save €38/month."
      [Create Automation] [Dismiss]

4. Apply Automation:
   [Create Automation] → shows automation preview
   "When solar_production > 2kW AND washing_machine = idle:
   → Run washing machine"
   [Activate] → done

5. Savings tracking:
   Dashboard: "ARIA has saved you €234 this month" (cumulative tracker)

EDGE CASES:
- No smart devices for scheduling → recommendations show manual tips
- Multiple EV chargers → can set individual schedules per vehicle
- Tenant uses energy → visibility depends on billing arrangement
- Solar not installed → section shows: "Add solar to unlock this" with ROI calculator
```

---

## Flow 10 — Property Handover (Sale/Transfer)
```
TRIGGER: Owner initiates property transfer

FLOW:
1. Settings → Property → [Transfer Property]
2. Warning screen: "This transfers all property data to a new owner."
   MFA challenge required
3. Enter new owner email or generate transfer code
4. PRV HOUSE prepares Property Passport™:
   - Full maintenance history
   - All documents (owner chooses what to include)
   - Inventory (owner chooses what stays/goes)
   - Smart device list
   - Renovation history
   - Energy history
5. Preview: "New owner will receive [summary]"
   [Edit what to share] → toggle per category
6. Transfer initiated:
   New owner receives email + in-app notification
   "You've received a property from [name]. Accept transfer?"
7. New owner accepts → property moves to their account
   Full history preserved and visible to new owner
8. Previous owner: property removed from their dashboard
   Download of "Your property history export" offered

EDGE CASES:
- New owner not on PRV HOUSE → invite link + property waits 30 days
- Transfer disputed → support escalation, property frozen
- Co-owned property → all owners must approve transfer
- Partial transfer (e.g., selling one unit of multi-unit) → split property
```

---

## Flows 11–20 (Summary Reference)

| # | Flow | Entry | Key Steps |
|---|---|---|---|
| 11 | **Document Upload** | Documents → + | Upload → OCR → auto-categorize → expiry detect |
| 12 | **Smart Home Scene Create** | Smart Home → Scenes → + | Name → add device actions → set trigger → activate |
| 13 | **Tenant Onboarding** | Family → + → Tenant | Invite → unit assignment → permissions → payment setup |
| 14 | **Security Camera Playback** | Security → Event | Select event → scrub timeline → export clip |
| 15 | **Garden Irrigation Schedule** | Garden → Irrigation | Zone select → schedule → weather integration toggle |
| 16 | **Insurance Claim** | Finance → Insurance → + Claim | Incident describe → upload evidence → ARIA prepares report |
| 17 | **Project Creation** | Projects → + | Type → budget → phases → team → documents |
| 18 | **Contractor Rating** | Work Order → Complete | Star rating → comment → submit → contractor notified |
| 19 | **ARIA Memory Management** | Settings → ARIA → Memory | View preferences → delete specific memory → reset all |
| 20 | **Data Export (GDPR)** | Settings → Data & Export | Select scope → format → confirm identity → download |

---

# A5. NAVIGATION SYSTEM

## Platform Navigation Models

### Mobile (iPhone)
```
PRIMARY NAVIGATION: Bottom Tab Bar (5 tabs max)

Tab 1 — HOME (house icon)
  → Dashboard
  
Tab 2 — PROPERTY (building icon)
  → Current property overview
  → Swipe/switch: other properties
  → Sub-tabs: Rooms / Documents / Twin

Tab 3 — SMART (mesh icon)
  → Smart Home + Security + Energy unified control center

Tab 4 — MANAGE (checklist icon)
  → Maintenance + Projects + Marketplace

Tab 5 — MORE (grid icon)
  → Family / Finance / Garden / ARIA / Settings

ARIA FAB: Always visible, bottom-right, above tab bar (56pt circle, gold)
NOTIFICATION: Bell icon in nav bar header
PROPERTY SWITCH: Top center pill → tap → property switcher sheet

NAVIGATION RULES:
- Max 3 levels deep from any tab
- Back always available (swipe right or back button)
- Modal sheets for: item detail, ARIA, quick actions, settings panels
- No dead ends — always show related content or suggested action
```

### Tablet (iPad)
```
PRIMARY NAVIGATION: Left Sidebar (collapsible)
  Width: 280pt (expanded), 72pt (collapsed — icon only)
  
  Sections:
  PROPERTIES (header with selector)
    ├── Dashboard
    ├── Rooms & Spaces
    ├── Inventory
    └── Documents
    
  SYSTEMS
    ├── Smart Home
    ├── Security
    └── Energy
    
  MANAGEMENT
    ├── Maintenance
    ├── Projects
    └── Finance
    
  COMMUNITY
    ├── Family
    └── Marketplace
    
  ARIA (always at bottom of sidebar)
  
CONTENT AREA: Remaining width
DETAIL PANEL: Right panel opens for detail views (iPad UISplitViewController pattern)
```

### Desktop (Web / Mac)
```
PRIMARY NAVIGATION: Left sidebar (always expanded)
  Same structure as tablet

TOP BAR:
  Left: PRV HOUSE logo + property name
  Center: Global search (command+K)
  Right: Notifications + Account menu

CONTENT: Full-width main area
PANELS: Right panels for detail, ARIA, notifications
COMMAND PALETTE (command+K):
  Quick navigation
  Quick actions (create task, scan item, open ARIA)
  Property switch
```

---

## Deep Linking Structure
```
URL PATTERN: prvhouse://[property_id]/[module]/[entity_id]

Examples:
prvhouse://home                           → Dashboard
prvhouse://property/[id]                  → Property overview
prvhouse://property/[id]/room/[room_id]   → Room detail
prvhouse://inventory/[item_id]            → Item detail
prvhouse://maintenance/[task_id]          → Task detail
prvhouse://security/live                  → Live security view
prvhouse://energy                         → Energy dashboard
prvhouse://aria                           → ARIA panel
prvhouse://family/[member_id]             → Member detail

NOTIFICATION TAPPING:
Each notification deep links to exact relevant screen
No navigating to find what was notified about
```

---

# A6. MODULE RELATIONSHIPS

## Dependency Map

```
CORE DATA (all modules read from):
  property_profile ←────────────────── all modules
  rooms ←──────────────────────────── inventory, smart_home, maintenance, security
  users/family ←───────────────────── permissions, notifications, activity_log

MODULE RELATIONSHIPS:

INVENTORY ──feeds──▶ MAINTENANCE
  (item warranty expires → maintenance task created)
  (item age milestone → predictive alert)
  (item recall → ARIA alert)

SMART HOME ──feeds──▶ ENERGY
  (device power draw → energy consumption data)
  (device anomaly → energy spike alert)

SMART HOME ──feeds──▶ SECURITY
  (motion sensors → security events)
  (door sensors → access log)
  (cameras → security feed)

SMART HOME ──feeds──▶ MAINTENANCE
  (device offline → maintenance alert)
  (device error code → diagnostic work order)

ENERGY ──feeds──▶ FINANCE
  (utility costs → expense transactions)
  (solar production → income if feed-in tariff)

MAINTENANCE ──feeds──▶ FINANCE
  (completed work orders → expense transactions)
  (contractor invoices → transactions)

MAINTENANCE ──feeds──▶ MARKETPLACE
  (work order needs contractor → job posted)
  (completed job → contractor rating)

PROJECTS ──feeds──▶ FINANCE
  (project expenses → transactions)
  (project phases → budget milestones)

FAMILY ──feeds──▶ SMART HOME
  (family member home → occupancy-based automation)
  (family member role → smart home access scope)

FAMILY ──feeds──▶ SECURITY
  (known family member → reduces false alerts)
  (access schedule → allowed unlock times)

FINANCE ──feeds──▶ ARIA
  (expense patterns → financial intelligence)
  (budget variance → proactive alerts)

ARIA ──orchestrates──▶ ALL MODULES
  (reads from all modules for context)
  (writes to: maintenance, smart_home, notifications, finance)
```

---

# A7. FEATURE HIERARCHY

## MVP (Version 1.0) — Launch

**Goal:** Prove core value proposition. Replace 4 apps with 1.

```
AUTH & ONBOARDING
✅ Email + password + magic link
✅ Apple + Google OAuth
✅ Passkeys
✅ TOTP 2FA
✅ 5-step onboarding
✅ 6 languages at launch

PROPERTY
✅ Unlimited properties
✅ Property profile (address, type, details, photos)
✅ Floor/room structure (manual)
✅ Document vault (upload, categorize, OCR)
✅ Property history timeline

INVENTORY (M-SCAN™ v1)
✅ Barcode + QR scan
✅ Manual item entry
✅ Room assignment
✅ Warranty tracking
✅ Receipt upload + OCR
✅ Recall database check

MAINTENANCE
✅ Task creation (manual)
✅ Calendar view
✅ Preventive schedule templates
✅ Basic work order management
✅ Contractor notes (manual)
✅ Photo documentation (before/after)

SMART HOME (Basic)
✅ Matter device integration
✅ Apple HomeKit bridge
✅ Google Home bridge
✅ Amazon Alexa bridge
✅ Device list + basic control
✅ Scenes (predefined)
✅ Basic automations (time/device triggers)

SECURITY (Basic)
✅ Camera integration (Ring, Nest, Arlo)
✅ Live view
✅ Event log
✅ Smart lock control
✅ Push notifications

ENERGY (Basic)
✅ Manual bill entry
✅ Utility cost tracking
✅ Smart meter API (where available)
✅ Basic consumption charts

FINANCE (Basic)
✅ Expense tracking
✅ Income tracking
✅ Insurance policy storage
✅ Basic P&L view

FAMILY (Basic)
✅ Invite members (all roles)
✅ Permission configuration
✅ Activity feed

ARIA (v1 — Conversational)
✅ Property Q&A
✅ Context-aware responses
✅ Basic morning briefing
✅ Document search
✅ Work order creation via ARIA

DASHBOARD
✅ Health Index™ (basic calculation)
✅ Energy widget
✅ Security status widget
✅ ARIA insight card
✅ Maintenance widget
✅ Living Property Background (LPBE v1 — basic)

MOBILE
✅ iOS 16+ (iPhone + iPad)
✅ Android 12+
✅ PWA (web, no install required)
```

**MVP Excluded (moved to V2):**
- Digital Twin 3D
- Marketplace (PRV-VERIFIED network needs runway)
- M-SCAN™ nameplate AI (requires ML model training)
- Predictive maintenance ML
- Full energy optimization AI
- LPBE full astronomical + weather engine
- Garden module full
- Projects full PM
- Apple Vision Pro

---

## V2 (Version 2.0) — Month 7–18

```
INTELLIGENCE UPGRADE
✅ ARIA v2 — proactive, behavioral learning
✅ Predictive maintenance (ML per appliance category)
✅ M-SCAN™ v2 — nameplate AI (fills Centriq void)
✅ HEALTH INDEX™ v2 — full scoring algorithm
✅ Energy AI optimizer (TOU scheduling, anomaly detection)
✅ Property valuation AI (AVM)
✅ LPBE v2 — full astronomical + weather + season system

MARKETPLACE LAUNCH
✅ PRV-VERIFIED contractor onboarding
✅ Job posting + matching algorithm
✅ In-app messaging
✅ PRV PAY (escrow)
✅ Rating system
✅ 3 initial markets (RO, NL, BE)

SMART HOME ADVANCED
✅ Advanced automation builder (visual flow)
✅ Home Assistant bridge (local)
✅ Energy-aware device scheduling
✅ Multi-property smart home

SECURITY ADVANCED
✅ AI motion detection zones
✅ Facial recognition (family members)
✅ Package detection
✅ Vacation mode

DIGITAL TWIN v1
✅ Floor plan import (2D → 3D basic)
✅ Photo-based room visualization
✅ IoT sensor overlay (basic)
✅ Room navigation

GARDEN MODULE
✅ Garden map
✅ Plant library + care schedules
✅ Irrigation integration (Rachio, Gardena)
✅ Pool chemistry tracking

FINANCE ADVANCED
✅ Insurance gap analysis
✅ Tax deductible tracking
✅ Multi-currency (EU portfolio owners)
✅ Airbnb income sync

FAMILY ADVANCED
✅ Elderly care module
✅ Teen safety features
✅ Guest digital welcome
✅ Family activity stream

ARIA v2 FEATURES
✅ Behavioral learning (90-day pattern engine)
✅ Proactive briefings (daily + event-triggered)
✅ Autonomous Level 2 (suggest + one-tap approve)
✅ Voice commands
✅ Cost optimization engine
```

---

## V3 (Version 3.0) — Month 19–36

```
SPATIAL COMPUTING
✅ Digital Twin v2 (LiDAR scan, full 3D, interactive objects)
✅ Apple Vision Pro app (visionOS native)
✅ AR maintenance guide
✅ Systems X-ray mode
✅ Time Machine
✅ Renovation scenario simulator

AUTONOMOUS ARIA v3
✅ Level 3–4 autonomous actions (pre-approved domains)
✅ Agentic maintenance (end-to-end contractor management)
✅ ARIA agentic swarm (specialized sub-agents)
✅ Energy trading desk (autonomous grid participation)

PLATFORM EXPANSION
✅ PRV HOUSE Enterprise (commercial properties, REITs)
✅ PRV API (developer access, webhooks)
✅ Property Passport™ v1 (blockchain-anchored history)
✅ Insurance Live Score (partner integrations)
✅ Smart City API (pilot cities: Amsterdam, Bucharest, Brussels)

MARKETPLACE EXPANSION
✅ 10+ European markets
✅ Drone inspection (DJI + Autel integration, pilot)
✅ AI architect assistant
✅ PRV HOUSE for Builders module

HARDWARE
✅ PRV HUB v1 (local bridge device, partnership with manufacturer)
✅ Matter hub integrated
✅ Local ARIA model option (privacy-first)
```

---

# A8. PERMISSION MATRIX VALIDATION

## Complete Role × Module Access Matrix

```
LEGEND: ✅ Full  ⚙️ Configurable  👁 View Only  ❌ No Access  🔒 Owner-only

MODULE               OWNER  PARTNER  ADULT   TEEN   CHILD  ELDERLY  TENANT  GUEST  SVC.PROV
──────────────────────────────────────────────────────────────────────────────────────────
Dashboard            ✅     ⚙️      ⚙️     👁     ❌     👁      👁     ❌    ❌
Property Profile     ✅     ⚙️      👁     ❌     ❌     ❌      ❌     ❌    ❌
Rooms               ✅     ✅       ⚙️     👁     ❌     ⚙️      Their  ❌    Job area
Documents — Legal   ✅     ⚙️      ❌     ❌     ❌     ❌      Their  ❌    ❌
Documents — Tech    ✅     ✅       ⚙️     ❌     ❌     ❌      ❌     ❌    Relevant
Documents — Manuals ✅     ✅       ✅     ❌     ❌     ❌      Their  ❌    Relevant
Digital Twin        ✅     ⚙️      ⚙️     ❌     ❌     ❌      ❌     ❌    ❌
──────────────────────────────────────────────────────────────────────────────────────────
Inventory — View    ✅     ✅       ✅     ❌     ❌     ⚙️      Their  ❌    Relevant
Inventory — Edit    ✅     ✅       ❌     ❌     ❌     ❌      ❌     ❌    ❌
Warranties          ✅     ✅       ⚙️     ❌     ❌     ❌      Their  ❌    ❌
──────────────────────────────────────────────────────────────────────────────────────────
Maintenance — View  ✅     ✅       ⚙️     ❌     ❌     ❌      Their  ❌    Their jobs
Maintenance — Create✅     ✅       ⚙️     ❌     ❌     ❌      Their  ❌    ❌
Maintenance — Assign✅     ⚙️      ❌     ❌     ❌     ❌      ❌     ❌    ❌
──────────────────────────────────────────────────────────────────────────────────────────
Smart Home — All    ✅     ⚙️      ⚙️     ⚙️    ❌     ⚙️      Their  Limited Their
Smart Home — Shared ✅     ✅       ⚙️     ⚙️    ❌     ✅      Their  Limited ❌
Smart Home — Own    ✅     ✅       ✅     ✅    ❌     ✅      ✅     ❌    ❌
Automations — View  ✅     ✅       ❌     ❌    ❌     ❌      ❌     ❌    ❌
Automations — Edit  ✅     ⚙️      ❌     ❌    ❌     ❌      ❌     ❌    ❌
──────────────────────────────────────────────────────────────────────────────────────────
Security — Cameras  ✅     ⚙️      ⚙️     ❌    ❌     ⚙️      Their  ❌    ❌
Security — Events   ✅     ✅       ⚙️     ❌    ❌     ⚙️      Their  ❌    ❌
Security — Alarm    ✅     ✅       ⚙️     ❌    ❌     ⚙️      ❌     ❌    ❌
Access — All doors  ✅     ⚙️      ⚙️     ⚙️    ❌     ⚙️      Their  Their  Their
Access — Own area   ✅     ✅       ✅     ✅    Limited✅      ✅     ✅    ✅
Access Codes — Create✅    ⚙️      ❌     ❌    ❌     ❌      ❌     ❌    ❌
──────────────────────────────────────────────────────────────────────────────────────────
Energy — View       ✅     ✅       ⚙️     ❌    ❌     ❌      Their  ❌    ❌
Energy — Control    ✅     ✅       ❌     ❌    ❌     ❌      ❌     ❌    ❌
Energy — Settings   ✅     ⚙️      ❌     ❌    ❌     ❌      ❌     ❌    ❌
──────────────────────────────────────────────────────────────────────────────────────────
Finance — View      ✅     ✅       ❌     ❌    ❌     ❌      Their  ❌    ❌
Finance — Edit      ✅     ⚙️      ❌     ❌    ❌     ❌      ❌     ❌    ❌
Insurance           ✅     ✅       ❌     ❌    ❌     ❌      ❌     ❌    ❌
Valuation           ✅     ✅       ❌     ❌    ❌     ❌      ❌     ❌    ❌
──────────────────────────────────────────────────────────────────────────────────────────
Garden — View       ✅     ✅       ✅     ✅    ❌     ✅      ❌     ❌    Gardener
Garden — Control    ✅     ✅       ⚙️     ❌    ❌     ❌      ❌     ❌    Gardener
──────────────────────────────────────────────────────────────────────────────────────────
Projects — View     ✅     ✅       ⚙️     ❌    ❌     ❌      ❌     ❌    Their project
Projects — Edit     ✅     ✅       ❌     ❌    ❌     ❌      ❌     ❌    ❌
──────────────────────────────────────────────────────────────────────────────────────────
Marketplace — View  ✅     ✅       ⚙️     ❌    ❌     ❌      ❌     ❌    ❌
Marketplace — Post  ✅     ✅       ❌     ❌    ❌     ❌      ⚙️     ❌    ❌
PRV PAY             ✅     ⚙️      ❌     ❌    ❌     ❌      Their  ❌    Receive
──────────────────────────────────────────────────────────────────────────────────────────
Family — View       ✅     ✅       ❌     ❌    ❌     ❌      ❌     ❌    ❌
Family — Manage     ✅     ⚙️      ❌     ❌    ❌     ❌      ❌     ❌    ❌
──────────────────────────────────────────────────────────────────────────────────────────
ARIA — Full         ✅     ⚙️      ⚙️     ❌    ❌     ⚙️      Limited❌    ❌
ARIA — Basic        ✅     ✅       ✅     ❌    ❌     ✅      ✅     ❌    ❌
──────────────────────────────────────────────────────────────────────────────────────────
Settings — Account  ✅     Own      Own    Own   ❌     Own     Own    ❌    ❌
Settings — Property 🔒    ❌       ❌     ❌    ❌     ❌      ❌     ❌    ❌
Settings — Billing  🔒    ❌       ❌     ❌    ❌     ❌      ❌     ❌    ❌
```

### Permission Inheritance Rules

```
RULE 1 — Least privilege default:
All new members start with minimum permissions for their role.
Owner must explicitly grant additional access.

RULE 2 — Scope inheritance:
Room access → item access in that room → device access in that room
No backdoors: access to child scope requires access to parent scope.

RULE 3 — Time-bound access:
All non-owner access can be time-limited.
Expired access: immediate revocation, user sees "access expired" on login.

RULE 4 — Tenant isolation:
Tenant accounts are completely isolated across properties.
Tenant A in property X cannot see property Y, even if same owner.

RULE 5 — Service Provider scope:
Automatically scoped to: assigned work order + relevant items + access code window.
Access revoked: work order marked complete + 2 hours buffer.

RULE 6 — Emergency override:
Owner can emergency-revoke all non-owner access from "Panic" in Security settings.
All codes invalidated, all sessions terminated, all doors locked.
```

---

# A9. MODULE SPECIFICATIONS

---

## MODULE 1 — HOME DASHBOARD

### Goals
1. Give the owner a complete, glanceable state of their property in under 5 seconds
2. Surface the most important action needed today
3. Be the entry point to all modules without feeling like a menu
4. Demonstrate ARIA intelligence daily

### User Stories

```
US-DASH-001  As an Owner, I want to see my property's overall health at a glance
             so I can know if everything is fine without opening each module.
             
US-DASH-002  As an Owner, I want to see today's energy consumption and cost
             so I can track my spending in real time.
             
US-DASH-003  As an Owner, I want to see my property's security status
             so I can confirm my home is protected when I'm away.
             
US-DASH-004  As a Partner, I want to see the family presence status
             so I know who is home without calling anyone.
             
US-DASH-005  As an Owner, I want ARIA to highlight the one most important
             thing I should do today for my property.
             
US-DASH-006  As an Owner, I want to control the most-used smart devices
             from the dashboard without entering the Smart Home module.
             
US-DASH-007  As a multi-property Owner, I want to switch between properties
             and see each property's dashboard separately.
```

### Functional Requirements

```
FR-DASH-001  Dashboard displays Property Hero widget with property photo,
             name, address, and HEALTH INDEX™ score.
             
FR-DASH-002  Health Index score updates daily, with last-updated timestamp.
             Score ring shows color (green/amber/red) and numeric value.
             
FR-DASH-003  Energy widget shows: today's consumption (kWh), today's cost,
             comparison vs. same day last week (+/- %), mini sparkline.
             
FR-DASH-004  Security widget shows: armed/disarmed status, last event time,
             camera count online/offline. Tap → Security module.
             
FR-DASH-005  ARIA Insight card shows 1 daily insight. Card can be:
             dismissed (don't show this type again today),
             acted upon (inline action button),
             expanded (full ARIA context).
             
FR-DASH-006  Maintenance widget shows: number of overdue tasks (red badge),
             next scheduled task (date + name), count of upcoming 30 days.
             
FR-DASH-007  Smart Home quick controls: shows 4–6 most-used devices
             (AI-determined from interaction history). Toggle visible state.
             
FR-DASH-008  Widget grid is fully customizable (add/remove/reorder).
             Settings → Display → Edit Dashboard.
             
FR-DASH-009  Dashboard refreshes data on app foreground (max 5-min cache).
             Real-time updates for security events and critical ARIA alerts.
             
FR-DASH-010  Property switcher: tap property name → sheet with list of owned
             properties, each showing mini health score + last alert.
```

### Non-Functional Requirements

```
NFR-DASH-001  Dashboard must load primary content within 1.5 seconds
              on 4G connection (LCP < 1.5s).
              
NFR-DASH-002  Dashboard must be functional offline (cached data, stale label).

NFR-DASH-003  LPBE background must not impact app performance:
              iOS: Metal, 120fps capable, < 8% battery drain per hour
              Android: Vulkan / OpenGL ES 3.2, 60fps minimum
              Web: WebGL 2.0, requestAnimationFrame throttled
              Reduced motion: static image if device reports prefers-reduced-motion
              
NFR-DASH-004  Dashboard must render correctly on:
              iPhone SE (375pt) to iPhone 16 Pro Max (430pt)
              All iPad sizes (768pt to 1366pt)
              Web (1024pt to 2560pt)
              
NFR-DASH-005  Widget data fetching must be parallelized (all widgets load
              concurrently, not sequentially). Individual widget failure
              must not block other widgets.
```

### Edge Cases

```
EC-DASH-001  No properties added → Onboarding CTA replaces dashboard.

EC-DASH-002  Health Index cannot be calculated (insufficient data) →
             Show "Building your score..." with spinner + explanation.
             Score builds progressively as modules are populated.

EC-DASH-003  All smart devices offline → energy/security widgets show
             "Devices offline" state with last known time + troubleshoot link.

EC-DASH-004  Multiple critical alerts → Show alert banner at top
             (scrollable if > 3 alerts). Dashboard dimmed behind banner.

EC-DASH-005  ARIA insight unavailable (API error) → Card hides gracefully.
             No error state shown to user for ARIA — it simply doesn't appear.

EC-DASH-006  First time dashboard loads (no history) → Show "Getting to know
             your home..." state with setup progress checklist as primary widget.
             
EC-DASH-007  User has multiple properties and selects wrong one →
             Property switcher always visible at top, 1-tap to switch.
```

### Success Metrics

```
SM-DASH-001  Time to first meaningful paint (dashboard data visible): < 1.5s
SM-DASH-002  Daily active users / total users (engagement ratio): > 60%
SM-DASH-003  Dashboard session duration (how long user spends): 45–120 seconds
             (too short = not enough value; too long = confusion)
SM-DASH-004  ARIA insight card CTR (acted upon / shown): > 25%
SM-DASH-005  Widget engagement: at least 3 widgets tapped per session
SM-DASH-006  Property switch usage: < 15% of sessions (multi-property owners
             should find their default property relevant)
SM-DASH-007  LPBE enabled: > 80% of users keep it on (measures perceived value)
```

---

## MODULE 2 — PROPERTY MANAGEMENT

### Goals
1. Create the complete, authoritative digital record of the property
2. Replace physical document folders, architect plans, and property history email threads
3. Enable confident decision-making about renovation, sale, and maintenance

### User Stories

```
US-PROP-001  As an Owner, I want to store all property documents in one place
             so I never need to search through email or physical folders again.
             
US-PROP-002  As an Owner, I want to add all rooms to my property
             so I can associate inventory, devices, and maintenance with specific rooms.
             
US-PROP-003  As an Owner, I want to see the complete history of work done
             on my property so I can provide this to buyers or insurers.
             
US-PROP-004  As an Owner, I want ARIA to warn me when any document is
             about to expire so I never miss a renewal.
             
US-PROP-005  As an Owner, I want to upload architectural plans and have
             them available to any contractor I work with.
             
US-PROP-006  As a Portfolio Owner, I want to add multiple property types
             and manage them all from one account.
```

### Functional Requirements

```
FR-PROP-001  Property supports all types: House, Villa, Apartment, Vacation Home,
             Land, Commercial, Industrial. Type determines available features.
             
FR-PROP-002  Property profile fields: name, type, address (with GPS auto-fill),
             area (m² / sq ft), year built, floors, rooms, construction details.
             
FR-PROP-003  Room creation: name, type (from list + custom), floor, area,
             photos (unlimited), notes. Room types: Bedroom, Living Room,
             Kitchen, Bathroom, Study, Garage, Storage, Garden + custom.
             
FR-PROP-004  Document vault supports: PDF, DOCX, XLSX, JPG, PNG, HEIC.
             Max file size per file: 50MB. Storage per tier:
             Free: 5GB, Essential: 25GB, Premium: 100GB, Portfolio: 500GB.
             
FR-PROP-005  OCR processing: on upload, system extracts text from PDFs/images.
             Extracted text is searchable. Key fields auto-detected:
             expiry dates, amounts, addresses, names.
             
FR-PROP-006  Document expiry tracking: for each document, system checks for
             detected expiry date. Alerts sent: 90/60/30/14/7 days before expiry.
             
FR-PROP-007  Property history timeline: chronological list of all events
             (maintenance, documents added, projects, transactions).
             Filterable by type. Each event links to originating record.
             
FR-PROP-008  Co-owner management: Owner can add co-owners (OWNER role)
             who have equal access. Requires acceptance via invite.
             
FR-PROP-009  Property photos: unlimited photos, date-stamped, room-tagged,
             organized as property timeline gallery.
             
FR-PROP-010  Share property brief: Owner can generate a read-only share link
             for property profile (for contractor briefings, estate agents).
             Configurable: what data to include. Expires: 24h / 7 days / 30 days.
```

### Non-Functional Requirements

```
NFR-PROP-001  Document upload: background upload (user can leave screen).
              Progress indicator in notification center during upload.
              
NFR-PROP-002  OCR processing time: < 30 seconds for standard PDF (< 10 pages).
              Async: user gets result notification when done.
              
NFR-PROP-003  Document search: full text search results in < 500ms for
              portfolio up to 500 documents.
              
NFR-PROP-004  Document storage is encrypted at rest (AES-256) and in transit
              (TLS 1.3). Documents are accessible only by authorized family members.
```

### Edge Cases

```
EC-PROP-001  Address not found in autocomplete (rural) → manual GPS pin
             on satellite map. Coordinate saved as property location.
             
EC-PROP-002  Document too large (> 50MB) → prompt to compress or split.
             Show estimated compressed size.
             
EC-PROP-003  Duplicate document detected (same filename, same size) →
             "This document may already exist. Upload anyway?"
             
EC-PROP-004  OCR fails (handwritten, poor scan quality) → document saved
             without extracted text. Search note: "Text extraction unavailable."
             Manual description field suggested.
             
EC-PROP-005  User has > 50 rooms (commercial property) → room list paginates.
             Floor filter required for large floor plans.
             
EC-PROP-006  Property transferred but documents remain → documents stay with
             property (transfer to new owner unless explicitly excluded).
```

### Success Metrics

```
SM-PROP-001  Documents uploaded per property within first 30 days: > 5
SM-PROP-002  Rooms created per property: > 4 (reflects real engagement)
SM-PROP-003  Document vault search queries per week: > 2 per active user
SM-PROP-004  Expiry alerts opened vs. received: > 70%
SM-PROP-005  Property history events logged in first 6 months: > 10
```

---

## MODULE 3 — INVENTORY (M-SCAN™)

### Goals
1. Create the world's most complete home inventory system, filling the void left by Centriq (shut down Jan 2026)
2. Make item addition so effortless it becomes habitual
3. Turn inventory data into financial, maintenance, and insurance value

### User Stories

```
US-INV-001  As an Owner, I want to scan any appliance barcode or nameplate
             and have ARIA populate all details automatically
             so I don't have to search for manuals manually.
             
US-INV-002  As an Owner, I want to see all warranties that are expiring
             in the next 90 days so I can make claims before it's too late.
             
US-INV-003  As an Owner, I want to know the total replacement value of
             my contents for insurance purposes.
             
US-INV-004  As an Owner, I want to be notified immediately if any product
             I own has a safety recall.
             
US-INV-005  As an Owner, I want to find the manual for any appliance
             instantly without searching online.
             
US-INV-006  As an Owner, I want to log the purchase price and track
             the current value of my items for insurance and accounting.
```

### Functional Requirements

```
FR-INV-001  Barcode scan: device camera reads EAN-13, EAN-8, UPC-A, QR codes.
            Product database lookup (1B+ products). Returns: brand, model,
            category, typical warranty period, manual URL.
            
FR-INV-002  M-SCAN™ nameplate recognition: camera photo of appliance nameplate
            → AI extracts: brand, model number, serial number, manufacturing date.
            Confidence score displayed. Fields pre-populated, user corrects any errors.
            
FR-INV-003  Receipt OCR: upload receipt photo → AI extracts: product name,
            brand, model (if present), purchase price, purchase date, store.
            
FR-INV-004  Item fields: name, brand, model, serial number, barcode,
            category, subcategory, room, condition (5 levels),
            purchase price, purchase date, purchase store/location,
            current estimated value, insurance value, warranty start/end,
            warranty type (manufacturer/extended/none), photos, notes.
            
FR-INV-005  Warranty tracking: list view sortable by expiry date.
            Color coding: green (> 90 days), amber (< 90 days), red (< 30 days),
            grey (expired). Notification at 90/30/14/7 days before expiry.
            
FR-INV-006  Recall database: daily check against CPSC (US), RAPEX (EU),
            and manufacturer recall databases. Immediate push notification
            if owned item has active recall. Recall details + action link.
            
FR-INV-007  Value tracking: total inventory value (purchase price sum),
            current estimated value (depreciation model per category),
            insurance recommendation (current replacement value).
            
FR-INV-008  Manual access: tap "View Manual" on any item → opens PDF manual
            in-app viewer. Manual stored in property document vault.
            Offline access: cached for last 20 viewed manuals.
            
FR-INV-009  Item maintenance link: each item links to its maintenance history.
            ARIA-generated maintenance recommendations visible per item.
            
FR-INV-010  Item categories: Appliances (kitchen, laundry, HVAC, water),
            Furniture, Electronics (AV, computing, lighting), Systems & Equipment,
            Vehicles (in garage), Art & Collectibles, Outdoor, Tools & Equipment,
            Custom (user-defined).
            
FR-INV-011  Bulk operations: select multiple items → move to room, export,
            or delete. CSV export for insurance documentation.
            
FR-INV-012  Insurance export: generate formatted inventory PDF report
            (item, serial, purchase value, current value, photos).
            Used for insurance claims or policy review.
```

### Non-Functional Requirements

```
NFR-INV-001  Barcode scan to result: < 1 second on device with camera.
NFR-INV-002  M-SCAN™ nameplate processing: < 8 seconds (device + AI roundtrip).
NFR-INV-003  Product database lookup: < 500ms API response time (P95).
NFR-INV-004  Inventory loads (list of all items): < 1 second for up to 500 items.
NFR-INV-005  Camera must work in low-light environments (nameplate in dark cupboard).
             Torch (flashlight) available in scan view.
```

### Edge Cases

```
EC-INV-001  Product not in database → Manual entry form, offered as
            "Help improve PRV HOUSE" option to submit to database.
            
EC-INV-002  Multiple items with same barcode (e.g., pack of 6) →
            "How many of this item?" quantity field.
            
EC-INV-003  Item worth > €10,000 → ARIA flags: "High-value item.
            Consider adding to insurance policy. View insurance module."
            
EC-INV-004  Receipt scan fails (bad photo, handwritten) → manual entry
            with hint: "Try better lighting or take a cleaner photo."
            
EC-INV-005  Item moved to different property (e.g., family moves) →
            Move item function: property transfer with full history preserved.
            
EC-INV-006  Recall found on item at scan time → block normal save flow,
            show SAFETY ALERT screen first. Must acknowledge before saving.
```

### Success Metrics

```
SM-INV-001  Items added per property in first 30 days: > 10
SM-INV-002  Scan method usage (% via scanner vs. manual): > 60% scan
SM-INV-003  Warranty alerts opened: > 75%
SM-INV-004  Recall notifications read: > 90% (safety-critical, must be very high)
SM-INV-005  Insurance export generated: > 20% of active users in first 6 months
SM-INV-006  Average items per property at 6 months: > 25
```

---

## MODULE 4 — MAINTENANCE

### Goals
1. Transform reactive, emergency-driven maintenance into predictive, scheduled care
2. Create the complete documented history of all work done on the property
3. Make finding and managing contractors effortless

### User Stories

```
US-MAINT-001  As an Owner, I want to be reminded about seasonal maintenance
              tasks automatically so I don't forget important annual items.
              
US-MAINT-002  As an Owner, I want ARIA to predict when my appliances are
              likely to fail so I can service them before they break down.
              
US-MAINT-003  As an Owner, I want to document every maintenance job with
              before/after photos so I have a full property service history.
              
US-MAINT-004  As a Property Manager, I want to assign work orders to
              contractors and track their progress without calling them.
              
US-MAINT-005  As an Owner, I want to see all overdue maintenance tasks
              in one list so I can prioritize my to-do list.
              
US-MAINT-006  As a Tenant, I want to report a maintenance issue with a photo
              and have the owner notified immediately.
```

### Functional Requirements

```
FR-MAINT-001  Task creation: title, description (ARIA pre-fill available),
              property, room, linked item (from inventory), category, priority
              (CRITICAL/HIGH/MEDIUM/LOW), due date, recurrence rule (iCal RRULE).
              
FR-MAINT-002  Pre-loaded maintenance schedule: 50+ standard tasks auto-created
              for property type with configurable frequency. Tasks include:
              HVAC filter, boiler service, gutter clean, roof check, smoke
              detector test, electrical inspection, etc.
              
FR-MAINT-003  Calendar view: monthly view with task density heatmap.
              Day view: full list for selected date. Week view available.
              Tap task → quick action (complete, reschedule, assign contractor).
              
FR-MAINT-004  Work order management: create from task (pre-fills title/description),
              add estimated cost, photos (before), assign from Marketplace,
              or link to existing contractor.
              
FR-MAINT-005  Predictive maintenance (V2): ARIA generates predictions based on
              appliance age, historical maintenance data, IoT anomalies.
              Predictions shown in dashboard and maintenance module with
              probability score and recommended action.
              
FR-MAINT-006  Completion documentation: photo upload (min 1 required for
              CRITICAL/HIGH tasks). Sign-off by owner or property manager.
              Cost recorded. Invoice upload optional.
              
FR-MAINT-007  Tenant maintenance requests: tenant submits request (title,
              description, category, 1–3 photos). Owner/PM notified.
              Request auto-converts to work order (owner approves).
              
FR-MAINT-008  Maintenance history: filterable by: property, room, item,
              category, date range, contractor. Export to PDF/CSV.
              
FR-MAINT-009  Recurrence engine: handles RRULE patterns. Monthly/quarterly/
              annual/seasonal tasks auto-regenerated on completion.
              Skipped tasks marked and rescheduled.
              
FR-MAINT-010  Notification system: push + in-app for:
              - Task due today
              - Task overdue (daily reminder until done or snoozed)
              - Contractor arriving in 2 hours
              - Predictive alert (new ARIA prediction)
              - Task completed by contractor (review prompt)
```

### Non-Functional Requirements

```
NFR-MAINT-001  Maintenance module loads (task list): < 1 second.
NFR-MAINT-002  Recurrence engine runs daily at 00:01 UTC (property timezone).
               Tasks must appear on due date, not retroactively.
NFR-MAINT-003  Photo uploads: compressed to < 2MB per photo before upload.
               Original resolution stored; compressed version served in lists.
NFR-MAINT-004  Calendar handles up to 200 tasks per month without
               performance degradation.
```

### Edge Cases

```
EC-MAINT-001  Recurring task marked complete early → next occurrence
              scheduled from completion date, not original due date.
              
EC-MAINT-002  Task overdue > 90 days → ARIA alert: "This critical task has been
              overdue for [N] days. This may affect your property Health Score."
              
EC-MAINT-003  Conflicting tasks on same day (e.g., both contractors at once) →
              warning: "You have 2 contractors scheduled simultaneously."
              
EC-MAINT-004  Contractor doesn't complete within estimated time →
              notification at estimated_time + 2 hours: "Job running long.
              Check in with contractor?"
              
EC-MAINT-005  Multi-property: ensure task is assigned to correct property.
              Notifications always include property name.
              
EC-MAINT-006  Bulk task creation (e.g., new property setup) → import from
              template or previous property. "Apply standard annual schedule?"
```

### Success Metrics

```
SM-MAINT-001  Tasks created per property per month: > 3
SM-MAINT-002  Tasks completed on time (vs. overdue): > 70%
SM-MAINT-003  Photo documentation rate (tasks with photos): > 50%
SM-MAINT-004  Predictive alert action rate (acted on vs. dismissed): > 40%
SM-MAINT-005  Average time from task created to completion: < 14 days (MEDIUM)
              < 3 days (HIGH), < 24h (CRITICAL)
SM-MAINT-006  Maintenance cost tracked per property per year: growing over time
              (indicates honest use, not gaming)
```

---

## MODULE 5 — SMART HOME

### Goals
1. Be the single control layer for all smart home devices, regardless of brand
2. Make automation accessible to non-technical users
3. Connect smart home intelligence to property context (maintenance, energy, security)

### User Stories

```
US-SMART-001  As an Owner, I want to control all my smart devices from
              one screen regardless of whether they are HomeKit, Google, or Alexa.
              
US-SMART-002  As an Owner, I want to create "Good Morning" scene that runs
              all my preferred morning automations with one tap.
              
US-SMART-003  As an Owner, I want automations to trigger based on my family's
              location (home/away) not just a fixed time.
              
US-SMART-004  As an Adult Child, I want to control the lights in my bedroom
              from my phone without being able to affect the rest of the house.
              
US-SMART-005  As an Owner, I want ARIA to suggest automations based on
              my usage patterns.
```

### Functional Requirements

```
FR-SMART-001  Platform bridges: Matter (primary), Apple HomeKit, Google Home,
              Amazon Alexa, Home Assistant, Samsung SmartThings.
              Device discovery runs automatically on bridge addition.
              
FR-SMART-002  Device control: all supported device types (see Constitution V2,
              Section 5.2). State updates reflected in UI < 500ms.
              
FR-SMART-003  Scene system: create named scenes with multiple device states.
              Scenes invocable via: tap, ARIA command, automation, widget,
              voice assistant (Siri shortcut / Google Assistant routine).
              
FR-SMART-004  Automation builder (MVP — simplified):
              Single trigger + conditions + actions.
              Triggers: time (specific/sunrise/sunset), geofence, device state.
              Conditions: time range, device state, family member presence.
              Actions: device state, scene, notification.
              
FR-SMART-005  Automation builder (V2 — visual flow):
              Multi-trigger, multi-condition, multi-action.
              Visual if-then-else logic builder (inspired by Shortcuts / Homey).
              
FR-SMART-006  Room-based view: devices grouped by room (matching property room
              structure). Rooms show all device states and aggregate status.
              
FR-SMART-007  Device detail: name, room, brand, model, firmware version,
              online status, last event, full control panel, linked automations.
              
FR-SMART-008  Energy monitoring: per-device power consumption (if device
              supports or has smart plug). Feeds Energy module.
              
FR-SMART-009  Offline detection: device offline > 15 minutes → notification
              (configurable: per-device sensitivity). Security cameras: 5 minutes.
```

### Non-Functional Requirements

```
NFR-SMART-001  Device state update: local network < 200ms, cloud < 500ms.
NFR-SMART-002  Smart home bridge must not affect app performance if bridge offline.
               Offline devices shown clearly; other devices unaffected.
NFR-SMART-003  Automation reliability: automations must fire within 60 seconds
               of trigger time. Late fire logged and surfaced to owner.
NFR-SMART-004  Device list performance: up to 200 devices, scroll smooth (60fps).
```

### Edge Cases

```
EC-SMART-001  Device renamed in native app (e.g., renamed in Apple Home) →
              PRV HOUSE detects name change on next sync, prompts: "Device
              name changed. Update in PRV HOUSE?"
              
EC-SMART-002  Same device accessible via multiple bridges (e.g., device in
              both Apple Home AND Alexa) → de-duplicate, show one device,
              prefer local bridge.
              
EC-SMART-003  Automation conflicts (two automations targeting same device
              simultaneously) → last-write-wins + warning to user about conflict.
              
EC-SMART-004  Bridge internet outage → local devices continue to work
              (local bridge mode). Notification: "Smart home running locally.
              Remote access unavailable."
              
EC-SMART-005  New family member added without smart home access →
              their presence does not trigger home/away automations.
              Owner must explicitly add them to geofence triggers.
```

### Success Metrics

```
SM-SMART-001  Devices connected per property (at 30 days): > 5
SM-SMART-002  Scene usage (activations per week): > 7 (≈ 1/day)
SM-SMART-003  Automation creation rate: > 3 automations per active smart home user
SM-SMART-004  Device control latency (P95): < 500ms
SM-SMART-005  Platform bridge connection success rate: > 95%
```

---

## MODULE 6 — SECURITY

*(Abbreviated — full spec follows same structure)*

### Goals
1. Unify all security devices into a single monitoring center
2. Reduce alert fatigue through AI-powered context-aware notifications
3. Enable confident remote security management

### Key Requirements

```
FR-SEC-001  Multi-camera live view: up to 16 simultaneous streams.
FR-SEC-002  AI event classification: person/vehicle/animal/package detection.
FR-SEC-003  Access codes: create/revoke time-limited codes. Associate with
            person name and valid time window.
FR-SEC-004  Alarm system: arm (full/perimeter/night mode)/disarm.
            Alarm triggered → all family members notified simultaneously.
FR-SEC-005  Event log: filterable by type, device, date. 30-second clip
            downloadable per event.
FR-SEC-006  Vacation mode: enhanced sensitivity, daily summary, 
            reduced false alarm suppression.
```

### Success Metrics

```
SM-SEC-001  Camera uptime: > 99.5% (critical — users depend on this)
SM-SEC-002  False alarm rate: < 5% of total motion events (AI quality)
SM-SEC-003  Alert response time (user opens notification): median < 3 minutes
SM-SEC-004  Access code usage: > 50% of users with contractor jobs use app codes
            vs. physical key handover
```

---

## MODULE 7 — ENERGY

*(Abbreviated)*

### Goals
1. Make energy costs visible, understandable, and actionable
2. Reduce homeowner energy spend through AI optimization
3. Support the full energy transition (solar + battery + EV)

### Key Requirements

```
FR-ENERGY-001  Real-time energy flow: Sankey diagram updating every 30s.
FR-ENERGY-002  Smart meter integration: country-specific APIs (UK SMETS2,
               NL P1 port, BE Fluvius, FR Linky).
FR-ENERGY-003  Bill scanner: photograph utility bill → OCR extracts
               period, consumption, cost → auto-logged as transaction.
FR-ENERGY-004  Solar inverter integration: Fronius, SolarEdge, Enphase, SMA.
FR-ENERGY-005  EV charger integration: Wallbox, Easee, Zaptec, OCPP.
FR-ENERGY-006  TOU optimization: AI schedules flexible loads for off-peak.
FR-ENERGY-007  Anomaly detection: spike > 40% above 30-day baseline →
               ARIA alert with probable cause.
```

---

## MODULE 8 — ARIA (AI Property Brain)

*(Abbreviated — core architecture in Constitution V2 Chapter 6)*

### Goals
1. Be the most knowledgeable entity about the user's property
2. Proactively surface insights that prevent problems and reduce costs
3. Make property management feel effortless for the owner

### Key Requirements

```
FR-ARIA-001  Conversational interface: natural language, multi-turn,
             context-aware (current property, history, IoT state).
FR-ARIA-002  Knowledge graph: all property entities accessible to ARIA.
             Query: "What is the total maintenance cost for the boiler?"
             → traverses transactions + maintenance tasks.
FR-ARIA-003  Proactive insights: generated daily per property.
             Minimum 1 insight/day. Maximum 5 insights/day (not overwhelming).
FR-ARIA-004  Morning briefing: delivered at user's configurable time (default 7:30).
             Format: home status + weather impact + today's schedule + 1 highlight.
FR-ARIA-005  Autonomy levels 1–4: user configurable per domain. All autonomous
             actions logged. All have undo within 30 minutes.
FR-ARIA-006  Privacy mode: user can disable cloud AI, use local model only
             (V2 feature — requires PRV Hub hardware or on-device model).
```

### Non-Functional Requirements

```
NFR-ARIA-001  Conversational response time: < 3 seconds (P95) for standard queries.
              Complex queries (full property history analysis): < 8 seconds with
              "This is taking a moment..." message after 3s.
NFR-ARIA-002  Morning briefing delivery: within 5 minutes of configured time.
              If user asleep (no app activity), notification waits until
              first app open.
NFR-ARIA-003  ARIA must handle gracefully: no internet, API timeout,
              partial property data. Degrades gracefully to "cached knowledge."
```

---

## MODULE 9 — MARKETPLACE

*(Abbreviated)*

### Goals
1. Build a high-trust contractor network where quality is guaranteed
2. Make hiring a professional effortless — from need to booked in under 5 minutes
3. Generate revenue through commission while protecting both sides

### Key Requirements

```
FR-MKTPL-001  PRV-VERIFIED onboarding: identity check, insurance check,
              license check, background check (partner), minimum job history.
FR-MKTPL-002  Smart matching: ARIA generates job brief from property context.
              Top 3 contractors shown. Exclusive match (no lead resell).
FR-MKTPL-003  In-app messaging: no WhatsApp needed. All job communication
              in PRV HOUSE (logged, searchable).
FR-MKTPL-004  PRV PAY: escrow model. Payment released on owner approval.
              Dispute resolution: 7-day window, PRV mediates.
FR-MKTPL-005  Rating system: bilateral (owner rates contractor + contractor
              rates owner). Both visible to future parties.
FR-MKTPL-006  Launch markets (V2): Romania, Netherlands, Belgium.
              Expanding to: France, Italy, Poland (V3).
```

---

## MODULE 10 — FINANCE

*(Abbreviated)*

### Goals
1. Replace the spreadsheet as the financial tool for property owners
2. Make the true cost of ownership visible and manageable
3. Support tax compliance and insurance coverage

### Key Requirements

```
FR-FIN-001  Property P&L: income vs. expenses per property, monthly/annual.
FR-FIN-002  Transaction categorization: AI auto-categorizes from description.
            Manual override always available. Custom categories.
FR-FIN-003  Insurance vault: policy storage, expiry tracking, coverage summary.
            ARIA calculates coverage gap vs. inventory value.
FR-FIN-004  Valuation AI: AVM (Automated Valuation Model) updated monthly.
            Comparable sales analysis. Equity tracker (value minus mortgage).
FR-FIN-005  Tax support: flag transactions as deductible. Annual summary
            exportable for accountant/tax return.
FR-FIN-006  Multi-currency: all financial data in one currency (owner-set)
            with conversion for multi-country portfolios.
```

---

## MODULE 11 — FAMILY

*(Core specification in A8 Permission Matrix and Constitution V2 Chapter 3)*

### Key Requirements

```
FR-FAM-001  Family map: property floor plan (simplified) with member presence.
            Occupancy sensor data. Privacy: shows area, not exact location.
FR-FAM-002  Elderly care: daily check-in system, medication reminders,
            activity pattern alerts, fall detection integration.
FR-FAM-003  Children safety: pool gate alert, window sensor alert,
            visitor alert when child home alone.
FR-FAM-004  Guest digital welcome: auto-generated guidebook, time-limited
            access code, simplified smart home for guest area only.
FR-FAM-005  Activity feed: family-visible log of home events.
            Each member controls their own visibility.
```

---

## MODULE 12 — GARDEN

*(Abbreviated)*

### Key Requirements

```
FR-GARDEN-001  Garden map: draw zones on satellite map (polygon draw tool).
               Label each zone (lawn, beds, pool, etc.).
FR-GARDEN-002  Plant library: 100,000+ species. Care calendar per plant.
               Photo-based plant identification (ML model).
FR-GARDEN-003  Smart irrigation: Rachio, Gardena, Hunter integration.
               Weather-adjusted: skip if rain forecast > 5mm in 24h.
FR-GARDEN-004  Pool chemistry: log pH, chlorine, alkalinity. ARIA alerts
               when values out of range. Dosing calculator.
FR-GARDEN-005  Seasonal guide: ARIA generates seasonal garden to-do list
               based on location + plant types in user's garden.
```

---

*End of Phase A — Product Blueprint*

**Document status:** Complete v1.0  
**Next:** Phase B — Glass OS Master Design
