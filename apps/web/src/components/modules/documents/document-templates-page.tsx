'use client'

import * as React from 'react'
import { Receipt, ClipboardCheck, Wrench } from 'lucide-react'
import { PageHeader } from '@/components/layout/page-header'
import { Card } from '@/components/ui/card'
import type { Property } from '@/lib/supabase/types'

interface LeaseInfo {
  id: string
  monthly_rent: number
  currency: string | null
  status: string
  tenant_name: string | null
}

interface RentPayment {
  id: string
  lease_id: string
  amount: number
  currency: string | null
  month: string | null
  status: string | null
}

interface DocumentTemplatesPageProps {
  property: Property
  leases: LeaseInfo[]
  recentPayments: RentPayment[]
}

function TemplateCard({
  icon: Icon,
  iconColor,
  title,
  description,
  children,
}: {
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>
  iconColor: string
  title: string
  description: string
  children: React.ReactNode
}) {
  return (
    <Card className="p-4 flex flex-col gap-4">
      <div className="flex items-start gap-3">
        <div
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
          style={{ background: `${iconColor}22` }}
        >
          <Icon className="h-5 w-5" style={{ color: iconColor }} />
        </div>
        <div>
          <p className="text-sm font-semibold">{title}</p>
          <p className="text-xs text-muted-foreground mt-0.5">{description}</p>
        </div>
      </div>
      {children}
    </Card>
  )
}

function SelectField({
  label,
  value,
  onChange,
  options,
  placeholder,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  options: { value: string; label: string }[]
  placeholder?: string
}) {
  return (
    <div>
      <label className="text-xs text-muted-foreground block mb-1">{label}</label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
      >
        {placeholder && <option value="">{placeholder}</option>}
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </div>
  )
}

function InputField({
  label,
  type,
  value,
  onChange,
  placeholder,
}: {
  label: string
  type?: string
  value: string
  onChange: (v: string) => void
  placeholder?: string
}) {
  return (
    <div>
      <label className="text-xs text-muted-foreground block mb-1">{label}</label>
      <input
        type={type ?? 'text'}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
      />
    </div>
  )
}

function GenerateButton({
  disabled,
  onClick,
}: {
  disabled?: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="w-full rounded-lg bg-primary px-4 py-2.5 text-sm font-semibold text-white transition-opacity hover:opacity-90 active:scale-95 disabled:opacity-40 disabled:cursor-not-allowed"
    >
      Generate Document
    </button>
  )
}

