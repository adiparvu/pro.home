# Supabase migrations — state & divergence notes

**The live `PRV HOUSE` project (`kwcanenheihuylaymwsl`) is the source of truth.**

The migration files in this folder and the live database have **divergent
lineages**. Several objects were created on the live DB by migrations whose
names/timestamps do not match the numbered files here. Notably:

- The live `direct_messages` table was created by a migration named
  `create_direct_messages_and_reactions`, **not** by the local
  `049_direct_messages` / `050_fix_dm_rls` files. As a result:
  - Its text column was historically `content`, while the entire app uses
    `body`. Migration `067` renames it (guarded; no-op where `body` exists).
  - It had no `UPDATE` RLS policy and no `current_user_display_name()` helper,
    so the strict policies the local `050` file assumes were never present.
- The numbered local files `049`–`066` therefore should **not** be assumed to
  reflect what is actually deployed.

## Canonical migrations (aligned to the live DB)

Migrations `067`+ were authored against the **real** live schema and applied
via MCP. They are idempotent and safe to replay:

| File | Purpose |
|---|---|
| `067_direct_messages_delivered_at` | rename `content`→`body` (guarded), add `delivered_at`, add permissive `dm_update` RLS policy |
| `068_message_deliveries` | group-chat delivery receipts table (mirrors `message_reads`) |
| `069_chat_message_notifications` | triggers that create `notifications` rows on new group/direct messages (drives web push) |
| `070_device_tokens` | APNs device tokens for native iOS push |

## Reconciling fully (follow-up)

To make the repo replay cleanly onto a fresh project, regenerate a single
baseline from the live DB and retire the divergent numbered files:

```bash
supabase link --project-ref kwcanenheihuylaymwsl
supabase db pull            # writes a schema snapshot reflecting live
# review, then squash 001–066 into a baseline; keep 067+ on top
```

This was intentionally **not** done automatically: squashing/rewriting
migration history is destructive to existing environments and should be a
deliberate, reviewed operation.
