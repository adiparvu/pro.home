'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { Users, Plus, Mail, Crown, Shield, UserX } from 'lucide-react'
import type { Property, PropertyMember } from '@/lib/supabase/types'
import { ROLE_LABELS } from '@/lib/supabase/types'
import { PageHeader } from '@/components/layout/page-header'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { InviteMemberDialog } from './invite-member-dialog'

interface FamilyPageProps {
  property: Property
  members: PropertyMember[]
  currentUserId: string
  myMembership: PropertyMember | null
}

const ROLE_ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  owner: Crown,
  partner: Shield,
}

export function FamilyPage({ property, members, currentUserId, myMembership }: FamilyPageProps) {
  const [inviteOpen, setInviteOpen] = React.useState(false)
  const canInvite =
    myMembership?.role === 'owner' || myMembership?.role === 'partner'

  const roleGroups = members.reduce<Record<string, PropertyMember[]>>((acc, m) => {
    const group = acc[m.role] ?? []
    group.push(m)
    acc[m.role] = group
    return acc
  }, {})

  return (
    <>
      <PageHeader
        title="Family"
        description={property.name}
        action={canInvite ? { label: 'Invite Member', href: '#' } : undefined}
      />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {/* Summary */}
        <div className="glass-standard rounded-2xl p-4 flex items-center gap-4">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl"
            style={{ background: 'hsl(340, 68%, 56% / 0.15)' }}>
            <Users className="h-6 w-6" style={{ color: 'hsl(340, 68%, 56%)' }} />
          </div>
          <div>
            <p className="text-2xl font-bold text-foreground">{members.length}</p>
            <p className="text-sm text-muted-foreground">
              {members.length === 1 ? 'member' : 'members'} in {property.name}
            </p>
          </div>
          {canInvite && (
            <Button
              variant="primary"
              size="sm"
              className="ml-auto"
              onClick={() => setInviteOpen(true)}
            >
              <Plus className="h-3.5 w-3.5" />
              Invite
            </Button>
          )}
        </div>

        {/* Member list */}
        <Card variant="default" padding="md">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Users className="h-4 w-4" />
              Members
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-col divide-y divide-border/30">
              {members.map((member) => (
                <MemberRow
                  key={member.id}
                  member={member}
                  isCurrentUser={member.user_id === currentUserId}
                  canManage={canInvite && member.user_id !== currentUserId && member.role !== 'owner'}
                />
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Role breakdown */}
        <Card variant="default" padding="md">
          <CardHeader>
            <CardTitle>Role Breakdown</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-col gap-2">
              {Object.entries(roleGroups).map(([role, roleMembers]) => (
                <div key={role} className="flex items-center justify-between py-1">
                  <span className="text-sm text-muted-foreground capitalize">
                    {ROLE_LABELS[role as keyof typeof ROLE_LABELS] ?? role}
                  </span>
                  <Badge variant="neutral" size="sm">{roleMembers.length}</Badge>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>

      <InviteMemberDialog
        open={inviteOpen}
        onClose={() => setInviteOpen(false)}
        propertyId={property.id}
      />
    </>
  )
}

function MemberRow({
  member,
  isCurrentUser,
  canManage,
}: {
  member: PropertyMember
  isCurrentUser: boolean
  canManage: boolean
}) {
  const RoleIcon = ROLE_ICONS[member.role]
  const initials = (member.nickname ?? 'M').charAt(0).toUpperCase()

  return (
    <div className="flex items-center gap-3 py-3">
      <Avatar size="md"><AvatarFallback>{initials}</AvatarFallback></Avatar>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          <p className="text-sm font-medium text-foreground truncate">
            {member.nickname ?? 'Member'}
            {isCurrentUser && (
              <span className="ml-1 text-xs text-muted-foreground">(you)</span>
            )}
          </p>
          {RoleIcon && <RoleIcon className="h-3.5 w-3.5 text-muted-foreground shrink-0" />}
        </div>
        <p className="text-xs text-muted-foreground">
          {ROLE_LABELS[member.role]}
        </p>
      </div>
      {canManage && (
        <Button variant="ghost" size="icon-sm" aria-label="Remove member">
          <UserX className="h-4 w-4 text-destructive" />
        </Button>
      )}
    </div>
  )
}
