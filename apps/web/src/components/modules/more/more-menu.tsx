'use client'

import * as React from 'react'
import Link from 'next/link'
import { useTheme } from 'next-themes'
import {
  ShieldCheck,
  Zap,
  Archive,
  Wrench,
  Banknote,
  FolderOpen,
  ShoppingCart,
  Search,
  ChevronRight,
  ChevronDown,
  Flower2,
  LayoutPanelLeft,
  Bell,
  FolderKanban,
  Cpu,
  TrendingUp,
  Webhook,
  Home,
  RotateCcw,
  HardHat,
  Gauge,
  FileSignature,
  Package,
  ClipboardList,
  PieChart,
  Split,
  Clock,
  Calculator,
  Leaf,
  ScanSearch,
  KeyRound,
  GitCompare,
  CalendarDays,
  Bug,
  Sun,
  Moon,
  Monitor,
  FileText,
  Building2,
  BarChart2,
  CalendarCheck,
  Percent,
  FilePlus,
  MessageSquare,
  Vault,
  DoorOpen,
  MapPin,
  Wifi,
  Globe,
  MessageCircle,
  Info,
  Settings,
  LayoutGrid,
  Sparkles,
} from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'
import { cn } from '@/lib/utils'

interface MoreItem {
  label: string
  description: string
  href: string
  icon: React.ComponentType<{ className?: string }>
  external?: boolean
}

interface Category {
  id: string
  label: string
  icon: React.ComponentType<{ className?: string }>
  items: MoreItem[]
}

