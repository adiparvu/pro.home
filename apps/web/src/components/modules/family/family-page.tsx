'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { Users, Plus, Crown, Shield, UserX, Mail, Clock, Ban, Pencil, Check, X } from 'lucide-react'
import type { Property, PropertyMember, PropertyInvitation, UserRole } from '@/lib/supabase/types'
import { ROLE_LABELS } from '@/lib/supabase/types'
import { createClient } from '@/lib/supabase/client'
import { PageHeader } from '@/components/layout/page-header'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { toast } from '@/hooks/use-toast'
import { InviteMemberDialog } from './invite-member-dialog'

interface FamilyPageProps {
  property: Property
  members: PropertyMember[]
  pendingInvitations: PropertyInvitation[]
  currentUserId: string
  myMembership: PropertyMember | null
}

const ROLE_ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  owner: Crown,
  partner: Shield,
}

const CHANGEABLE_ROLES: UserRole[] = [
  'partner', 'family_adult', 'family_teen', 'family_child',
  'family_elderly', 'tenant', 'guest', 'service_provider',
]

export function FamilyPage({
  property,
  members: initialMembers,
  pendingInvitations: initialInvitations,
  currentUserId,
  myMembership,
}: FamilyPageProps) {
  const router = useRouter()
  const confirmDialog = useConfirm()
  const [inviteOpen, setInviteOpen] = React.useState(false)
  const [members, setMembers] = React.useState(initialMembers)
  const [invitations, setInvitations] = React.useState(initialInvitations)
  const canManageMembers = myMembership?.role === 'owner' || myMembership?.role === 'partner'

  const roleGroups = members.reduce<Record<string, PropertyMember[]>>((acc, m) => {
    const group = acc[m.role] ?? []
    group.push(m)
    acc[m.role] = group
    return acc
  }, {})

  async function handleRemove(memberId: string) {
    const ok = await confirmDialog({
      title: 'Remove this member?',
      description: 'They will lose access to this property.',
      confirmLabel: 'Remove',
      destructive: true,
    })
    if (!ok) return
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('property_members').update({ status: 'inactive' }).eq('id', memberId)
    toast.success('Member removed')
    setMembers((prev) => prev.filter((m) => m.id !== memberId))
    router.refresh()
  }

  async function handleRoleChange(memberId: string, newRole: UserRole) {
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('property_members').update({ role: newRole }).eq('id', memberId)
    if (!error) {
      setMembers((prev) => prev.map((m) => m.id === memberId ? { ...m, role: newRole } : m))
    }
  }

  async function handleNicknameChange(memberId: string, nickname: string) {
    const supabase = createClient()
    const trimmed = nickname.trim() || null
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { error } = await (supabase as any).from('property_members').update({ nickname: trimmed }).eq('id', memberId)
    if (!error) {
      setMembers((prev) => prev.map((m) => m.id === memberId ? { ...m, nickname: trimmed } : m))
    }
  }

  async function handleRevoke(invitationId: string) {
    const ok = await confirmDialog({
      title: 'Revoke this invitation?',
      confirmLabel: 'Revoke',
      destructive: true,
    })
    if (!ok) return
    const supabase = createClient()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await (supabase as any).from('property_invitations').update({ status: 'revoked' }).eq('id', invitationId)
    toast.success('Invitation revoked')
    setInvitations((prev) => prev.filter((inv) => inv.id !== invitationId))
  }

  return (
    <>
      <PageHeader title="Family" description={property.name} />

      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[88px] md:pb-6">
        {/* Summary */}
        <div className="glass-standard rounded-2xl p-4 flex items-center gap-4">
          <div
            className="flex h-12 w-12 items-center justify-center rounded-xl"
            style={{ background: 'hsl(340 68% 56% / 0.15)' }}
          >
            <Users className="h-6 w-6" style={{ color: 'hsl(340, 68%, 56%)' }} />
          </div>
          <div>
            <p className="text-2xl font-bold text-foreground">{members.length}</p>
            <p className="text-sm text-muted-foreground">
              {members.length === 1 ? 'member' : 'members'} in {property.name}
            </p>
          </div>
          {canManageMembers && (
            <Button variant="primary" size="sm" className="ml-auto" onClick={() => setInviteOpen(true)}>
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
              Members ({members.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-col divide-y divide-border/30">
              {members.map((member) => (
                <MemberRow
                  key={member.id}
                  member={member}
                  isCurrentUser={member.user_id === currentUserId}
                  canManage={canManageMembers && member.user_id !== currentUserId && member.role !== 'owner'}
                  onRemove={handleRemove}
                  onRoleChange={handleRoleChange}
                  onNicknameChange={handleNicknameChange}
                />
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Pending invitations */}
        {(invitations.length > 0 || canManageMembers) && invitations.length > 0 && (
          <Card variant="default" padding="md">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Mail className="h-4 w-4" />
                Pending Invitations ({invitations.length})
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex flex-col divide-y divide-border/30">
                {invitations.map((inv) => (
                  <InvitationRow
                    key={inv.id}
                    invitation={inv}
                    canManage={canManageMembers}
                    onRevoke={handleRevoke}
                  />
                ))}
              </div>
            </CardContent>
          </Card>
        )}

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
        propertyName={property.name}
        onInvited={(inv) => setInvitations((prev) => [inv, ...prev])}
      />
    </>
  )
}

function MemberRow({
  member,
  isCurrentUser,
  canManage,
  onRemove,
  onRoleChange,
  onNicknameChange,
}: {
  member: PropertyMember
  isCurrentUser: boolean
  canManage: boolean
  onRemove: (id: string) => void
  onRoleChange: (id: string, role: UserRole) => void
  onNicknameChange: (id: string, nickname: string) => void
}) {
  const [editingNickname, setEditingNickname] = React.useState(false)
  const [nicknameInput, setNicknameInput] = React.useState(member.nickname ?? '')
  const [editingRole, setEditingRole] = React.useState(false)

  const RoleIcon = ROLE_ICONS[member.role]
  const initials = (member.nickname ?? 'M').charAt(0).toUpperCase()

  function saveNickname() {
    onNicknameChange(member.id, nicknameInput)
    setEditingNickname(false)
  }

  function cancelNickname() {
    setNicknameInput(member.nickname ?? '')
    setEditingNickname(false)
  }

  return (
    <div className="flex items-center gap-3 py-3">
      <Avatar size="md"><AvatarFallback>{initials}</AvatarFallback></Avatar>

      <div className="flex-1 min-w-0">
        {/* Nickname row */}
        {editingNickname ? (
          <div className="flex items-center gap-1">
            <input
              autoFocus
              value={nicknameInput}
              onChange={(e) => setNicknameInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') saveNickname(); if (e.key === 'Escape') cancelNickname() }}
              className="h-7 w-full max-w-[140px] rounded-lg border border-border bg-glass-light px-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-primary/60"
              placeholder="Display name"
            />
            <button onClick={saveNickname} className="text-success hover:text-success/80 focus-ring rounded" aria-label="Save">
              <Check className="h-3.5 w-3.5" />
            </button>
            <button onClick={cancelNickname} className="text-muted-foreground hover:text-foreground focus-ring rounded" aria-label="Cancel">
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ) : (
          <div className="flex items-center gap-1.5 group/name">
            <p className="text-sm font-medium text-foreground truncate">
              {member.nickname ?? 'Member'}
              {isCurrentUser && <span className="ml-1 text-xs text-muted-foreground">(you)</span>}
            </p>
            {RoleIcon && <RoleIcon className="h-3.5 w-3.5 text-muted-foreground shrink-0" />}
            {canManage && (
              <button
                onClick={() => setEditingNickname(true)}
                className="opacity-0 group-hover/name:opacity-100 text-muted-foreground hover:text-foreground transition-opacity focus-ring rounded"
                aria-label="Edit name"
              >
                <Pencil className="h-3 w-3" />
              </button>
            )}
          </div>
        )}

        {/* Role row */}
        {canManage && editingRole ? (
          <div className="flex items-center gap-1 mt-0.5">
            <select
              autoFocus
              defaultValue={member.role}
              onChange={(e) => { onRoleChange(member.id, e.target.value as UserRole); setEditingRole(false) }}
              onBlur={() => setEditingRole(false)}
              className="h-6 rounded-md border border-border bg-glass-light px-1.5 text-xs text-foreground focus:outline-none focus:ring-1 focus:ring-primary/60"
            >
              {CHANGEABLE_ROLES.map((r) => (
                <option key={r} value={r}>{ROLE_LABELS[r]}</option>
              ))}
            </select>
          </div>
        ) : (
          <div className="flex items-center gap-1 group/role mt-0.5">
            <p className="text-xs text-muted-foreground">{ROLE_LABELS[member.role]}</p>
            {canManage && (
              <button
                onClick={() => setEditingRole(true)}
                className="opacity-0 group-hover/role:opacity-100 text-muted-foreground hover:text-foreground transition-opacity focus-ring rounded"
                aria-label="Change role"
              >
                <Pencil className="h-3 w-3" />
              </button>
            )}
          </div>
        )}
      </div>

      {canManage && !editingNickname && !editingRole && (
        <Button variant="ghost" size="icon-sm" aria-label="Remove member" onClick={() => onRemove(member.id)}>
          <UserX className="h-4 w-4 text-destructive" />
        </Button>
      )}
    </div>
  )
}

function InvitationRow({
  invitation,
  canManage,
  onRevoke,
}: {
  invitation: PropertyInvitation
  canManage: boolean
  onRevoke: (id: string) => void
}) {
  const expiresDate = new Date(invitation.expires_at)
  const daysLeft = Math.ceil((expiresDate.getTime() - Date.now()) / (1000 * 60 * 60 * 24))

  return (
    <div className="flex items-center gap-3 py-3">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl glass-standard">
        <Mail className="h-4 w-4 text-muted-foreground" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-foreground truncate">{invitation.email}</p>
        <div className="flex items-center gap-2 mt-0.5">
          <Badge variant="neutral" size="xs">{ROLE_LABELS[invitation.role]}</Badge>
          <span className="flex items-center gap-0.5 text-xs text-muted-foreground">
            <Clock className="h-3 w-3" />
            {daysLeft}d left
          </span>
        </div>
      </div>
      {canManage && (
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label="Revoke invitation"
          onClick={() => onRevoke(invitation.id)}
        >
          <Ban className="h-4 w-4 text-destructive" />
        </Button>
      )}
    </div>
  )
}
