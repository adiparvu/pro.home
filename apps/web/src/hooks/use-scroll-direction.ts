'use client'

import * as React from 'react'

interface ScrollState {
  /** Floating chrome (tab bar, FAB) should be hidden */
  hidden: boolean
  /** Page is scrolled past the large-title collapse threshold */
  collapsed: boolean
}

const HIDE_DELTA = 12
const COLLAPSE_AT = 48
const NEAR_TOP = 80

/**
 * Shared scroll choreography for floating chrome. Hide on scroll-down,
 * spring back on scroll-up or near the top. Respects reduced motion by
 * still toggling state (consumers swap transforms for fades via CSS).
 */
export function useScrollDirection(): ScrollState {
  const [state, setState] = React.useState<ScrollState>({ hidden: false, collapsed: false })
  const lastY = React.useRef(0)

  React.useEffect(() => {
    lastY.current = window.scrollY
    let ticking = false

    function onScroll() {
      if (ticking) return
      ticking = true
      requestAnimationFrame(() => {
        const y = window.scrollY
        const delta = y - lastY.current
        setState((prev) => {
          const collapsed = y > COLLAPSE_AT
          let hidden = prev.hidden
          if (y < NEAR_TOP) hidden = false
          else if (delta > HIDE_DELTA) hidden = true
          else if (delta < -HIDE_DELTA) hidden = false
          if (hidden === prev.hidden && collapsed === prev.collapsed) return prev
          return { hidden, collapsed }
        })
        lastY.current = y
        ticking = false
      })
    }

    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return state
}