const CATEGORIES: Category[] = [
  {
    id: 'overview',
    label: 'Overview',
    icon: LayoutGrid,
    items: [
      { label: 'Notifications', description: 'Alerts, recalls & reminders', href: '/notifications', icon: Bell },
      { label: 'Search', description: 'Find anything in your home', href: '/search', icon: Search },
      { label: 'Insights', description: 'AI-powered property intelligence', href: '/insights', icon: Sparkles },
      { label: 'Timeline', description: 'Property activity log', href: '/timeline', icon: Clock },
    ],
  },
  {
    id: 'security',
    label: 'Security & Access',
    icon: ShieldCheck,
    items: [
      { label: 'Security', description: 'Cameras, locks & alarms', href: '/security', icon: ShieldCheck },
      { label: 'Smart Home', description: 'Webhook tokens & smart meter integration', href: '/energy/smart-home', icon: Wifi },
      { label: 'Smart Home Log', description: 'Device events & readings', href: '/smart-home', icon: Cpu },
      { label: 'Access Codes', description: 'Temporary access QR codes', href: '/access', icon: KeyRound },
    ],
  },
  {
    id: 'energy',
    label: 'Energy & Environment',
    icon: Zap,
    items: [
      { label: 'Energy', description: 'Usage & optimization', href: '/energy', icon: Zap },
      { label: 'Meter Readings', description: 'Electricity, gas & water meters', href: '/energy/meters', icon: Gauge },
      { label: 'Carbon Footprint', description: 'CO₂ emissions tracker', href: '/energy/carbon', icon: Leaf },
    ],
  },
  {
    id: 'maintenance',
    label: 'Maintenance & Projects',
    icon: Wrench,
    items: [
      { label: 'Maintenance', description: 'Tasks & repairs', href: '/maintenance', icon: Wrench },
      { label: 'Projects', description: 'Renovation & home projects', href: '/projects', icon: FolderKanban },
      { label: 'Move Checklist', description: 'Moving in & out checklist', href: '/maintenance/checklist', icon: ClipboardList },
      { label: 'Recurring Tasks', description: 'Scheduled maintenance templates', href: '/maintenance/recurring', icon: RotateCcw },
      { label: 'Defect Log', description: 'Track and manage property defects', href: '/maintenance/defects', icon: Bug },
      { label: 'Seasonal Planner', description: 'Seasonal maintenance templates', href: '/maintenance/seasonal', icon: Sun },
    ],
  },
  {
    id: 'finances',
    label: 'Finances',
    icon: Banknote,
    items: [
      { label: 'Finances', description: 'Costs & budgets', href: '/finances', icon: Banknote },
      { label: 'Budget', description: 'Budget planning & tracking', href: '/finances/budget', icon: PieChart },
      { label: 'Cost Split', description: 'Split costs with housemates', href: '/finances/split', icon: Split },
      { label: 'Mortgage', description: 'Mortgage tracker & repayment progress', href: '/finances/mortgage', icon: Building2 },
      { label: 'Insurance', description: 'Insurance policies & renewal dates', href: '/finances/insurance', icon: ShieldCheck },
      { label: 'Forecast', description: 'Expense forecasting by category', href: '/finances/forecast', icon: BarChart2 },
      { label: 'Tax Report', description: 'Download annual tax summary', href: '/api/reports/tax?year=2025', icon: FileText, external: true },
    ],
  },
  {
    id: 'documents',
    label: 'Documents & Compliance',
    icon: FolderOpen,
    items: [
      { label: 'Documents', description: 'Contracts & manuals', href: '/documents', icon: FolderOpen },
      { label: 'Expiry Radar', description: 'Documents & warranties expiring', href: '/documents/expiry', icon: ScanSearch },
      { label: 'Compliance', description: 'Certificates & regulatory checks', href: '/documents/compliance', icon: ShieldCheck },
      { label: 'Templates', description: 'Generate tenant documents & notices', href: '/documents/templates', icon: FilePlus },
      { label: 'Calendar Export', description: 'Download all events as .ics', href: '/api/calendar/export', icon: CalendarDays, external: true },
    ],
  },
  {
    id: 'tenant',
    label: 'Tenant & Rental',
    icon: Home,
    items: [
      { label: 'Tenant Portal', description: 'Tenant & guest view', href: '/tenant', icon: Home },
      { label: 'Leases', description: 'Lease agreements & tenants', href: '/tenant/leases', icon: FileSignature },
      { label: 'Portal Links', description: 'Tenant request portal links', href: '/tenant/portal', icon: MessageSquare },
      { label: 'Deposit', description: 'Deposit deductions & lifecycle', href: '/tenant/deposit', icon: Vault },
      { label: 'Vacancies', description: 'Vacancy periods & rent loss', href: '/tenant/vacancy', icon: DoorOpen },
    ],
  },
  {
    id: 'analytics',
    label: 'Property Analytics',
    icon: TrendingUp,
    items: [
      { label: 'Compare Properties', description: 'Side-by-side property metrics', href: '/property/compare', icon: GitCompare },
      { label: 'ROI Calculator', description: 'Return on investment analysis', href: '/property/roi', icon: Calculator },
      { label: 'Share Register', description: 'Co-ownership share register', href: '/property/shares', icon: PieChart },
      { label: 'Occupancy', description: 'Vacancy & occupancy rate dashboard', href: '/analytics/occupancy', icon: CalendarCheck },
      { label: 'Rent Yield', description: 'Gross & net rental yield calculator', href: '/analytics/yield', icon: Percent },
      { label: '5-Year Forecast', description: 'Property value & income projections', href: '/analytics/forecast', icon: TrendingUp },
      { label: 'Neighbourhood', description: 'Compare your property to area benchmarks', href: '/analytics/neighbourhood', icon: MapPin },
    ],
  },
  {
    id: 'home',
    label: 'Home & Lifestyle',
    icon: Archive,
    items: [
      { label: 'Inventory', description: 'Appliances & assets', href: '/inventory', icon: Archive },
      { label: 'Household', description: 'Shared grocery & to-do lists', href: '/household', icon: ShoppingCart },
      { label: 'Packages', description: 'Package delivery tracking', href: '/household/packages', icon: Package },
      { label: 'Contractors', description: 'Service providers & directory', href: '/contractors', icon: HardHat },
      { label: 'Garden', description: 'Plants, tasks & zones', href: '/garden', icon: Flower2 },
      { label: 'Marketplace', description: 'Service providers & contacts', href: '/marketplace', icon: ShoppingCart },
      { label: 'Digital Twin', description: 'Interactive floor plan', href: '/digital-twin', icon: LayoutPanelLeft },
      { label: 'Integrations', description: 'Webhooks & automation', href: '/settings/integrations', icon: Webhook },
    ],
  },
]

const THEME_OPTIONS = [
  { id: 'light', label: 'Light', icon: Sun },
  { id: 'dark', label: 'Dark', icon: Moon },
  { id: 'system', label: 'System', icon: Monitor },
] as const

const APP_VERSION = '1.0.0'

function ItemRow({ label, description, href, icon: Icon, external }: MoreItem) {
  const inner = (
    <>
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-foreground/8">
        <Icon className="h-4 w-4 text-foreground/70" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold text-foreground leading-tight">{label}</p>
        <p className="text-xs text-muted-foreground leading-snug mt-0.5 truncate">{description}</p>
      </div>
      <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground/50 transition-transform group-hover:translate-x-0.5" />
    </>
  )

  const className = 'flex items-center gap-3 rounded-xl px-3 py-2.5 transition-colors hover:bg-foreground/[0.06] focus-ring group'

  if (external) {
    return (
      <a href={href} target="_blank" rel="noopener noreferrer" className={className}>
        {inner}
      </a>
    )
  }

  return (
    <Link href={href} className={className}>
      {inner}
    </Link>
  )
}

