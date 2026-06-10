import { type Metadata } from 'next'
import { notFound, redirect } from 'next/navigation'
import Link from 'next/link'
import { Building2, CheckCircle, XCircle, Clock } from 'lucide-react'
import { createClient } from '@/lib/supabase/server'
import type { PropertyInvitation } from '@/lib/supabase/types'
import { ROLE_LABELS } from '@/lib/supabase/types'
import { Providers } from '@/components/layout/providers'
import { Button } from '@/components/ui/button'

export const metadata: Metadata = { title: 'You\'ve been invited' }

interface Props { params: Promise<{ token: string }> }

async function acceptInvite(invitationId: string, propertyId: string, role: string) {
  'use server'
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any).from('property_members').insert({
    property_id: propertyId,
    user_id: user.id,
    role,
    status: 'active',
    nickname: null,
    color: null,
    permissions: {},
    invited_by: null,
    joined_at: new Date().toISOString(),
  })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any)
    .from('property_invitations')
    .update({ status: 'accepted', accepted_at: new Date().toISOString() })
    .eq('id', invitationId)

  redirect('/')
}

async function declineInvite(invitationId: string) {
  'use server'
  const supabase = await createClient()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (supabase as any)
    .from('property_invitations')
    .update({ status: 'declined' })
    .eq('id', invitationId)
  redirect('/')
}

export default async function InvitePage({ params }: Props) {
  const { token } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: invitation } = await (supabase as any)
    .from('property_invitations')
    .select('*, properties(name, city, country, property_type, photo_url)')
    .eq('token', token)
    .single() as { data: (PropertyInvitation & { properties: { name: string; city: string; country: string; property_type: string; photo_url: string | null } | null }) | null; error: unknown }

  if (!invitation) notFound()

  const isExpired = new Date(invitation.expires_at) < new Date()
  const isAlreadyUsed = invitation.status !== 'pending'
  const property = invitation.properties

  return (
    <Providers>
      <div className="relative min-h-dvh overflow-hidden">
        <div className="absolute inset-0 lpbe-bg" aria-hidden="true" />
        <div className="absolute inset-0 bg-black/20" aria-hidden="true" />
        <div className="relative z-10 flex min-h-dvh flex-col items-center justify-center px-4 py-12">
          <div className="w-full max-w-sm">
            {/* Card */}
            <div className="glass-heavy rounded-3xl border border-white/10 p-6 flex flex-col gap-6">
              {/* Property icon */}
              <div className="flex flex-col items-center gap-3 text-center">
                {property?.photo_url ? (
                  <img
                    src={property.photo_url}
                    alt={property.name}
                    className="h-20 w-20 rounded-2xl object-cover border border-white/10"
                  />
                ) : (
                  <div className="flex h-20 w-20 items-center justify-center rounded-2xl glass-standard">
                    <Building2 className="h-10 w-10 text-muted-foreground" />
                  </div>
                )}
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                    You&apos;ve been invited to
                  </p>
                  <h1 className="mt-1 text-xl font-bold text-foreground">{property?.name ?? 'a property'}</h1>
                  {property && (
                    <p className="text-sm text-muted-foreground">{property.city}, {property.country}</p>
                  )}
                </div>
              </div>

              {/* Role pill */}
              <div className="flex justify-center">
                <div className="rounded-full glass-standard border border-white/10 px-4 py-1.5">
                  <p className="text-sm font-medium text-foreground">
                    Role: <span className="text-primary">{ROLE_LABELS[invitation.role]}</span>
                  </p>
                </div>
              </div>

              {/* Personal message */}
              {invitation.message && (
                <div className="rounded-xl glass-light border border-white/10 px-4 py-3">
                  <p className="text-xs text-muted-foreground mb-1">Message from inviter</p>
                  <p className="text-sm text-foreground italic">&ldquo;{invitation.message}&rdquo;</p>
                </div>
              )}

              {/* State: expired */}
              {(isExpired || isAlreadyUsed) && (
                <div className="flex flex-col items-center gap-2 py-2 text-center">
                  {isAlreadyUsed && invitation.status === 'accepted' ? (
                    <>
                      <CheckCircle className="h-8 w-8 text-success" />
                      <p className="text-sm font-medium text-foreground">Already accepted</p>
                      <p className="text-xs text-muted-foreground">This invitation has already been used.</p>
                    </>
                  ) : (
                    <>
                      <Clock className="h-8 w-8 text-muted-foreground" />
                      <p className="text-sm font-medium text-foreground">
                        {isExpired ? 'Invitation expired' : 'Invitation no longer valid'}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Ask the property owner to send a new invitation.
                      </p>
                    </>
                  )}
                  <Link href="/" className="mt-2 text-sm text-primary hover:underline">
                    Go to dashboard
                  </Link>
                </div>
              )}

              {/* State: valid — not logged in */}
              {!isExpired && !isAlreadyUsed && !user && (
                <div className="flex flex-col gap-3">
                  <p className="text-center text-sm text-muted-foreground">
                    Sign in or create an account to accept this invitation.
                  </p>
                  <Button asChild variant="primary" size="lg" fullWidth>
                    <Link href={`/login?redirectTo=/invite/${token}`}>Sign in to accept</Link>
                  </Button>
                  <Button asChild variant="ghost" size="lg" fullWidth>
                    <Link href={`/register?redirectTo=/invite/${token}`}>Create an account</Link>
                  </Button>
                </div>
              )}

              {/* State: valid — logged in */}
              {!isExpired && !isAlreadyUsed && user && (
                <div className="flex flex-col gap-2">
                  <p className="text-center text-xs text-muted-foreground">
                    Signed in as <span className="text-foreground">{user.email}</span>
                  </p>
                  <form action={acceptInvite.bind(null, invitation.id, invitation.property_id, invitation.role)}>
                    <Button type="submit" variant="primary" size="lg" fullWidth>
                      <CheckCircle className="h-4 w-4" />
                      Accept invitation
                    </Button>
                  </form>
                  <form action={declineInvite.bind(null, invitation.id)}>
                    <Button type="submit" variant="ghost" size="lg" fullWidth>
                      <XCircle className="h-4 w-4" />
                      Decline
                    </Button>
                  </form>
                </div>
              )}
            </div>

            <p className="mt-6 text-center text-xs text-white/50">PRV HOUSE — Property Operating System</p>
          </div>
        </div>
      </div>
    </Providers>
  )
}
