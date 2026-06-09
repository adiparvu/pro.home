'use client'

import Link from 'next/link'
import { Building2, MapPin, ChevronRight, Plus } from 'lucide-react'
import type { Property } from '@/lib/supabase/types'
import { Card } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'

interface PropertyListProps {
  properties: Property[]
}

export function PropertyList({ properties }: PropertyListProps) {
  if (properties.length === 0) {
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
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      {properties.map((property) => (
        <PropertyCard key={property.id} property={property} />
      ))}
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
      <Card
        variant="default"
        hover
        padding="lg"
        moduleColor="property"
        className="group"
      >
        <div className="flex items-start justify-between gap-3">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl"
            style={{ background: 'hsl(36, 78%, 52% / 0.15)' }}>
            <Building2 className="h-5 w-5" style={{ color: 'hsl(36, 78%, 52%)' }} />
          </div>
          {property.health_score !== null && (
            <Badge variant={healthColor} size="sm">
              {property.health_score}%
            </Badge>
          )}
        </div>

        <div className="mt-3">
          <p className="font-semibold text-foreground truncate">{property.name}</p>
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
