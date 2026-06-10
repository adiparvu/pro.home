// Generates icon-192.png and icon-512.png for the PWA manifest
// Run: node scripts/generate-icons.mjs

import sharp from 'sharp'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'

const __dir = dirname(fileURLToPath(import.meta.url))
const publicDir = join(__dir, '../apps/web/public')

function makeSvg(size) {
  const pad = Math.round(size * 0.18)
  const inner = size - pad * 2
  // Roof points
  const roofLeft  = `${pad},${pad + inner * 0.46}`
  const roofTip   = `${size / 2},${pad}`
  const roofRight = `${pad + inner},${pad + inner * 0.46}`
  // Wall rect
  const wallX = pad + inner * 0.12
  const wallY = pad + inner * 0.44
  const wallW = inner * 0.76
  const wallH = inner * 0.54
  // Door
  const doorW = inner * 0.22
  const doorH = inner * 0.34
  const doorX = size / 2 - doorW / 2
  const doorY = wallY + wallH - doorH

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0d1420"/>
      <stop offset="100%" stop-color="#0f1c30"/>
    </linearGradient>
    <linearGradient id="house" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#60a5fa"/>
      <stop offset="100%" stop-color="#3b82f6"/>
    </linearGradient>
  </defs>
  <!-- Background -->
  <rect width="${size}" height="${size}" rx="${size * 0.22}" fill="url(#bg)"/>
  <!-- Roof -->
  <polygon points="${roofLeft} ${roofTip} ${roofRight}" fill="url(#house)" opacity="0.95"/>
  <!-- Wall -->
  <rect x="${wallX}" y="${wallY}" width="${wallW}" height="${wallH}" rx="${inner * 0.04}" fill="url(#house)" opacity="0.85"/>
  <!-- Door -->
  <rect x="${doorX}" y="${doorY}" width="${doorW}" height="${doorH}" rx="${inner * 0.03}" fill="#0d1420" opacity="0.7"/>
</svg>`
}

async function generate(size, filename) {
  const svg = Buffer.from(makeSvg(size))
  await sharp(svg).png().toFile(join(publicDir, filename))
  console.log(`✓ ${filename} (${size}×${size})`)
}

await generate(192, 'icon-192.png')
await generate(512, 'icon-512.png')
console.log('Done.')
