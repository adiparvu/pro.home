import type { Config } from 'tailwindcss'

const config: Config = {
  darkMode: ['class'],
  content: [
    './src/**/*.{ts,tsx}',
  ],
  theme: {
    extend: {
      // ─── Color System ───────────────────────────────────────────────────────
      colors: {
        // Neutral scale
        neutral: {
          0: 'hsl(220, 15%, 98%)',
          50: 'hsl(220, 14%, 96%)',
          100: 'hsl(220, 13%, 91%)',
          200: 'hsl(220, 12%, 84%)',
          300: 'hsl(220, 11%, 72%)',
          400: 'hsl(220, 10%, 58%)',
          500: 'hsl(220, 9%, 46%)',
          600: 'hsl(220, 10%, 36%)',
          700: 'hsl(220, 12%, 28%)',
          800: 'hsl(220, 14%, 20%)',
          900: 'hsl(220, 16%, 14%)',
          1000: 'hsl(220, 18%, 10%)',
          1100: 'hsl(220, 20%, 7%)',
          1200: 'hsl(220, 22%, 4%)',
        },

        // CSS variable-driven semantic colors
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        card: {
          DEFAULT: 'hsl(var(--card))',
          foreground: 'hsl(var(--card-foreground))',
        },
        popover: {
          DEFAULT: 'hsl(var(--popover))',
          foreground: 'hsl(var(--popover-foreground))',
        },
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
        secondary: {
          DEFAULT: 'hsl(var(--secondary))',
          foreground: 'hsl(var(--secondary-foreground))',
        },
        muted: {
          DEFAULT: 'hsl(var(--muted))',
          foreground: 'hsl(var(--muted-foreground))',
        },
        accent: {
          DEFAULT: 'hsl(var(--accent))',
          foreground: 'hsl(var(--accent-foreground))',
        },
        destructive: {
          DEFAULT: 'hsl(var(--destructive))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',

        // Module colors
        module: {
          home: {
            100: 'hsl(210, 90%, 92%)',
            400: 'hsl(210, 75%, 52%)',
            500: 'hsl(210, 75%, 42%)',
            600: 'hsl(210, 75%, 33%)',
          },
          property: {
            100: 'hsl(36, 90%, 92%)',
            400: 'hsl(36, 78%, 52%)',
            500: 'hsl(36, 75%, 42%)',
          },
          twin: {
            500: 'hsl(252, 72%, 47%)',
          },
          family: {
            500: 'hsl(340, 68%, 46%)',
          },
          aria: {
            500: 'hsl(280, 68%, 47%)',
          },
          security: {
            500: 'hsl(0, 68%, 44%)',
          },
          energy: {
            500: 'hsl(152, 62%, 38%)',
          },
          inventory: {
            500: 'hsl(185, 62%, 38%)',
          },
          maintenance: {
            500: 'hsl(22, 68%, 41%)',
          },
        },

        // Status colors
        status: {
          success: 'hsl(152, 65%, 48%)',
          warning: 'hsl(38, 90%, 50%)',
          danger: 'hsl(0, 70%, 52%)',
          info: 'hsl(210, 75%, 50%)',
        },
      },

      // ─── Typography ─────────────────────────────────────────────────────────
      fontFamily: {
        sans: [
          'SF Pro Display',
          'SF Pro Text',
          '-apple-system',
          'BlinkMacSystemFont',
          'Geist',
          'Inter',
          'system-ui',
          'sans-serif',
        ],
        mono: [
          'SF Mono',
          'Geist Mono',
          'Fira Code',
          'ui-monospace',
          'monospace',
        ],
      },
      fontSize: {
        '2xs': ['10px', { lineHeight: '14px' }],
        xs: ['12px', { lineHeight: '16px' }],
        sm: ['13px', { lineHeight: '18px' }],
        base: ['15px', { lineHeight: '22px' }],
        md: ['17px', { lineHeight: '24px' }],
        lg: ['20px', { lineHeight: '28px' }],
        xl: ['24px', { lineHeight: '32px' }],
        '2xl': ['28px', { lineHeight: '36px' }],
        '3xl': ['34px', { lineHeight: '42px' }],
        '4xl': ['40px', { lineHeight: '48px' }],
        '5xl': ['48px', { lineHeight: '56px' }],
        '6xl': ['60px', { lineHeight: '68px' }],
        '7xl': ['72px', { lineHeight: '80px' }],
      },

      // ─── Spacing ─────────────────────────────────────────────────────────────
      spacing: {
        '0.5': '2px',
        '1.5': '6px',
        '2.5': '10px',
        '3.5': '14px',
        '4.5': '18px',
        '13': '52px',
        '15': '60px',
        '18': '72px',
        '22': '88px',
        safe: 'env(safe-area-inset-bottom)',
        'safe-top': 'env(safe-area-inset-top)',
      },

      // ─── Border Radius ───────────────────────────────────────────────────────
      borderRadius: {
        '2xs': '2px',
        xs: '4px',
        sm: '8px',
        DEFAULT: '12px',
        md: '12px',
        lg: '16px',
        xl: '20px',
        '2xl': '24px',
        '3xl': '32px',
        '4xl': '40px',
        '5xl': '48px',
        full: '9999px',
      },

      // ─── Shadows ────────────────────────────────────────────────────────────
      boxShadow: {
        '1': '0px 1px 2px rgba(0,0,0,0.04), 0px 1px 4px rgba(0,0,0,0.06)',
        '2': '0px 2px 4px rgba(0,0,0,0.06), 0px 4px 12px rgba(0,0,0,0.08), 0px 0px 0px 1px rgba(255,255,255,0.08)',
        '3': '0px 4px 8px rgba(0,0,0,0.08), 0px 8px 24px rgba(0,0,0,0.12), 0px 16px 40px rgba(0,0,0,0.08), 0px 0px 0px 1px rgba(255,255,255,0.10)',
        '4': '0px 8px 16px rgba(0,0,0,0.10), 0px 16px 40px rgba(0,0,0,0.14), 0px 32px 64px rgba(0,0,0,0.10), 0px 0px 0px 1px rgba(255,255,255,0.12)',
        '5': '0px 16px 32px rgba(0,0,0,0.14), 0px 32px 64px rgba(0,0,0,0.18), 0px 64px 128px rgba(0,0,0,0.12), 0px 0px 0px 1px rgba(255,255,255,0.14)',
        'inner-glass': 'inset 0px 1px 0px rgba(255,255,255,0.24), inset 1px 0px 0px rgba(255,255,255,0.08), inset -1px 0px 0px rgba(255,255,255,0.04), inset 0px -1px 0px rgba(0,0,0,0.12)',
        'glow-home': '0px 8px 32px rgba(46,143,236,0.20)',
        'glow-aria': '0px 8px 32px rgba(128,64,196,0.20)',
        'glow-energy': '0px 8px 32px rgba(48,180,112,0.20)',
        'glow-security': '0px 8px 32px rgba(180,32,32,0.20)',
      },

      // ─── Backdrop Blur ───────────────────────────────────────────────────────
      backdropBlur: {
        xs: '4px',
        sm: '8px',
        DEFAULT: '16px',
        md: '16px',
        lg: '24px',
        xl: '40px',
        '2xl': '60px',
        '3xl': '80px',
        max: '100px',
      },

      // ─── Animation ───────────────────────────────────────────────────────────
      transitionTimingFunction: {
        'spring-out': 'cubic-bezier(0.34, 1.56, 0.64, 1)',
        'spring-in-out': 'cubic-bezier(0.68, -0.55, 0.27, 1.55)',
        'ease-out': 'cubic-bezier(0.0, 0.0, 0.2, 1.0)',
        'ease-in': 'cubic-bezier(0.4, 0.0, 1.0, 1.0)',
      },
      transitionDuration: {
        fast: '100ms',
        normal: '200ms',
        slow: '320ms',
        slower: '480ms',
      },
      keyframes: {
        'fade-in': {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        'fade-out': {
          '0%': { opacity: '1' },
          '100%': { opacity: '0' },
        },
        'slide-up': {
          '0%': { transform: 'translateY(16px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        'slide-down': {
          '0%': { transform: 'translateY(-8px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        'scale-in': {
          '0%': { transform: 'scale(0.95)', opacity: '0' },
          '100%': { transform: 'scale(1)', opacity: '1' },
        },
        'skeleton-shimmer': {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
        'pulse-soft': {
          '0%, 100%': { opacity: '1' },
          '50%': { opacity: '0.5' },
        },
        'spin-slow': {
          '0%': { transform: 'rotate(0deg)' },
          '100%': { transform: 'rotate(360deg)' },
        },
      },
      animation: {
        'fade-in': 'fade-in 200ms ease-out',
        'fade-out': 'fade-out 200ms ease-in',
        'slide-up': 'slide-up 300ms cubic-bezier(0.34, 1.56, 0.64, 1)',
        'slide-down': 'slide-down 200ms ease-out',
        'scale-in': 'scale-in 200ms cubic-bezier(0.34, 1.56, 0.64, 1)',
        'skeleton': 'skeleton-shimmer 1.6s ease-in-out infinite',
        'pulse-soft': 'pulse-soft 2s ease-in-out infinite',
        'spin-slow': 'spin-slow 2s linear infinite',
      },

      // ─── Screens ─────────────────────────────────────────────────────────────
      screens: {
        xs: '375px',
        sm: '430px',
        md: '768px',
        lg: '1024px',
        xl: '1280px',
        '2xl': '1440px',
        '3xl': '1920px',
      },
    },
  },
  plugins: [],
}

export default config
