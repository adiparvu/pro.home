# PRV HOUSE — Mobile App Setup

Capacitor wraps the Next.js web app in a native iOS/Android shell.
The app is hosted on Vercel; Capacitor opens it via WKWebView (iOS) / WebView (Android).

## Prerequisites

- **Mac** with Xcode 15+ (iOS build — Mac-only)
- **Android Studio** (Android build — Mac/Windows/Linux)
- Node 20+, pnpm 9+
- Apple Developer account ($99/yr) for App Store
- Google Play Developer account ($25 one-time) for Play Store

---

## 1 — Initial setup (run once)

```bash
# From repo root
pnpm install

cd apps/web

# Add native platforms (generates ios/ and android/ directories)
npx cap add ios
npx cap add android
```

### After `cap add ios`:

1. Copy `ios-config/PrivacyInfo.xcprivacy` → `ios/App/App/PrivacyInfo.xcprivacy`
2. Open `ios/App/App/Info.plist` in Xcode as Source Code
3. Merge the keys from `ios-config/Info.plist.additions.xml` inside the root `<dict>`

---

## 2 — Set production URL

Edit `capacitor.config.ts` and update the server URL with your Vercel deployment URL:

```typescript
url: 'https://your-app.vercel.app',   // replace with real URL
```

Then sync:

```bash
npx cap sync
```

---

## 3 — iOS App Store submission

### Build in Xcode

```bash
cd apps/web
npx cap sync ios
npx cap open ios          # opens Xcode
```

In Xcode:
1. Select your Apple Developer **Team** (Signing & Capabilities)
2. Set **Bundle Identifier**: `com.prvhouse.app`
3. Set **Version**: `1.0.0` / **Build**: `1`
4. Add **App Icons** — generate all sizes from `public/icon-512.png` using
   [appicon.co](https://www.appicon.co/) or Xcode's icon generator
5. **Product → Archive** → **Distribute App → App Store Connect**

### App Store Connect checklist

- [ ] Create app with Bundle ID `com.prvhouse.app`
- [ ] Upload screenshots for iPhone 6.7" and 6.1" (minimum)
- [ ] Add Privacy Policy URL (required)
- [ ] Fill App Privacy labels (Data not collected)
- [ ] Set age rating (4+)
- [ ] Submit for review

---

## 4 — Android Play Store submission

```bash
cd apps/web
npx cap sync android
npx cap open android      # opens Android Studio
```

In Android Studio:
1. **Build → Generate Signed Bundle / APK** → **Android App Bundle**
2. Create a keystore (keep it safe — loss = can't update app)
3. Upload `.aab` to Play Console → Internal Testing → Production

### Play Console checklist

- [ ] Create app in [play.google.com/console](https://play.google.com/console)
- [ ] Upload App Bundle (AAB, not APK)
- [ ] Add screenshots for phone and 7" tablet
- [ ] Fill store listing (description, category: Productivity)
- [ ] Set content rating
- [ ] Add Privacy Policy URL
- [ ] Submit for review

---

## 5 — Local development with live reload

```bash
# Terminal 1 — start Next.js
cd apps/web && pnpm dev

# Terminal 2 — run on iOS simulator with live reload
cd apps/web && npx cap run ios -l --external
```

The `--external` flag makes it accessible over LAN (needed for physical device testing).

---

## App IDs & URLs

| Field         | Value                        |
|---------------|------------------------------|
| Bundle ID     | `com.prvhouse.app`           |
| Android ID    | `com.prvhouse.app`           |
| App Name      | PRV HOUSE                    |
| Vercel URL    | *(set after Vercel deploy)*  |
