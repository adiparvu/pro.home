'use client'

import * as React from 'react'
import { Loader2, CheckCircle2, MessageSquare } from 'lucide-react'

interface TenantPortalPublicPageProps {
  portalId: string
  propertyId: string
  portalLabel: string
  propertyName: string
}

const CATEGORIES = ['maintenance', 'noise', 'billing', 'access', 'other']
const PRIORITIES = ['low', 'medium', 'high', 'urgent']

const inputCls = `
  w-full rounded-xl border border-gray-200 bg-white px-3 py-2.5 text-sm
  focus:outline-none focus:ring-2 focus:ring-blue-500/30 focus:border-blue-400
  transition-colors
`.trim()

const selectCls = `
  w-full rounded-xl border border-gray-200 bg-white px-3 py-2.5 text-sm
  focus:outline-none focus:ring-2 focus:ring-blue-500/30 focus:border-blue-400
  transition-colors appearance-none
`.trim()

export function TenantPortalPublicPage({ portalId, propertyId, portalLabel, propertyName }: TenantPortalPublicPageProps) {
  const [submitted, setSubmitted] = React.useState(false)
  const [submitting, setSubmitting] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  const [tenantName, setTenantName] = React.useState('')
  const [tenantEmail, setTenantEmail] = React.useState('')
  const [title, setTitle] = React.useState('')
  const [description, setDescription] = React.useState('')
  const [category, setCategory] = React.useState('other')
  const [priority, setPriority] = React.useState('medium')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!tenantName.trim() || !title.trim()) return
    setSubmitting(true)
    setError(null)
    try {
      const res = await fetch('/api/tenant-portal/submit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          portal_id: portalId,
          property_id: propertyId,
          tenant_name: tenantName.trim(),
          tenant_email: tenantEmail.trim() || null,
          title: title.trim(),
          description: description.trim() || null,
          category,
          priority,
        }),
      })
      const json = await res.json() as { success?: boolean; error?: string }
      if (!res.ok || !json.success) {
        setError(json.error ?? 'Something went wrong. Please try again.')
        return
      }
      setSubmitted(true)
    } catch (err) {
      setError(String(err))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div style={{
      minHeight: '100dvh',
      background: '#f9fafb',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      padding: '24px 16px 48px',
    }}>
      {/* Brand header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '24px' }}>
        <div style={{
          width: 40, height: 40, borderRadius: 10,
          background: '#0D1420', display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="22" height="22" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
            <path fillRule="evenodd" fill="white" d="M18 10 h28 v80 h-28 Z M46 10 L68 10 Q90 10 90 33 Q90 56 68 56 L46 56 Z M46 26 L65 26 Q74 26 74 33 Q74 40 65 40 L46 40 Z"/>
          </svg>
        </div>
        <div>
          <p style={{ margin: 0, fontSize: '13px', fontWeight: 700, color: '#0D1420', letterSpacing: '0.05em' }}>PRV HOUSE</p>
          <p style={{ margin: 0, fontSize: '10px', color: '#6b7280', letterSpacing: '0.1em', textTransform: 'uppercase' }}>Tenant Portal</p>
        </div>
      </div>

      <div style={{
        width: '100%', maxWidth: '520px',
        background: 'white',
        borderRadius: '20px',
        border: '1px solid #e5e7eb',
        overflow: 'hidden',
        boxShadow: '0 1px 3px rgba(0,0,0,0.06), 0 4px 16px rgba(0,0,0,0.06)',
      }}>
        {/* Header */}
        <div style={{
          background: '#1e3a5f',
          padding: '20px 24px',
          display: 'flex',
          alignItems: 'flex-start',
          gap: '14px',
        }}>
          <div style={{
            width: 44, height: 44, borderRadius: 12,
            background: 'rgba(255,255,255,0.15)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            <MessageSquare style={{ width: 22, height: 22, color: 'rgba(255,255,255,0.9)' }} />
          </div>
          <div>
            <p style={{ margin: 0, fontSize: '18px', fontWeight: 700, color: 'white' }}>{portalLabel}</p>
            <p style={{ margin: '4px 0 0', fontSize: '13px', color: 'rgba(255,255,255,0.65)' }}>{propertyName}</p>
          </div>
        </div>

        {submitted ? (
          <div style={{ padding: '40px 24px', textAlign: 'center' }}>
            <CheckCircle2 style={{ width: 48, height: 48, color: '#16a34a', margin: '0 auto 16px' }} />
            <p style={{ margin: '0 0 8px', fontSize: '16px', fontWeight: 600, color: '#111827' }}>
              Request submitted
            </p>
            <p style={{ margin: 0, fontSize: '13px', color: '#6b7280' }}>
              {`We'll be in touch soon.`}
            </p>
          </div>
        ) : (
          <form onSubmit={handleSubmit} style={{ padding: '24px' }}>
            <p style={{ margin: '0 0 20px', fontSize: '13px', color: '#6b7280' }}>
              Submit a request to the property manager. Fields marked * are required.
            </p>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 500, color: '#6b7280', marginBottom: '6px' }}>
                  Your name *
                </label>
                <input
                  className={inputCls}
                  placeholder="Full name"
                  value={tenantName}
                  onChange={(e) => setTenantName(e.target.value)}
                  required
                />
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 500, color: '#6b7280', marginBottom: '6px' }}>
                  Email address
                </label>
                <input
                  className={inputCls}
                  type="email"
                  placeholder="your@email.com"
                  value={tenantEmail}
                  onChange={(e) => setTenantEmail(e.target.value)}
                />
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 500, color: '#6b7280', marginBottom: '6px' }}>
                  Subject *
                </label>
                <input
                  className={inputCls}
                  placeholder="Brief description of the issue"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  required
                />
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 500, color: '#6b7280', marginBottom: '6px' }}>
                  Details
                </label>
                <textarea
                  className={inputCls}
                  placeholder="Provide more details about your request…"
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  rows={4}
                  style={{ resize: 'none' }}
                />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 500, color: '#6b7280', marginBottom: '6px' }}>
                    Category
                  </label>
                  <select
                    className={selectCls}
                    value={category}
                    onChange={(e) => setCategory(e.target.value)}
                  >
                    {CATEGORIES.map((c) => (
                      <option key={c} value={c}>{c.charAt(0).toUpperCase() + c.slice(1)}</option>
                    ))}
                  </select>
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 500, color: '#6b7280', marginBottom: '6px' }}>
                    Priority
                  </label>
                  <select
                    className={selectCls}
                    value={priority}
                    onChange={(e) => setPriority(e.target.value)}
                  >
                    {PRIORITIES.map((p) => (
                      <option key={p} value={p}>{p.charAt(0).toUpperCase() + p.slice(1)}</option>
                    ))}
                  </select>
                </div>
              </div>
            </div>

            {error && (
              <div style={{
                marginTop: '16px', padding: '12px', borderRadius: '10px',
                background: '#fef2f2', border: '1px solid #fecaca',
              }}>
                <p style={{ margin: 0, fontSize: '13px', color: '#dc2626' }}>{error}</p>
              </div>
            )}

            <button
              type="submit"
              disabled={submitting}
              style={{
                marginTop: '20px',
                width: '100%',
                padding: '12px',
                borderRadius: '12px',
                background: submitting ? '#93c5fd' : '#1e40af',
                color: 'white',
                fontSize: '14px',
                fontWeight: 600,
                border: 'none',
                cursor: submitting ? 'not-allowed' : 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '8px',
                transition: 'background 0.15s',
              }}
            >
              {submitting && <Loader2 style={{ width: 16, height: 16, animation: 'spin 1s linear infinite' }} />}
              {submitting ? 'Submitting…' : 'Submit Request'}
            </button>
          </form>
        )}

        <div style={{
          background: '#f9fafb', borderTop: '1px solid #e5e7eb',
          padding: '12px 24px', textAlign: 'center',
        }}>
          <p style={{ margin: 0, fontSize: '11px', color: '#9ca3af' }}>PRV HOUSE · Tenant Portal</p>
        </div>
      </div>
    </div>
  )
}
