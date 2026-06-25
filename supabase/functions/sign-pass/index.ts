// sign-pass — creates and returns a signed .pkpass bundle for an NFC tag
//
// Required Supabase secrets (set via: supabase secrets set KEY=value):
//   PASS_CERT_P12_BASE64   — base64-encoded Pass Type ID .p12 certificate
//   PASS_CERT_PASSWORD     — password for the .p12 (empty string if none)
//   PASS_WWDR_CERT_BASE64  — base64-encoded Apple WWDR intermediate cert (.cer, DER format)
//
// Pass Type ID to register in Apple Developer portal: pass.com.prvio.app.nfctag

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
// @ts-ignore
import forge from "npm:node-forge@1.3.1"
// @ts-ignore
import JSZip from "npm:jszip@3.10.1"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

const TEAM_ID      = Deno.env.get("PASS_TEAM_IDENTIFIER")  ?? "SU92TVZT8W"
const PASS_TYPE_ID = Deno.env.get("PASS_TYPE_IDENTIFIER")  ?? "pass.com.prvio.app.nfctag"

// 1×1 transparent PNG used as icon/logo placeholder
const ICON_B64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVQI12NgAAIABQAABjE+ibYAAAAASUVORK5CYII="
const iconBytes = Uint8Array.from(atob(ICON_B64), (c) => c.charCodeAt(0))

// SHA-1 hex of a Uint8Array or string
async function sha1hex(data: Uint8Array | string): Promise<string> {
  const buf = typeof data === "string" ? new TextEncoder().encode(data) : data
  const hash = await crypto.subtle.digest("SHA-1", buf)
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("")
}

function passBackgroundColor(linkedType: string): string {
  switch (linkedType) {
    case "zone":      return "rgb(30,80,200)"
    case "appliance": return "rgb(80,40,180)"
    case "element":   return "rgb(120,20,160)"
    default:          return "rgb(40,50,70)"
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS })
  }

  try {
    const { tagId, tagName, linkedType, linkedName, uid } = await req.json()

    // ----- Build pass.json -----
    const passJson = {
      formatVersion: 1,
      passTypeIdentifier: PASS_TYPE_ID,
      serialNumber: tagId ?? crypto.randomUUID(),
      teamIdentifier: TEAM_ID,
      organizationName: "PRVIO",
      description: tagName ?? "NFC Tag",
      foregroundColor: "rgb(255,255,255)",
      backgroundColor: passBackgroundColor(linkedType ?? "none"),
      labelColor: "rgb(180,180,180)",
      generic: {
        primaryFields: [
          { key: "name", label: "TAG", value: tagName ?? "NFC Tag" },
        ],
        secondaryFields: [
          {
            key: "linked",
            label: (linkedType ?? "none").toUpperCase(),
            value: linkedName && linkedName.trim() ? linkedName : "Standalone",
          },
        ],
        auxiliaryFields: [
          { key: "uid", label: "UID", value: (uid ?? "").substring(0, 16).toUpperCase() },
        ],
        backFields: [
          { key: "full_uid", label: "Full UID", value: uid ?? "" },
          { key: "app", label: "App", value: "PRVIO — Smart Home" },
        ],
      },
    }

    const passJsonStr = JSON.stringify(passJson)

    // ----- Check signing certs -----
    const certP12B64  = Deno.env.get("PASS_CERT_P12_BASE64")
    const certPass    = Deno.env.get("PASS_CERT_PASSWORD") ?? ""
    const wwdrB64     = Deno.env.get("PASS_WWDR_CERT_BASE64")

    if (!certP12B64 || !wwdrB64) {
      return new Response(
        JSON.stringify({ error: "Pass signing certificates not configured. Set PASS_CERT_P12_BASE64 and PASS_WWDR_CERT_BASE64 in Supabase secrets." }),
        { status: 503, headers: { ...CORS, "Content-Type": "application/json" } },
      )
    }

    // ----- Build manifest.json -----
    const files: Record<string, Uint8Array | string> = {
      "pass.json":  passJsonStr,
      "icon.png":   iconBytes,
      "icon@2x.png": iconBytes,
      "logo.png":   iconBytes,
      "logo@2x.png": iconBytes,
    }

    const manifest: Record<string, string> = {}
    for (const [name, content] of Object.entries(files)) {
      manifest[name] = await sha1hex(
        typeof content === "string" ? content : content,
      )
    }
    const manifestStr = JSON.stringify(manifest)

    // ----- Create PKCS#7 detached signature -----
    const p12Der    = atob(certP12B64)
    const p12Asn1   = forge.asn1.fromDer(p12Der)
    const p12       = forge.pkcs12.pkcs12FromAsn1(p12Asn1, certPass)

    const keyBags  = p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag })[forge.pki.oids.pkcs8ShroudedKeyBag] ?? []
    const certBags = p12.getBags({ bagType: forge.pki.oids.certBag })[forge.pki.oids.certBag] ?? []
    if (!keyBags.length || !certBags.length) throw new Error("Invalid P12: missing key or cert")

    const privateKey  = keyBags[0].key
    const certificate = certBags[0].cert

    const wwdrDer  = atob(wwdrB64)
    const wwdrAsn1 = forge.asn1.fromDer(wwdrDer)
    const wwdrCert = forge.pki.certificateFromAsn1(wwdrAsn1)

    const p7 = forge.pkcs7.createSignedData()
    p7.content = forge.util.createBuffer(manifestStr)
    p7.addCertificate(certificate)
    p7.addCertificate(wwdrCert)
    p7.addSigner({
      key: privateKey,
      certificate,
      digestAlgorithm: forge.pki.oids.sha1,
      authenticatedAttributes: [
        { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
        { type: forge.pki.oids.messageDigest },
        { type: forge.pki.oids.signingTime, value: new Date() },
      ],
    })
    p7.sign({ detached: true })

    const sigDer   = forge.asn1.toDer(p7.toAsn1()).getBytes()
    const sigBytes = Uint8Array.from(sigDer, (c: string) => c.charCodeAt(0))

    // ----- Pack .pkpass ZIP -----
    const zip = new JSZip()
    zip.file("pass.json",    passJsonStr)
    zip.file("manifest.json", manifestStr)
    zip.file("signature",    sigBytes)
    zip.file("icon.png",     iconBytes)
    zip.file("icon@2x.png",  iconBytes)
    zip.file("logo.png",     iconBytes)
    zip.file("logo@2x.png",  iconBytes)

    const zipData = await zip.generateAsync({ type: "uint8array" })

    return new Response(zipData, {
      headers: {
        ...CORS,
        "Content-Type": "application/vnd.apple.pkpass",
        "Content-Disposition": `attachment; filename="${tagId ?? "pass"}.pkpass"`,
      },
    })
  } catch (err) {
    console.error("sign-pass error:", err)
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    )
  }
})
