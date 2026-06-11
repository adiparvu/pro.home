'use client'

import * as React from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import {
  Home,
  Building2,
  Sparkles,
  Users,
  ShieldCheck,
  Zap,
  Archive,
  Wrench,
  Banknote,
  FolderOpen,
  ShoppingCart,
  Search,
  Settings,
  ChevronLeft,
  ChevronRight,
  Flower2,
  LayoutPanelLeft,
  Bell,
  TrendingUp,
  FolderKanban,
  Cpu,
} from 'lucide-react'
import { useTranslations } from 'next-intl'
import { cn } from '@/lib/utils'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { useSidebarStore } from '@/stores/sidebar'

const NAV_ITEMS = [
  { i18nKey: 'home', href: '/', icon: Home, module: 'home' },
  { i18nKey: 'property', href: '/property', icon: Building2, module: 'property' },
  { i18nKey: 'aria', href: '/aria', icon: Sparkles, module: 'aria' },
  { i18nKey: 'family', href: '/family', icon: Users, module: 'family' },
] as const

const MORE_NAV_ITEMS = [
  { i18nKey: 'search', href: '/search', icon: Search, module: 'search' },
  { i18nKey: 'insights', href: '/insights', icon: TrendingUp, module: 'insights' },
  { i18nKey: 'projects', href: '/projects', icon: FolderKanban, module: 'projects' },
  { i18nKey: 'security', href: '/security', icon: ShieldCheck, module: 'security' },
  { i18nKey: 'energy', href: '/energy', icon: Zap, module: 'energy' },
  { i18nKey: 'inventory', href: '/inventory', icon: Archive, module: 'inventory' },
  { i18nKey: 'maintenance', href: '/maintenance', icon: Wrench, module: 'maintenance' },
  { i18nKey: 'finances', href: '/finances', icon: Banknote, module: 'finances' },
  { i18nKey: 'documents', href: '/documents', icon: FolderOpen, module: 'documents' },
  { i18nKey: 'marketplace', href: '/marketplace', icon: ShoppingCart, module: 'marketplace' },
  { i18nKey: 'garden', href: '/garden', icon: Flower2, module: 'garden' },
  { i18nKey: 'digitalTwin', href: '/digital-twin', icon: LayoutPanelLeft, module: 'digital-twin' },
] as const

const MODULE_COLORS: Record<string, string> = {
  home: 'hsl(210, 75%, 42%)',
  property: 'hsl(36, 75%, 42%)',
  aria: 'hsl(280, 68%, 47%)',
  family: 'hsl(340, 68%, 46%)',
  security: 'hsl(0, 68%, 44%)',
  energy: 'hsl(152, 62%, 38%)',
  inventory: 'hsl(185, 62%, 38%)',
  maintenance: 'hsl(22, 68%, 41%)',
  finances: 'hsl(45, 75%, 42%)',
  documents: 'hsl(220, 52%, 46%)',
  marketplace: 'hsl(88, 58%, 39%)',
  garden: 'hsl(120, 52%, 36%)',
  'digital-twin': 'hsl(260, 62%, 52%)',
  search: 'hsl(210, 75%, 42%)',
  insights: 'hsl(152, 62%, 38%)',
  projects: 'hsl(258, 62%, 52%)',
  'smart-home': 'hsl(185, 68%, 38%)',
  notifications: 'hsl(280, 68%, 47%)',
}

interface SidebarNavProps {
  unreadCount?: number
}