export function DocumentTemplatesPage({
  property,
  leases,
  recentPayments,
}: DocumentTemplatesPageProps) {
  // ── Rent Receipt state ────────────────────────────────────────────────────
  const [receiptLeaseId, setReceiptLeaseId] = React.useState(leases[0]?.id ?? '')
  const [receiptMonth, setReceiptMonth] = React.useState(
    recentPayments[0]?.month ?? new Date().toISOString().slice(0, 7),
  )

  // ── Inspection Notice state ───────────────────────────────────────────────
  const [inspectionLeaseId, setInspectionLeaseId] = React.useState(leases[0]?.id ?? '')
  const [inspectionDate, setInspectionDate] = React.useState(
    new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0] ?? '',
  )

  // ── Maintenance Notice state ──────────────────────────────────────────────
  const [maintenanceDescription, setMaintenanceDescription] = React.useState('')
  const [maintenanceDate, setMaintenanceDate] = React.useState(
    new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString().split('T')[0] ?? '',
  )
  const [maintenanceLeaseId, setMaintenanceLeaseId] = React.useState(leases[0]?.id ?? '')

  const leaseOptions = leases.map((l) => ({
    value: l.id,
    label: l.tenant_name ? `${l.tenant_name} (${l.id.slice(0, 6)})` : l.id.slice(0, 8),
  }))

  // Build unique month options from recent payments
  const monthSet = new Set<string>()
  for (const p of recentPayments) {
    if (p.month) monthSet.add(p.month)
  }
  if (!monthSet.size) {
    // Fallback: last 6 months
    for (let i = 0; i < 6; i++) {
      const d = new Date()
      d.setMonth(d.getMonth() - i)
      monthSet.add(d.toISOString().slice(0, 7))
    }
  }
  const monthOptions = Array.from(monthSet).map((m) => {
    const [y, mo] = m.split('-')
    const label = new Date(parseInt(y ?? '2024'), parseInt(mo ?? '1') - 1, 1).toLocaleDateString('en', {
      month: 'long',
      year: 'numeric',
    })
    return { value: m, label }
  })

  function openReceipt() {
    if (!receiptLeaseId) return
    const url = `/api/reports/templates?type=rent_receipt&lease_id=${receiptLeaseId}&month=${receiptMonth}`
    window.open(url, '_blank')
  }

  function openInspection() {
    if (!inspectionLeaseId) return
    const url = `/api/reports/templates?type=inspection_notice&lease_id=${inspectionLeaseId}&date=${inspectionDate}`
    window.open(url, '_blank')
  }

  function openMaintenance() {
    if (!maintenanceDescription.trim()) return
    const url =
      `/api/reports/templates?type=maintenance_notice` +
      `&description=${encodeURIComponent(maintenanceDescription)}` +
      `&date=${maintenanceDate}` +
      (maintenanceLeaseId ? `&lease_id=${maintenanceLeaseId}` : '')
    window.open(url, '_blank')
  }

  const hasLeases = leases.length > 0

  return (
    <>
      <PageHeader title="Templates" description={property.name} backHref="/documents" />
      <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6">
        {!hasLeases && (
          <Card className="p-4">
            <p className="text-sm text-muted-foreground text-center">
              No active leases found. Add a lease to generate tenant documents.
            </p>
          </Card>
        )}

        {/* Rent Receipt */}
        <TemplateCard
          icon={Receipt}
          iconColor="hsl(152,62%,38%)"
          title="Rent Receipt"
          description="Generate a printable rent receipt for a specific month"
        >
          <div className="flex flex-col gap-3">
            <SelectField
              label="Lease / Tenant"
              value={receiptLeaseId}
              onChange={setReceiptLeaseId}
              options={leaseOptions}
              placeholder="Select lease"
            />
            <SelectField
              label="Month"
              value={receiptMonth}
              onChange={setReceiptMonth}
              options={monthOptions}
            />
            <GenerateButton disabled={!receiptLeaseId} onClick={openReceipt} />
          </div>
        </TemplateCard>

        {/* Inspection Notice */}
        <TemplateCard
          icon={ClipboardCheck}
          iconColor="hsl(210,75%,42%)"
          title="Inspection Notice"
          description="Send a formal notice of a scheduled property inspection"
        >
          <div className="flex flex-col gap-3">
            <SelectField
              label="Lease / Tenant"
              value={inspectionLeaseId}
              onChange={setInspectionLeaseId}
              options={leaseOptions}
              placeholder="Select lease"
            />
            <InputField
              label="Inspection date"
              type="date"
              value={inspectionDate}
              onChange={setInspectionDate}
            />
            <GenerateButton disabled={!inspectionLeaseId} onClick={openInspection} />
          </div>
        </TemplateCard>

        {/* Maintenance Notice */}
        <TemplateCard
          icon={Wrench}
          iconColor="hsl(22,68%,41%)"
          title="Maintenance Notice"
          description="Notify tenants of planned maintenance or repair work"
        >
          <div className="flex flex-col gap-3">
            {hasLeases && (
              <SelectField
                label="Lease / Tenant (optional)"
                value={maintenanceLeaseId}
                onChange={setMaintenanceLeaseId}
                options={leaseOptions}
                placeholder="Select lease (optional)"
              />
            )}
            <div>
              <label className="text-xs text-muted-foreground block mb-1">
                Work description
              </label>
              <textarea
                value={maintenanceDescription}
                onChange={(e) => setMaintenanceDescription(e.target.value)}
                placeholder="e.g. Boiler service and annual inspection"
                rows={3}
                className="w-full rounded-lg border border-border/50 bg-background px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40 resize-none"
              />
            </div>
            <InputField
              label="Scheduled date"
              type="date"
              value={maintenanceDate}
              onChange={setMaintenanceDate}
            />
            <GenerateButton
              disabled={!maintenanceDescription.trim()}
              onClick={openMaintenance}
            />
          </div>
        </TemplateCard>

        <p className="text-xs text-muted-foreground px-1">
          Documents open in a new tab as print-ready HTML. Use your browser&apos;s print function to save as PDF.
        </p>
      </div>
    </>
  )
}
