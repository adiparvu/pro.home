import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

// Tool definitions for Claude
const tools = [
  {
    name: "create_task",
    description: "Create a new maintenance task for the property. Use when the user wants to add, schedule, or track a maintenance job.",
    input_schema: {
      type: "object",
      properties: {
        name: {
          type: "string",
          description: "The title or name of the task",
        },
        description: {
          type: "string",
          description: "Optional detailed description of the task",
        },
        due_date: {
          type: "string",
          description: "Optional due date in YYYY-MM-DD format",
        },
      },
      required: ["name"],
    },
  },
  {
    name: "mark_plant_watered",
    description: "Mark a plant as watered. Use when the user mentions watering a plant or updating a plant's care status.",
    input_schema: {
      type: "object",
      properties: {
        plant_name: {
          type: "string",
          description: "The name of the plant to mark as watered",
        },
      },
      required: ["plant_name"],
    },
  },
  {
    name: "query_twin_health",
    description: "Get a summary of the property's digital twin health score and status. Use when the user asks about property health, condition, or overall status.",
    input_schema: {
      type: "object",
      properties: {},
      required: [],
    },
  },
  {
    name: "add_appliance",
    description: "Add a new appliance or home equipment record to the property. Use when the user mentions a specific appliance, device, or equipment (boiler, fridge, washing machine, air conditioner, etc.) they want to register or track.",
    input_schema: {
      type: "object",
      properties: {
        name: {
          type: "string",
          description: "Name of the appliance or equipment",
        },
        brand: {
          type: "string",
          description: "Optional brand or manufacturer name",
        },
        category: {
          type: "string",
          description: "Category: hvac, kitchen, laundry, bathroom, security, entertainment, or other",
        },
        location: {
          type: "string",
          description: "Optional location in the property (e.g. 'kitchen', 'basement')",
        },
        notes: {
          type: "string",
          description: "Optional notes about the appliance",
        },
      },
      required: ["name"],
    },
  },
  {
    name: "schedule_maintenance",
    description: "Schedule a maintenance task for a specific property element or appliance. Use when the user wants to plan or set a reminder for a maintenance job with a specific timeframe.",
    input_schema: {
      type: "object",
      properties: {
        name: {
          type: "string",
          description: "Short title of the maintenance task",
        },
        description: {
          type: "string",
          description: "Detailed description of what needs to be done",
        },
        due_date: {
          type: "string",
          description: "Optional due date in YYYY-MM-DD format",
        },
      },
      required: ["name"],
    },
  },
]

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })

  try {
    const authHeader = req.headers.get("Authorization") ?? ""
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: cors })
    }

    const body = await req.json()
    // iOS client sends snake_case; accept both for compatibility
    const message: string = body.message
    const propertyId: string | undefined = body.propertyId ?? body.property_id
    const language: string | undefined = body.language
    const tone: string | undefined = body.tone
    const assistantName: string = (body.assistant_name ?? "ARIA").toString().slice(0, 40) || "ARIA"
    // "What ARIA can see" switches (iOS AI Settings). Default true so older
    // clients keep full context; `false` means the domain is never loaded,
    // never mentioned, and its tools are never offered.
    const allowTasks: boolean = body.allow_tasks !== false
    const allowFinances: boolean = body.allow_finances !== false
    const allowProperty: boolean = body.allow_property !== false
    const allowFamily: boolean = body.allow_family !== false
    const allowPlants: boolean = body.allow_plants !== false

    // ── D3 Document Smart Scan: structured extraction mode ──────────────────
    // The Document Vault sends OCR text here for strict-JSON extraction plus a
    // long-contract summary. It reuses this already-verified function + model
    // (Claude Haiku 4.5, text) but deliberately skips conversation history,
    // tools and message persistence — a clean, self-contained call that returns
    // machine-readable data instead of chat. The model is instructed to emit
    // null (never invent) so the iOS client can present every value as an
    // editable, confirm-before-save suggestion.
    if ((body.mode as string | undefined) === "extract") {
      const apiKey = Deno.env.get("ANTHROPIC_API_KEY")
      if (!apiKey) {
        return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }),
          { status: 500, headers: { ...cors, "Content-Type": "application/json" } })
      }
      const ocr = ((body.ocr_text ?? body.message) as string | undefined)?.toString().slice(0, 8000) ?? ""
      if (!ocr.trim()) {
        return new Response(JSON.stringify({ error: "Empty OCR text" }),
          { status: 400, headers: { ...cors, "Content-Type": "application/json" } })
      }
      const lang = (body.language as string | undefined) ?? "ro"
      const catHint = (body.category_hint as string | undefined) ?? null

      const extractSystem = `You are a precise document data-extraction engine for a Romanian/EU home-management app.
Given raw OCR text from a scanned document (contract, invoice, insurance policy, warranty, utility bill, certificate…), extract structured fields and — for long contracts — a short plain-language summary.
Respond with ONLY one JSON object. No prose, no markdown code fences.
Schema (use null for anything not clearly present; NEVER invent a value):
{
  "document_type": string|null,
  "category": one of ["contract","legal","warranty","insurance","certificate","manual","invoice","permit","tax","utility","photo","other"]|null,
  "issuer": string|null,
  "holder": string|null,
  "contract_code": string|null, "series": string|null, "policy_number": string|null,
  "client_code": string|null, "client_number": string|null, "doc_number": string|null, "fiscal_code": string|null,
  "issued_at": "YYYY-MM-DD"|null, "expires_at": "YYYY-MM-DD"|null, "renew_at": "YYYY-MM-DD"|null,
  "value": number|null, "currency": "RON"|"EUR"|"USD"|"GBP"|null, "vat": number|null,
  "summary": string|null,
  "confidence": number
}
"summary": 2-4 sentences covering duration, obligations, costs and key clauses — null when the document is short/simple.
Dates as ISO YYYY-MM-DD. Amounts as plain numbers (no thousands separators). Write "document_type" and "summary" in language: ${lang}.`

      const userMsg = `${catHint ? `The user tentatively categorised this as "${catHint}".\n` : ""}OCR TEXT:\n${ocr}`

      const claudeRes = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({
          model: "claude-haiku-4-5-20251001",
          max_tokens: 1500,
          system: extractSystem,
          messages: [{ role: "user", content: userMsg }],
        }),
      })
      if (!claudeRes.ok) {
        const errText = await claudeRes.text()
        return new Response(JSON.stringify({ error: `Claude API ${claudeRes.status}: ${errText}` }),
          { status: 502, headers: { ...cors, "Content-Type": "application/json" } })
      }
      const claudeData = await claudeRes.json()
      const rawText: string =
        (claudeData.content ?? []).find((b: { type: string }) => b.type === "text")?.text ?? ""

      // Locate the JSON object in the reply and parse it server-side.
      let extraction: Record<string, unknown> | null = null
      const jsonStart = rawText.indexOf("{")
      const jsonEnd = rawText.lastIndexOf("}")
      if (jsonStart !== -1 && jsonEnd > jsonStart) {
        try { extraction = JSON.parse(rawText.slice(jsonStart, jsonEnd + 1)) } catch { extraction = null }
      }
      if (!extraction) {
        // Hand the raw text back so the client can attempt its own tolerant parse.
        return new Response(JSON.stringify({ raw: rawText }),
          { headers: { ...cors, "Content-Type": "application/json" } })
      }
      return new Response(
        JSON.stringify({ extraction, summary: extraction.summary ?? null, raw: rawText }),
        { headers: { ...cors, "Content-Type": "application/json" } }
      )
    }

    if (!message?.trim()) {
      return new Response(JSON.stringify({ error: "Empty message" }), { status: 400, headers: cors })
    }

    // Load recent conversation history (last 10 pairs)
    const { data: history } = await supabase
      .from("aria_messages")
      .select("role, content")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(20)

    // Load property context — each domain is loaded ONLY when its "What ARIA
    // can see" switch is on. A disabled domain never reaches the model.
    const none = Promise.resolve({ data: null })
    const [tasksRes, finRes, propRes, docsRes, delivRes, famRes, plantsRes] = await Promise.all([
      allowTasks
        ? supabase
            .from("maintenance_tasks")
            .select("title, status, priority, due_date")
            .in("status", ["pending", "in_progress", "overdue"])
            .order("due_date", { ascending: true })
            .limit(5)
        : none,
      allowFinances
        ? supabase
            .from("financial_records")
            .select("type, amount, currency, title, date")
            .gte("date", new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split("T")[0])
            .order("date", { ascending: false })
            .limit(8)
        : none,
      allowProperty && propertyId
        ? supabase.from("properties").select("name, address_line1, city, health_score").eq("id", propertyId).single()
        : none,
      supabase
        .from("documents")
        .select("name, expires_at")
        .not("expires_at", "is", null)
        .lte("expires_at", new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().split("T")[0])
        .gte("expires_at", new Date().toISOString().split("T")[0])
        .limit(5),
      supabase
        .from("packages")
        .select("title, status, expected_date")
        .in("status", ["expected", "out_for_delivery"])
        .limit(5),
      allowFamily
        ? supabase.from("family_members").select("name, role").limit(10)
        : none,
      allowPlants
        ? supabase
            .from("plants")
            .select("name, last_watered_at, watering_interval_days, health_status")
            .limit(10)
        : none,
    ])

    const tasks = tasksRes.data ?? []
    const financials = finRes.data ?? []
    const property = propRes.data as { name?: string; address_line1?: string; city?: string; health_score?: number } | null
    const expiringDocs = (docsRes?.data ?? []) as Array<{ name: string; expires_at: string }>
    const deliveries = (delivRes?.data ?? []) as Array<{ title: string; status: string; expected_date?: string }>
    const familyMembers = (famRes?.data ?? []) as Array<{ name: string; role?: string }>
    const plants = (plantsRes?.data ?? []) as Array<{ name: string; last_watered_at?: string; watering_interval_days?: number; health_status?: string }>

    const taskCtx = tasks.length > 0
      ? tasks.map((t: { title: string; priority: string; status: string; due_date?: string }) =>
          `• ${t.title} [${t.priority.toUpperCase()}${t.due_date ? `, due ${t.due_date}` : ""}]`
        ).join("\n")
      : "No open tasks — all done!"

    const currency = financials[0]?.currency === "USD" ? "$" : "€"
    const income = financials.filter((f: { type: string }) => f.type === "income").reduce((s: number, f: { amount: number }) => s + Number(f.amount), 0)
    const expenses = financials.filter((f: { type: string }) => f.type === "expense").reduce((s: number, f: { amount: number }) => s + Number(f.amount), 0)
    const finCtx = financials.length > 0
      ? `Income: ${currency}${income.toFixed(0)} | Expenses: ${currency}${expenses.toFixed(0)} | Net: ${currency}${(income - expenses).toFixed(0)}\n` +
        financials.slice(0, 5).map((f: { title: string; amount: number; type: string }) => `• ${f.title}: ${currency}${f.amount} (${f.type})`).join("\n")
      : "No recent financial records."

    const docsCtx = expiringDocs.length > 0
      ? expiringDocs.map((d) => `• ${d.name} expires ${d.expires_at}`).join("\n")
      : ""
    const delivCtx = deliveries.length > 0
      ? deliveries.map((d) => `• ${d.title} (${d.status}${d.expected_date ? `, expected ${d.expected_date}` : ""})`).join("\n")
      : ""

    const propCtx = property
      ? `Property: ${property.name ?? "Home"} — ${property.address_line1 ?? ""}, ${property.city ?? ""}${property.health_score ? ` | Health: ${property.health_score}/100` : ""}`
      : ""

    const famCtx = familyMembers.length > 0
      ? familyMembers.map((m) => `• ${m.name}${m.role ? ` (${m.role})` : ""}`).join("\n")
      : ""
    const plantCtx = plants.length > 0
      ? plants.map((p) =>
          `• ${p.name}${p.health_status ? ` [${p.health_status}]` : ""}${p.last_watered_at ? `, last watered ${p.last_watered_at}` : ""}${p.watering_interval_days ? `, every ${p.watering_interval_days}d` : ""}`
        ).join("\n")
      : ""

    // Language instruction: explicit BCP-47 code from iOS client takes priority;
    // fallback to "same language the user writes in" for safety.
    const langInstruction = language
      ? `Always respond in the user's selected app language (BCP-47: ${language}). Do NOT switch languages even if the user writes in a different one.`
      : "Always respond in the same language the user writes in."

    // Owner-chosen personality (device setting, sent per request).
    const toneInstruction = tone === "friendly"
      ? "Tone: warm and encouraging — celebrate wins, keep it human."
      : tone === "professional" || tone === "formal"
      ? "Tone: professional and precise. No exclamation marks, no small talk."
      : tone === "concise"
      ? "Tone: as few words as fully helpful. Prefer tight bullet lists."
      : "Tone: balanced — helpful and natural, moderately detailed."

    // Honesty about switched-off domains: the model has no data from them and
    // must say so instead of guessing.
    const disabledDomains = [
      ...(allowTasks ? [] : ["tasks"]),
      ...(allowFinances ? [] : ["finances"]),
      ...(allowProperty ? [] : ["property details"]),
      ...(allowFamily ? [] : ["family members"]),
      ...(allowPlants ? [] : ["plants"]),
    ]
    const privacyInstruction = disabledDomains.length > 0
      ? `The owner turned OFF your access to: ${disabledDomains.join(", ")}. You have NO data from those areas. If asked about them, say access is switched off in AI Settings — never guess or invent values.`
      : ""

    const systemPrompt = `You are ${assistantName}, the intelligent AI assistant built into PRVHouse — a smart property management app.
You help the owner manage their property with practical, specific, and concise advice.
${langInstruction}
${toneInstruction}
${privacyInstruction}
Keep responses under 200 words unless a detailed breakdown is requested.
Ground answers in the property data below — cite the actual task names, amounts and dates instead of speaking generically.
Use your tools when the user's intent clearly matches one of them.

${propCtx ? `PROPERTY:\n${propCtx}\n` : ""}${allowTasks ? `
OPEN TASKS (last 5):
${taskCtx}
` : ""}${allowFinances ? `
FINANCES (last 30 days):
${finCtx}` : ""}${famCtx ? `\n\nFAMILY MEMBERS:\n${famCtx}` : ""}${plantCtx ? `\n\nPLANTS:\n${plantCtx}` : ""}${docsCtx ? `\n\nDOCUMENTS EXPIRING SOON:\n${docsCtx}` : ""}${delivCtx ? `\n\nACTIVE DELIVERIES:\n${delivCtx}` : ""}`

    const claudeMessages: Array<{ role: string; content: unknown }> = [
      ...(history ?? []).reverse().map((m: { role: string; content: string }) => ({
        role: m.role === "assistant" ? "assistant" : "user",
        content: m.content,
      })),
      { role: "user", content: message },
    ]

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY")
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not configured")

    // Tools follow the same switches as context: no task tools without task
    // access, no plant tool without plant access, no health/appliance tools
    // without property access.
    const activeTools = tools.filter((t) => {
      if (t.name === "create_task" || t.name === "schedule_maintenance") return allowTasks
      if (t.name === "mark_plant_watered") return allowPlants
      if (t.name === "query_twin_health" || t.name === "add_appliance") return allowProperty
      return true
    })

    // Tool-use loop — run until end_turn or a client-side action is needed
    let reply = ""
    let pendingAction: { type: "action_required"; tool: string; input: Record<string, unknown> } | null = null

    while (true) {
      const claudeRes = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model: "claude-haiku-4-5-20251001",
          max_tokens: 512,
          system: systemPrompt,
          messages: claudeMessages,
          tools: activeTools,
        }),
      })

      if (!claudeRes.ok) {
        const err = await claudeRes.text()
        throw new Error(`Claude API ${claudeRes.status}: ${err}`)
      }

      const claudeData = await claudeRes.json()
      const stopReason: string = claudeData.stop_reason ?? "end_turn"

      if (stopReason === "end_turn") {
        // Extract text reply from content blocks
        const textBlock = claudeData.content?.find((b: { type: string }) => b.type === "text")
        reply = textBlock?.text ?? "I couldn't generate a response."
        break
      }

      if (stopReason === "tool_use") {
        // Find all tool_use blocks
        const toolUseBlocks: Array<{ type: string; id: string; name: string; input: Record<string, unknown> }> =
          (claudeData.content ?? []).filter((b: { type: string }) => b.type === "tool_use")

        if (toolUseBlocks.length === 0) {
          // No tool calls found despite stop_reason — treat as end_turn
          const textBlock = claudeData.content?.find((b: { type: string }) => b.type === "text")
          reply = textBlock?.text ?? "I couldn't generate a response."
          break
        }

        // Append Claude's assistant turn (with tool_use) to the message history
        claudeMessages.push({ role: "assistant", content: claudeData.content })

        const toolResults: Array<{ type: string; tool_use_id: string; content: string }> = []

        for (const toolUse of toolUseBlocks) {
          if (toolUse.name === "query_twin_health") {
            // Server-side tool: query health_scores table
            const { data: healthData } = await supabase
              .from("health_scores")
              .select("score, category, computed_at")
              .order("computed_at", { ascending: false })
              .limit(5)

            let healthSummary: string
            if (!healthData || healthData.length === 0) {
              healthSummary = "No health score data available for this property."
            } else {
              const latest = healthData[0]
              const avg = healthData.reduce((s: number, h: { score: number }) => s + Number(h.score), 0) / healthData.length
              healthSummary = `Overall health score: ${latest.score}/100 (computed ${latest.computed_at}).\n` +
                `Average across ${healthData.length} categories: ${avg.toFixed(0)}/100.\n` +
                healthData.map((h: { score: number; category: string }) => `• ${h.category}: ${h.score}/100`).join("\n")
            }

            toolResults.push({
              type: "tool_result",
              tool_use_id: toolUse.id,
              content: healthSummary,
            })
          } else if (toolUse.name === "create_task" || toolUse.name === "mark_plant_watered" ||
                     toolUse.name === "add_appliance" || toolUse.name === "schedule_maintenance") {
            // Client-side action — return immediately to iOS for confirmation
            pendingAction = {
              type: "action_required",
              tool: toolUse.name,
              input: toolUse.input,
            }
            // Get the text context Claude provided alongside the tool call (if any)
            const textBlock = claudeData.content?.find((b: { type: string }) => b.type === "text")
            reply = textBlock?.text ?? ""
            break
          }
        }

        // If a pending client-side action was found, stop the loop immediately
        if (pendingAction !== null) {
          break
        }

        // Append tool results and continue the loop
        claudeMessages.push({ role: "user", content: toolResults })
        continue
      }

      // Unknown stop_reason — treat as end_turn
      const textBlock = claudeData.content?.find((b: { type: string }) => b.type === "text")
      reply = textBlock?.text ?? "I couldn't generate a response."
      break
    }

    // Persist user message; persist assistant reply only if we have one (not when action required with empty reply)
    const persistRows: Array<{ user_id: string; property_id: string | null; role: string; content: string }> = [
      { user_id: user.id, property_id: propertyId ?? null, role: "user", content: message },
    ]
    if (reply) {
      persistRows.push({ user_id: user.id, property_id: propertyId ?? null, role: "assistant", content: reply })
    }
    await supabase.from("aria_messages").insert(persistRows)

    if (pendingAction) {
      return new Response(
        JSON.stringify({ reply: reply || undefined, ...pendingAction }),
        { headers: { ...cors, "Content-Type": "application/json" } }
      )
    }

    return new Response(
      JSON.stringify({ reply }),
      { headers: { ...cors, "Content-Type": "application/json" } }
    )
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return new Response(
      JSON.stringify({ error: msg }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
    )
  }
})