function CategorySection({ category }: { category: Category }) {
  const [isOpen, setIsOpen] = React.useState(false)
  const { id, label, icon: CatIcon, items } = category

  return (
    <div className="rounded-2xl overflow-hidden glass-light" key={id}>
      <button
        type="button"
        onClick={() => setIsOpen(v => !v)}
        className="w-full flex items-center gap-3 px-4 py-3.5 text-left focus-ring"
        aria-expanded={isOpen}
      >
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-foreground/10">
          <CatIcon className="h-4 w-4 text-foreground/80" />
        </div>
        <span className="flex-1 text-sm font-semibold text-foreground">{label}</span>
        <span className="text-xs font-medium text-muted-foreground tabular-nums mr-1">{items.length}</span>
        <ChevronDown
          className={cn(
            'h-4 w-4 shrink-0 text-muted-foreground transition-transform duration-200',
            isOpen && 'rotate-180'
          )}
        />
      </button>

      {isOpen && (
        <div className="px-2 pb-2 border-t border-foreground/[0.08]">
          {items.map(item => (
            <ItemRow key={item.href} {...item} />
          ))}
        </div>
      )}
    </div>
  )
}

function AppSettingsSection() {
  const [isOpen, setIsOpen] = React.useState(false)
  const { theme, setTheme } = useTheme()

  return (
    <div className="rounded-2xl overflow-hidden glass-light">
      <button
        type="button"
        onClick={() => setIsOpen(v => !v)}
        className="w-full flex items-center gap-3 px-4 py-3.5 text-left focus-ring"
        aria-expanded={isOpen}
      >
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-foreground/10">
          <Settings className="h-4 w-4 text-foreground/80" />
        </div>
        <span className="flex-1 text-sm font-semibold text-foreground">App Settings</span>
        <ChevronDown
          className={cn(
            'h-4 w-4 shrink-0 text-muted-foreground transition-transform duration-200',
            isOpen && 'rotate-180'
          )}
        />
      </button>

      {isOpen && (
        <div className="px-4 pb-4 border-t border-foreground/[0.08] pt-3 flex flex-col gap-3">
          {/* Theme */}
          <div>
            <p className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground mb-2 px-1">Theme</p>
            <div className="grid grid-cols-3 gap-2">
              {THEME_OPTIONS.map(({ id, label, icon: Icon }) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => setTheme(id)}
                  className={cn(
                    'flex flex-col items-center gap-1.5 rounded-xl py-3 px-2 transition-all focus-ring border',
                    theme === id
                      ? 'bg-foreground text-background border-foreground'
                      : 'glass-light border-transparent hover:bg-foreground/[0.06]'
                  )}
                >
                  <Icon
                    className={cn('h-4 w-4', theme === id ? 'text-background' : 'text-muted-foreground')}
                  />
                  <span className={cn('text-xs font-semibold', theme === id ? 'text-background' : 'text-muted-foreground')}>
                    {label}
                  </span>
                </button>
              ))}
            </div>
          </div>

          {/* Language */}
          <Link
            href="/settings/language"
            className="flex items-center gap-3 rounded-xl px-3 py-2.5 transition-colors hover:bg-foreground/[0.06] focus-ring group"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-foreground/10">
              <Globe className="h-4 w-4 text-foreground/80" />
            </div>
            <div className="flex-1">
              <p className="text-sm font-semibold text-foreground">Language</p>
              <p className="text-xs text-muted-foreground">Select your preferred language</p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground/50 group-hover:translate-x-0.5 transition-transform" />
          </Link>

          {/* Feedback */}
          <a
            href="mailto:feedback@prvhouse.app"
            className="flex items-center gap-3 rounded-xl px-3 py-2.5 transition-colors hover:bg-foreground/[0.06] focus-ring group"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-foreground/10">
              <MessageCircle className="h-4 w-4 text-foreground/80" />
            </div>
            <div className="flex-1">
              <p className="text-sm font-semibold text-foreground">Send Feedback</p>
              <p className="text-xs text-muted-foreground">Help us improve the app</p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground/50 group-hover:translate-x-0.5 transition-transform" />
          </a>

          {/* App Version */}
          <div className="flex items-center gap-3 px-3 py-2.5">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-foreground/10">
              <Info className="h-4 w-4 text-muted-foreground" />
            </div>
            <div className="flex-1">
              <p className="text-sm font-semibold text-foreground">App Version</p>
              <p className="text-xs text-muted-foreground">v{APP_VERSION}</p>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export function MoreMenu() {
  return (
    <>
      <PageHeader title="More" />
      <div className="px-4 py-4 md:px-6 md:py-6 flex flex-col gap-2.5">
        {CATEGORIES.map(category => (
          <CategorySection key={category.id} category={category} />
        ))}
        <AppSettingsSection />
      </div>
    </>
  )
}
