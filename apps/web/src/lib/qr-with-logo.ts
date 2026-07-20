import QRCode from 'qrcode'

// PRVIO "P" letterform in a white rounded square, centered at (cx, cy)
function prvLogoOverlay(cx: number, cy: number, pixelSize: number, dark: string): string {
  const half = pixelSize / 2
  // In a 100-unit viewBox: stem at x=18..46, bowl outer M46,10→M46,56 curving through x=90
  // counter cutout M46,26→M46,40 curving through x=74
  return `<svg xmlns="http://www.w3.org/2000/svg" x="${cx - half}" y="${cy - half}" width="${pixelSize}" height="${pixelSize}" viewBox="0 0 100 100">
  <rect width="100" height="100" rx="18" fill="white"/>
  <path fill-rule="evenodd" fill="${dark}" d="M18 10 h28 v80 h-28 Z M46 10 L68 10 Q90 10 90 33 Q90 56 68 56 L46 56 Z M46 26 L65 26 Q74 26 74 33 Q74 40 65 40 L46 40 Z"/>
</svg>`
}

export async function qrWithLogo(
  url: string,
  options: { width?: number; margin?: number; dark?: string; light?: string } = {},
): Promise<string> {
  const width = options.width ?? 200
  const dark = options.dark ?? '#1a1a2e'
  const light = options.light ?? '#ffffff'

  const svgStr = await QRCode.toString(url, {
    type: 'svg',
    width,
    margin: options.margin ?? 2,
    // High error correction (30% data recovery) is required to cover the center logo
    errorCorrectionLevel: 'H',
    color: { dark, light },
  })

  const logoSize = Math.round(width * 0.22)
  const center = Math.round(width / 2)
  const overlay = prvLogoOverlay(center, center, logoSize, dark)

  return svgStr.replace('</svg>', `${overlay}</svg>`)
}
