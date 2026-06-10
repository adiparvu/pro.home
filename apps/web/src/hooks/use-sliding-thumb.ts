'use client'

import * as React from 'react'

/**
 * Measures the active item inside a container and returns the geometry for
 * an animated sliding thumb/pill. Shared by SegmentedControl and the
 * floating tab bar so the active-state mechanic is identical everywhere.
 */
export function useSlidingThumb<T extends string>(value: T, deps: React.DependencyList = []) {
  const containerRef = React.useRef<HTMLDivElement>(null)
  const itemRefs = React.useRef(new Map<T, HTMLElement>())
  const [thumb, setThumb] = React.useState<{ left: number; width: number } | null>(null)

  const measure = React.useCallback(() => {
    const el = itemRefs.current.get(value)
    const container = containerRef.current
    if (!el || !container) return
    const cRect = container.getBoundingClientRect()
    const rect = el.getBoundingClientRect()
    setThumb({ left: rect.left - cRect.left, width: rect.width })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, ...deps])

  React.useLayoutEffect(() => {
    measure()
  }, [measure])

  React.useEffect(() => {
    window.addEventListener('resize', measure)
    return () => window.removeEventListener('resize', measure)
  }, [measure])

  const setItemRef = React.useCallback((key: T) => (el: HTMLElement | null) => {
    if (el) itemRefs.current.set(key, el)
    else itemRefs.current.delete(key)
  }, [])

  return { containerRef, setItemRef, thumb }
}
