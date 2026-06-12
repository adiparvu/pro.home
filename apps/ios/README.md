# PRV House — iOS App

Native SwiftUI app for PRV House property management.

## Setup

### Requirements
- Xcode 15.4+
- iOS 17.0+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Generate Xcode project

```bash
brew install xcodegen
cd apps/ios
xcodegen generate
open PRVHouse.xcodeproj
```

### First run
- Select your team in Signing & Capabilities
- Build & Run on simulator or device

## Architecture

```
Sources/
├── App/              # Entry point, tab bar
├── Features/
│   ├── Auth/         # Login screen
│   ├── Dashboard/    # Home with health score & tasks
│   ├── Tasks/        # Task management
│   ├── Analytics/    # Occupancy, yield, forecast charts
│   ├── ARIA/         # AI assistant chat
│   └── Settings/     # App settings
├── Components/       # GlassCard, PageHeader, IconBadge
└── Services/         # Supabase client, AuthService
```
