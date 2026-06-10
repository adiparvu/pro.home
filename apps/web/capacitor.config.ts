import type { CapacitorConfig } from '@capacitor/cli'

const isProd = process.env.NODE_ENV === 'production'

const config: CapacitorConfig = {
  appId: 'com.prvhouse.app',
  appName: 'PRV HOUSE',
  // webDir is the built output; in live-reload / server mode the bundle is served remotely
  webDir: 'public',
  server: isProd
    ? {
        // Set CAPACITOR_SERVER_URL in CI or replace with your Vercel URL
        url: process.env.CAPACITOR_SERVER_URL ?? 'https://app.prvhouse.com',
        cleartext: false,
        androidScheme: 'https',
      }
    : {
        // Local dev — run `next dev` first, then `cap run ios -l`
        url: 'http://localhost:3000',
        cleartext: true,
      },
  ios: {
    contentInset: 'automatic',
    backgroundColor: '#0D1420',
    scheme: 'PRV HOUSE',
  },
  android: {
    backgroundColor: '#0D1420',
    allowMixedContent: false,
    captureInput: true,
    webContentsDebuggingEnabled: false,
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1800,
      launchAutoHide: true,
      backgroundColor: '#0D1420',
      iosSpinnerStyle: 'small',
      spinnerColor: '#60a5fa',
      showSpinner: false,
      androidSplashResourceName: 'splash',
      androidScaleType: 'CENTER_CROP',
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#0D1420',
      overlaysWebView: false,
    },
    Keyboard: {
      resize: 'body',
      style: 'DARK',
      resizeOnFullScreen: true,
    },
    PushNotifications: {
      presentationOptions: ['badge', 'sound', 'alert'],
    },
    Camera: {
      // Required for M-SCAN barcode scanner
    },
  },
}

export default config
