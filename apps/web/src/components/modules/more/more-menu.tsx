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
} from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'

const MORE_ITEMS = [
  { label: 'Notifications', description: 'Alerts, recalls & reminders', href: '/notifications', icon: Bell, color: 'hsl(280, 68%, 47%)' },
  { label: 'Search', description: 'Find anything in your home', href: '/search', icon: Search, color: 'hsl(210, 75%, 42%)' },
  { label: 'Projects', description: 'Renovation & home projects', href: '/projects', icon: FolderKanban, color: 'hsl(258, 62%, 52%)' },
  { label: 'Insights', description: 'AI-powered property intelligence', href: '/insights', icon: TrendingUp, color: 'hsl(152, 62%, 38%)' },
  { label: 'Security', description: 'Cameras, locks & alarms', href: '/security', icon: ShieldCheck, color: 'hsl(0, 68%, 44%)' },
  { label: 'Energy', description: 'Usage & optimization', href: '/energy', icon: Zap, color: 'hsl(152, 62%, 38%)' },
  { label: 'Meter Readings', description: 'Electricity, gas & water meters', href: '/energy/meters', icon: Gauge, color: 'hsl(45, 75%, 42%)' },
  { label: 'Inventory', description: 'Appliances & assets', href: '/inventory', icon: Archive, color: 'hsl(185, 62%, 38%)' },
  { label: 'Maintenance', description: 'Tasks & repairs', href: '/maintenance', icon: Wrench, color: 'hsl(22, 68%, 41%)' },
  { label: 'Move Checklist', description: 'Moving in & out checklist', href: '/maintenance/checklist', icon: ClipboardList, color: 'hsl(22, 68%, 41%)' },
  { label: 'Recurring Tasks', description: 'Scheduled maintenance templates', href: '/maintenance/recurring', icon: RotateCcw, color: 'hsl(22, 68%, 41%)' },
  { label: 'Finances', description: 'Costs & budgets', href: '/finances', icon: Banknote, color: 'hsl(45, 75%, 42%)' },
  { label: 'Budget', description: 'Budget planning & tracking', href: '/finances/budget', icon: PieChart, color: 'hsl(45, 75%, 42%)' },
  { label: 'Cost Split', description: 'Split costs with housemates', href: '/finances/split', icon: Split, color: 'hsl(88, 58%, 39%)' },
  { label: 'Documents', description: 'Contracts & manuals', href: '/documents', icon: FolderOpen, color: 'hsl(220, 52%, 46%)' },
  { label: 'Marketplace', description: 'Service providers & contacts', href: '/marketplace', icon: ShoppingCart, color: 'hsl(88, 58%, 39%)' },
  { label: 'Smart Home Log', description: 'Device events & readings', href: '/smart-home', icon: Cpu, color: 'hsl(185, 68%, 38%)' },
  { label: 'Garden', description: 'Plants, tasks & zones', href: '/garden', icon: Flower2, color: 'hsl(120, 52%, 36%)' },
  { label: 'Digital Twin', description: 'Interactive floor plan', href: '/digital-twin', icon: LayoutPanelLeft, color: 'hsl(260, 62%, 52%)' },
  { label: 'Tenant Portal', description: 'Tenant & guest view', href: '/tenant', icon: Home, color: 'hsl(210, 75%, 42%)' },
  { label: 'Leases', description: 'Lease agreements & tenants', href: '/tenant/leases', icon: FileSignature, color: 'hsl(210, 75%, 42%)' },
  { label: 'Household', description: 'Shared grocery & to-do lists', href: '/household', icon: ShoppingCart, color: 'hsl(152, 62%, 38%)' },
  { label: 'Packages', description: 'Package delivery tracking', href: '/household/packages', icon: Package, color: 'hsl(220, 62%, 52%)' },
  { label: 'Contractors', description: 'Service providers & directory', href: '/contractors', icon: HardHat, color: 'hsl(185, 62%, 38%)' },
  { label: 'Integrations', description: 'Webhooks & automation', href: '/settings/integrations', icon: Webhook, color: 'hsl(220, 52%, 46%)' },
]

export function MoreMenu() {
  return (
    <>
      <PageHeader title="More" />
      <div className="px-4 py-4 md:px-6 md:py-6">
        <div className="flex flex-col gap-2">
          {MORE_ITEMS.map(({ label, description, href, icon: Icon, color }) => (
            <Link
              key={href}
              href={href}
              className="flex items-center gap-4 rounded-2xl glass-light p-4 transition-colors hover:glass-standard focus-ring group"
            >
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
            </Link>
          ))}
        </div>
      </div>
    </>
  )
}
