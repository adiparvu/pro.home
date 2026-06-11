import * as React from 'react'
import Link from 'next/link'
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
  FileText,
  Building2,
  BarChart2,
  CalendarCheck,
  Percent,
  FilePlus,
  MessageSquare,
  Vault,
  DoorOpen,
} from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'

interface MoreItem {
  label: string
  description: string
  href: string
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>
  color: string
  external?: boolean
}

const MORE_ITEMS: MoreItem[] = [
  { label: 'Notifications', description: 'Alerts, recalls & reminders', href: '/notifications', icon: Bell, color: 'hsl(280, 68%, 47%)' },
  { label: 'Search', description: 'Find anything in your home', href: '/search', icon: Search, color: 'hsl(210, 75%, 42%)' },
  { label: 'Projects', description: 'Renovation & home projects', href: '/projects', icon: FolderKanban, color: 'hsl(258, 62%, 52%)' },
  { label: 'Insights', description: 'AI-powered property intelligence', href: '/insights', icon: TrendingUp, color: 'hsl(152, 62%, 38%)' },
  { label: 'Security', description: 'Cameras, locks & alarms', href: '/security', icon: ShieldCheck, color: 'hsl(0, 68%, 44%)' },
  { label: 'Energy', description: 'Usage & optimization', href: '/energy', icon: Zap, color: 'hsl(152, 62%, 38%)' },
  { label: 'Meter Readings', description: 'Electricity, gas & water meters', href: '/energy/meters', icon: Gauge, color: 'hsl(45, 75%, 42%)' },
  { label: 'Carbon Footprint', description: 'CO₂ emissions tracker', href: '/energy/carbon', icon: Leaf, color: 'hsl(120, 52%, 36%)' },
  { label: 'Inventory', description: 'Appliances & assets', href: '/inventory', icon: Archive, color: 'hsl(185, 62%, 38%)' },
  { label: 'Maintenance', description: 'Tasks & repairs', href: '/maintenance', icon: Wrench, color: 'hsl(22, 68%, 41%)' },
  { label: 'Move Checklist', description: 'Moving in & out checklist', href: '/maintenance/checklist', icon: ClipboardList, color: 'hsl(22, 68%, 41%)' },
  { label: 'Recurring Tasks', description: 'Scheduled maintenance templates', href: '/maintenance/recurring', icon: RotateCcw, color: 'hsl(22, 68%, 41%)' },
  { label: 'Defect Log', description: 'Track and manage property defects', href: '/maintenance/defects', icon: Bug, color: 'hsl(0, 68%, 44%)' },
  { label: 'Seasonal Planner', description: 'Seasonal maintenance templates', href: '/maintenance/seasonal', icon: Sun, color: 'hsl(45, 75%, 42%)' },
  { label: 'Finances', description: 'Costs & budgets', href: '/finances', icon: Banknote, color: 'hsl(45, 75%, 42%)' },
  { label: 'Budget', description: 'Budget planning & tracking', href: '/finances/budget', icon: PieChart, color: 'hsl(45, 75%, 42%)' },
  { label: 'Cost Split', description: 'Split costs with housemates', href: '/finances/split', icon: Split, color: 'hsl(88, 58%, 39%)' },
  { label: 'Mortgage', description: 'Mortgage tracker & repayment progress', href: '/finances/mortgage', icon: Building2, color: 'hsl(270, 62%, 52%)' },
  { label: 'Insurance', description: 'Insurance policies & renewal dates', href: '/finances/insurance', icon: ShieldCheck, color: 'hsl(152, 62%, 42%)' },
  { label: 'Forecast', description: 'Expense forecasting by category', href: '/finances/forecast', icon: BarChart2, color: 'hsl(220, 62%, 52%)' },
  { label: 'Tax Report', description: 'Download annual tax summary', href: '/api/reports/tax?year=2025', icon: FileText, color: 'hsl(45, 75%, 42%)', external: true },
  { label: 'Documents', description: 'Contracts & manuals', href: '/documents', icon: FolderOpen, color: 'hsl(220, 52%, 46%)' },
  { label: 'Expiry Radar', description: 'Documents & warranties expiring', href: '/documents/expiry', icon: ScanSearch, color: 'hsl(22, 68%, 41%)' },
  { label: 'Compliance', description: 'Certificates & regulatory checks', href: '/documents/compliance', icon: ShieldCheck, color: 'hsl(152, 62%, 38%)' },
  { label: 'Marketplace', description: 'Service providers & contacts', href: '/marketplace', icon: ShoppingCart, color: 'hsl(88, 58%, 39%)' },
  { label: 'Smart Home Log', description: 'Device events & readings', href: '/smart-home', icon: Cpu, color: 'hsl(185, 68%, 38%)' },
  { label: 'Garden', description: 'Plants, tasks & zones', href: '/garden', icon: Flower2, color: 'hsl(120, 52%, 36%)' },
  { label: 'Digital Twin', description: 'Interactive floor plan', href: '/digital-twin', icon: LayoutPanelLeft, color: 'hsl(260, 62%, 52%)' },
  { label: 'Tenant Portal', description: 'Tenant & guest view', href: '/tenant', icon: Home, color: 'hsl(210, 75%, 42%)' },
  { label: 'Leases', description: 'Lease agreements & tenants', href: '/tenant/leases', icon: FileSignature, color: 'hsl(210, 75%, 42%)' },
  { label: 'Tenant Portal', description: 'Tenant request portal links', href: '/tenant/portal', icon: MessageSquare, color: 'hsl(210, 75%, 42%)' },
  { label: 'Deposit', description: 'Deposit deductions & lifecycle', href: '/tenant/deposit', icon: Vault, color: 'hsl(45, 75%, 42%)' },
  { label: 'Vacancies', description: 'Vacancy periods & rent loss', href: '/tenant/vacancy', icon: DoorOpen, color: 'hsl(220, 52%, 46%)' },
  { label: 'Access Codes', description: 'Temporary access QR codes', href: '/access', icon: KeyRound, color: 'hsl(280, 62%, 47%)' },
  { label: 'Household', description: 'Shared grocery & to-do lists', href: '/household', icon: ShoppingCart, color: 'hsl(152, 62%, 38%)' },
  { label: 'Packages', description: 'Package delivery tracking', href: '/household/packages', icon: Package, color: 'hsl(220, 62%, 52%)' },
  { label: 'Contractors', description: 'Service providers & directory', href: '/contractors', icon: HardHat, color: 'hsl(185, 62%, 38%)' },
  { label: 'Compare Properties', description: 'Side-by-side property metrics', href: '/property/compare', icon: GitCompare, color: 'hsl(258, 62%, 52%)' },
  { label: 'Integrations', description: 'Webhooks & automation', href: '/settings/integrations', icon: Webhook, color: 'hsl(220, 52%, 46%)' },
  { label: 'Timeline', description: 'Property activity log', href: '/timeline', icon: Clock, color: 'hsl(220, 62%, 52%)' },
  { label: 'ROI Calculator', description: 'Return on investment analysis', href: '/property/roi', icon: Calculator, color: 'hsl(152, 62%, 38%)' },
  { label: 'Occupancy', description: 'Vacancy & occupancy rate dashboard', href: '/analytics/occupancy', icon: CalendarCheck, color: 'hsl(152, 62%, 38%)' },
  { label: 'Rent Yield', description: 'Gross & net rental yield calculator', href: '/analytics/yield', icon: Percent, color: 'hsl(45, 75%, 42%)' },
  { label: '5-Year Forecast', description: 'Property value & income projections', href: '/analytics/forecast', icon: TrendingUp, color: 'hsl(258, 62%, 52%)' },
  { label: 'Templates', description: 'Generate tenant documents & notices', href: '/documents/templates', icon: FilePlus, color: 'hsl(220, 52%, 46%)' },
  { label: 'Calendar Export', description: 'Download all events as .ics', href: '/api/calendar/export', icon: CalendarDays, color: 'hsl(210, 75%, 42%)', external: true },
]

export function MoreMenu() {
  return (
    <>
      <PageHeader title="More" />
      <div className="px-4 py-4 md:px-6 md:py-6">
        <div className="flex flex-col gap-2">
          {MORE_ITEMS.map(({ label, description, href, icon: Icon, color, external }) => {
            const inner = (
              <>
                <div
                  className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl"
                  style={{ background: `${color}22` }}
                >
                  <Icon className="h-5 w-5" style={{ color }} />
                </div>
                <div className="flex-1">
                  <p className="text-sm font-semibold text-foreground">{label}</p>
                  <p className="text-xs text-muted-foreground">{description}</p>
                </div>
                <ChevronRight className="h-4 w-4 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
              </>
            )

            if (external) {
              return (
                <a
                  key={href}
                  href={href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-4 rounded-2xl glass-light p-4 transition-colors hover:glass-standard focus-ring group"
                >
                  {inner}
                </a>
              )
            }

            return (
              <Link
                key={href}
                href={href}
                className="flex items-center gap-4 rounded-2xl glass-light p-4 transition-colors hover:glass-standard focus-ring group"
              >
                {inner}
              </Link>
            )
          })}
        </div>
      </div>
    </>
  )
}
