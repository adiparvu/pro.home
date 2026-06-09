import Link from 'next/link'
import { Building2, Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'

export function NoPropertyState() {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-4 py-12">
      <Card variant="heavy" padding="xl" className="w-full max-w-sm text-center">
        <div className="flex flex-col items-center gap-4">
          <div className="flex h-16 w-16 items-center justify-center rounded-3xl bg-primary/20">
            <Building2 className="h-8 w-8 text-primary" />
          </div>

          <div className="flex flex-col gap-2">
            <h2 className="text-xl font-semibold">Add Your First Property</h2>
            <p className="text-sm text-muted-foreground text-balance">
              Start managing your home with PRV HOUSE. Add your property to unlock all features.
            </p>
          </div>

          <Link href="/property/new" className="w-full">
            <Button fullWidth size="lg" leftIcon={<Plus className="h-4 w-4" />}>
              Add Property
            </Button>
          </Link>
        </div>
      </Card>
    </div>
  )
}
