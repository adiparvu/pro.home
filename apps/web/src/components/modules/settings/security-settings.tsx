'use client'

import * as React from 'react'
import { useRouter } from 'next/navigation'
import { Shield, KeyRound, LogOut } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'

interface SecuritySettingsProps {
  userId: string
}

export function SecuritySettings({ userId: _userId }: SecuritySettingsProps) {
  const router = useRouter()
  const [isSigningOut, setIsSigningOut] = React.useState(false)

  async function handleSignOut() {
    setIsSigningOut(true)
    const supabase = createClient()
    await supabase.auth.signOut()
    router.push('/login')
  }

  return (
    <div className="flex flex-col gap-6 max-w-lg">
      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <KeyRound className="h-4 w-4" />
            Change Password
          </CardTitle>
        </CardHeader>
        <CardContent>
          <form className="flex flex-col gap-4" onSubmit={(e) => e.preventDefault()}>
            <Input label="Current password" type="password" />
            <Input label="New password" type="password" />
            <Input label="Confirm new password" type="password" />
            <div className="flex justify-end">
              <Button type="submit" variant="primary" size="md">
                Update Password
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>

      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Shield className="h-4 w-4" />
            Two-Factor Authentication
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-foreground">Authenticator app</p>
              <p className="text-xs text-muted-foreground">Add an extra layer of security</p>
            </div>
            <Button variant="outline" size="sm" disabled>
              Coming Soon
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card variant="default" padding="lg">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <LogOut className="h-4 w-4" />
            Sessions
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-foreground">Sign out everywhere</p>
              <p className="text-xs text-muted-foreground">
                Sign out from all devices and sessions
              </p>
            </div>
            <Button
              variant="destructive"
              size="sm"
              loading={isSigningOut}
              onClick={handleSignOut}
            >
              Sign Out
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