export function SidebarNav({ unreadCount = 0 }: SidebarNavProps) {
  const pathname = usePathname()
  const t = useTranslations('navigation')
  const { isExpanded, toggle } = useSidebarStore()

  return (
    <aside
      className={cn(
        'fixed left-0 top-0 z-[25] hidden md:flex flex-col h-full',
        'glass-opaque',
        'border-r border-border/50',
        'transition-all duration-slow',
        isExpanded ? 'w-[260px]' : 'w-[72px]'
      )}
    >
      {/* Header */}
      <div className={cn(
        'flex items-center p-4 gap-3',
        !isExpanded && 'justify-center'
      )}>
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary shadow-glow-home">
          <Home className="h-5 w-5 text-white" />
        </div>
        {isExpanded && (
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-bold text-gradient">PRV HOUSE</p>
            <p className="truncate text-[10px] text-muted-foreground uppercase tracking-wider">
              Property OS
            </p>
          </div>
        )}
      </div>

      <Separator className="opacity-30" />

      {/* Primary Nav */}
      <nav className="flex flex-col gap-1 p-2 flex-1 overflow-y-auto scrollbar-hide" aria-label="Main navigation">
        {NAV_ITEMS.map((item) => (
          <NavItem
            key={item.href}
            href={item.href}
            icon={item.icon}
            module={item.module}
            label={t(item.i18nKey)}
            isActive={pathname === item.href || (item.href !== '/' && pathname.startsWith(item.href))}
            isExpanded={isExpanded}
          />
        ))}

        <Separator className="my-2 opacity-30" />

        {MORE_NAV_ITEMS.map((item) => (
          <NavItem
            key={item.href}
            href={item.href}
            icon={item.icon}
            module={item.module}
            label={t(item.i18nKey)}
            isActive={pathname.startsWith(item.href)}
            isExpanded={isExpanded}
          />
        ))}
      </nav>

      <Separator className="opacity-30" />

      {/* Settings + Notifications + Collapse */}
      <div className="flex flex-col gap-1 p-2">
        <NavItem
          href="/notifications"
          label={t('notifications')}
          icon={Bell}
          module="notifications"
          isActive={pathname.startsWith('/notifications')}
          isExpanded={isExpanded}
          badge={unreadCount}
        />
        <NavItem
          href="/settings"
          label={t('settings')}
          icon={Settings}
          module="settings"
          isActive={pathname.startsWith('/settings')}
          isExpanded={isExpanded}
        />
        <Button
          variant="ghost"
          size="icon"
          className={cn('h-11', isExpanded && 'w-full justify-start gap-3 px-3')}
          onClick={toggle}
          aria-label={isExpanded ? 'Collapse sidebar' : 'Expand sidebar'}
        >
          {isExpanded ? (
            <>
              <ChevronLeft className="h-4 w-4 shrink-0" />
              <span className="text-sm">Collapse</span>
            </>
          ) : (
            <ChevronRight className="h-4 w-4" />
          )}
        </Button>
      </div>
    </aside>
  )
}

interface NavItemProps {
  href: string
  label: string
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>
  module: string
  isActive: boolean
  isExpanded: boolean
  badge?: number
}

function NavItem({ href, label, icon: Icon, module, isActive, isExpanded, badge }: NavItemProps) {
  const color = MODULE_COLORS[module]

  return (
    <Link
      href={href}
      className={cn(
        'group relative flex items-center gap-3 rounded-xl',
        'min-h-[44px] transition-all duration-fast',
        'focus-ring',
        isExpanded ? 'px-3' : 'justify-center px-3',
        isActive
          ? 'bg-[var(--color-selected)]'
          : 'hover:bg-[var(--color-hover)]'
      )}
      aria-current={isActive ? 'page' : undefined}
    >
      {isActive && (
        <span
          className="absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-6 rounded-full"
          style={{ backgroundColor: color }}
          aria-hidden="true"
        />
      )}
      <Icon
        className={cn(
          'h-5 w-5 shrink-0 transition-colors duration-fast',
          isActive ? 'text-foreground' : 'text-muted-foreground group-hover:text-foreground'
        )}
        style={isActive ? { color } : undefined}
      />
      {isExpanded && (
        <span
          className={cn(
            'flex-1 text-sm font-medium transition-colors duration-fast',
            isActive ? 'text-foreground' : 'text-muted-foreground group-hover:text-foreground'
          )}
        >
          {label}
        </span>
      )}
      {badge !== undefined && badge > 0 && (
        <Badge
          variant="danger"
          size="xs"
          className={cn(!isExpanded && 'absolute -right-1 -top-1')}
        >
          {badge > 99 ? '99+' : badge}
        </Badge>
      )}
    </Link>
  )
}
