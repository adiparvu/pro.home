'use client'

import * as React from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Building2, MapPin, ChevronRight, Plus, ArchiveRestore, ChevronDown } from 'lucide-react'
import type { Property } from '@/lib/supabase/types'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { createClient } from '@/lib/supabase/client'

interface PropertyListProps {
  properties: Property[]
  archivedProperties?: Property[]
}

export function PropertyList({ properties, archivedProperties = [] }: PropertyListProps) {
  const router = useRouter()
  const [restoringId, setRestoringId] = React.useState<string | null>(null)
  const [showArchived, setShowArchived] = React.useState(false)

  async function handleRestore(propertyId: string) {
    setRestoringId(propertyId)
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('properties').update({ is_active: true }).eq('id', propertyId)
    setRestoringId(null)
    router.refresh()
  }

  if (properties.length === 0 && archivedProperties.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center gap-4 py-20 text-center">
        <div className="flex h-16 w-16 items-center justify-center rounded-2xl glass-standard">
          <Building2 className="h-8 w-8 text-muted-foreground" />
        </div>
        <div>
          <p className="font-semibold text-foreground">No properties yet</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Add your first property to get started
          </p>
        </div>
        <Button asChild variant="primary" size="sm">
          <Link href="/property/new">
            <Plus className="h-4 w-4" />
            Add Property
          </Link>
        </Button>
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-6">
      {properties.length > 0 ? (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {properties.map((property) => (
            <PropertyCard key={property.id} property={property} />
          ))}
        </div>
      ) : (
        <div className="flex flex-col items-center justify-center gap-4 py-12 text-center">
          <p className="text-sm text-muted-foreground">No active properties.</p>
          <Button asChild variant="primary" size="sm">
            <Link href="/property/new">
              <Plus className="h-4 w-4" />
              Add Property
            </Link>
          </Button>
        </div>
      )}

      {archivedProperties.length > 0 && (
        <div>
          <button
            onClick={() => setShowArchived(!showArchived)}
            className="flex w-full items-center justify-between gap-2 rounded-lg px-1 py-2 text-sm text-muted-foreground transition-colors hover:text-foreground focus-ring"
          >
            <span className="font-medium">Archived ({archivedProperties.length})</span>
            <ChevronDown className={`h-4 w-4 transition-transform ${showArchived ? 'rotate-180' : ''}`} />
          </button>
          {showArchived && (
            <div className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {archivedProperties.map((property) => (
                <ArchivedPropertyCard
                  key={property.id}
                  property={property}
                  onRestore={() => handleRestore(property.id)}
                  restoring={restoringId === property.id}
                />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function PropertyCard({ property }: { property: Property }) {
  const healthColor =
    (property.health_score ?? 0) >= 85
      ? 'success'
      : (property.health_score ?? 0) >= 70
        ? 'warning'
        : 'danger'

  return (
    <Link href={`/property/${property.id}`} className="block focus-ring rounded-2xl">
      <Card variant="default" hover padding="lg" moduleColor="property" className="group">
        <div className="flex items-start justify-between gap-3">
          <div
            className="h-11 w-11 shrink-0 overflow-hidden rounded-xl"
            style={{ background: 'hsl(36, 78%, 52% / 0.15)' }}
          >
            {property.photo_url ? (
              <img
                src={property.photo_url}
                alt={property.name}
                className="h-full w-full object-cover"
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center">
                <Building2 className="h-5 w-5" style={{ color: 'hsl(36, 78%, 52%)' }} />
              </div>
            )}
          </div>
          {property.health_score !== null && (
            <Badge variant={healthColor} size="sm">
              {property.health_score}%
            </Badge>
          )}
        </div>

        <div className="mt-3">
          <p className="truncate font-semibold text-foreground">{property.name}</p>
          <div className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
            <MapPin className="h-3 w-3 shrink-0" />
            <span className="truncate">
              {property.city}, {property.country}
            </span>
          </div>
        </div>

        <div className="mt-3 flex items-center justify-between">
          <Badge variant="neutral" size="xs">
            {property.property_type}
          </Badge>
          <ChevronRight className="h-4 w-4 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
        </div>
      </Card>
    </Link>
  )
}

function ArchivedPropertyCard({
  property,
  onRestore,
  restoring,
}: {
  property: Property
  onRestore: () => void
  restoring: boolean
}) {
  return (
    <Card variant="default" padding="lg" className="opacity-60">
      <div className="flex items-start justify-between gap-3">
        <div
          className="h-11 w-11 shrink-0 overflow-hidden rounded-xl"
          style={{ background: 'hsl(36, 78%, 52% / 0.10)' }}
        >
          {property.photo_url ? (
            <img
              src={property.photo_url}
              alt={property.name}
              className="h-full w-full object-cover grayscale"
            />
          ) : (
            <div className="flex h-full w-full items-center justify-center">
              <Building2 className="h-5 w-5 text-muted-foreground" />
            </div>
          )}
        </div>
        <Badge variant="neutral" size="xs">archived</Badge>
      </div>
      <div className="mt-3">
        <p className="truncate font-semibold text-foreground">{property.name}</p>
        <div className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
          <MapPin className="h-3 w-3 shrink-0" />
          <span className="truncate">{property.city}, {property.country}</span>
        </div>
      </div>
      <div className="mt-3">
        <Button variant="ghost" size="sm" className="w-full" loading={restoring} onClick={onRestore}>
          <ArchiveRestore className="h-3.5 w-3.5" />
          Restore
        </Button>
      </div>
    </Card>
  )
}
