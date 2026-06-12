import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

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

    const { message, propertyId } = await req.json()
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

    // Load property context
    const [tasksRes, finRes, propRes] = await Promise.all([
      supabase
        .from("maintenance_tasks")
        .select("title, status, priority, due_date")
        .in("status", ["pending", "in_progress", "overdue"])
        .order("due_date", { ascending: true })
        .limit(5),
      supabase
        .from("financial_records")
        .select("type, amount, currency, title, date")
        .gte("date", new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split("T")[0])
        .order("date", { ascending: false })
        .limit(8),
      propertyId
        ? supabase.from("properties").select("name, address_line1, city, health_score").eq("id", propertyId).single()
        : Promise.resolve({ data: null }),
    ])

    const tasks = tasksRes.data ?? []
    const financials = finRes.data ?? []
    const property = propRes.data as { name?: string; address_line1?: string; city?: string; health_score?: number } | null

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

    const propCtx = property
      ? `Property: ${property.name ?? "Home"} — ${property.address_line1 ?? ""}, ${property.city ?? ""}${property.health_score ? ` | Health: ${property.health_score}/100` : ""}`
      : ""

    const systemPrompt = `You are ARIA, the intelligent AI assistant built into PRVHouse — a smart property management app.
You help the owner manage their property with practical, specific, and concise advice.
Always respond in the same language the user writes in.
Keep responses under 200 words unless a detailed breakdown is requested.

${propCtx ? `PROPERTY:\n${propCtx}\n` : ""}
OPEN TASKS (last 5):
${taskCtx}

FINANCES (last 30 days):
${finCtx}`

    const claudeMessages = [
      ...(history ?? []).reverse().map((m: { role: string; content: string }) => ({
        role: m.role === "assistant" ? "assistant" : "user",
        content: m.content,
      })),
      { role: "user", content: message },
    ]

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY")
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not configured")

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
      }),
    })

    if (!claudeRes.ok) {
      const err = await claudeRes.text()
      throw new Error(`Claude API ${claudeRes.status}: ${err}`)
    }

    const claudeData = await claudeRes.json()
    const reply = claudeData.content[0]?.text ?? "I couldn't generate a response."

    // Persist both turns
    await supabase.from("aria_messages").insert([
      { user_id: user.id, property_id: propertyId ?? null, role: "user", content: message },
      { user_id: user.id, property_id: propertyId ?? null, role: "assistant", content: reply },
    ])

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
