# Chat Unification — architecture & phases

## Why

PRVIO chat runs on **two parallel engines** and **two parallel view shells**:

| Concern        | Direct messages            | Group / community chat     |
|----------------|----------------------------|----------------------------|
| Service        | `DirectMessageService` (~1040 lines) | `MessageService` (~920 lines) + `ChatGroupService` |
| Data model     | `DirectMessage`            | `Message`                  |
| View shell     | `DirectMessageView` (+Composer, +MessageList) | `ChatView` (+Composer, +MessageList) |

The two shells already share the composer (`ChatComposerBar`), the bubble
(`ChatMessageBubbleShared`), the attachment sheet, activity bubbles, theme and
jump-button behaviour — those were extracted opportunistically. But the
**scroll/paging/realtime/unread coordinators are still duplicated**, and every
chat improvement this cycle (live delivery, typing/recording bubbles, jump
button, background live-update, notification suppression) had to be written
**twice**, once per shell/service. That double-maintenance is the cost the
unification removes.

Goal: **one conversation engine + one view shell**, parameterised by the
conversation kind (DM / group / community), with zero behaviour regressions.
The core chat feature ships to every user, so each phase must be independently
shippable and verifiable — no big-bang rewrite.

## Target architecture

```
ChatMessage            // one normalized message model (id, author, body,
                       // media, replyTo, createdAt, receipts, kind)
        ▲
ChatEngine (protocol)  // load(older/newer), send, edit, delete, react,
                       // typing, receipts, realtime subscribe/unsubscribe,
                       // unread + outbox — the surface both current services
                       // already implement under different names
   ├── DMEngine        // wraps direct_messages
   └── RoomEngine      // wraps messages (property group + community sub-group)

ConversationModel      // @Observable coordinator the view binds to:
                       // scroll state, jump-to-latest, load-more window,
                       // activity (typing/recording), draft, send pipeline
        ▲
ConversationView       // ONE shell; DM/group/community differ only in header,
                       // roster and the engine handed to the model
```

## Phases (each independently shippable)

- **P0 — this doc.** Name the seams; freeze the target shape.
- **P1 — Shared `ConversationModel`.** Extract the duplicated
  `+MessageList` coordinator (scroll anchoring, jump-to-latest, load-newer/
  older window, activity bubble state) into one `@Observable` model both
  shells drive. No service change yet — the model calls into the existing
  service via a thin closure/adapter. *Kills the double-edit pain first, at
  the lowest risk.*
- **P2 — `ChatMessage` + `ChatEngine` protocol.** Introduce the normalized
  model and the protocol; conform `DirectMessageService` and `MessageService`
  to it behind adapters, leaving their storage untouched. Views/model talk to
  the protocol.
- **P3 — Shared realtime + unread + outbox.** One reliable-delivery broadcast
  path, one unread cursor, one `OfflineOutbox` integration — today each engine
  reimplements these (the `dm_new`/`msg_new` split shipped this cycle is the
  seam to merge).
- **P4 — One `ConversationView` shell.** Collapse `DirectMessageView` and
  `ChatView` into a single shell parameterised by kind; delete the duplicates.
- **P5 — Feature parity sweep** (#123): push, outbox, search, video DM,
  presence, unread sync — verified once, on the unified path.

## Rules

1. **Every phase compiles and ships green.** No phase leaves chat half-migrated
   on `main`.
2. **No behaviour regressions.** The unified path must match today's DM and
   group behaviour before the old path is deleted (P4).
3. **Coordinate on the branch.** Chat files are hot; another worker may touch
   them. Keep each phase to a tight file set and rebase before pushing.
4. **Honesty law holds.** No dead controls, no fabricated receipts/state on the
   unified path.

## Status

- **P0** ✓ — this document.
- **P1** ✓ — shared `ConversationScrollModel` (jump-to-latest visibility +
  debounced toggle) adopted by both message lists. Shipped, CI green.
- **P2a** ✓ — normalized `ChatMessageKind` vocabulary: the group bubble's
  reply preview (`MessageBubble.replyPreview`) now resolves through it instead
  of hardcoded English labels, fixing a localization-law violation (RO users
  saw "📷 Photo") while keeping EN output identical. Seed of the unified
  `ChatMessage.kind`.
- **P2b** ✓ — the group **pinned-banner** snippet (`pinnedSnippet`) was a third
  copy of the same classification, also hardcoded in English. Routed through
  `Message.chatKind` too: localized now, and it correctly labels task/contact
  shares it previously missed. Three group kind-classifiers → one.
- **P2c** ✓ — one DM snippet authority: `DirectMessage.previewSnippet` (the
  full deleted → `DMRich` → contact → media → subject-stripped-text chain).
  Reply quote, composer reply banner, pinned banner, message details and the
  starred list all route through it. Fixes two real leaks — message details
  and the starred list skipped the rich/contact checks and showed raw marker
  payloads for location/sticker/event/file/contact shares — plus two
  unlocalized strings ("👤 Contact", "This message was deleted" in the
  action-overlay preview).
- Deferred (runtime-behaviour-sensitive, needs on-device verification before
  touching): the **conversation-list** previews intentionally differ from the
  bubble (the list prefixes the sender and prefers a caption over a media
  label), so they are *not* a mechanical reroute — converging them can regress
  captioned-media cases and must be verified live, not just CI-compiled.
- **P3a** ✓ — one typing/recording subsystem (`ChatActivityIndicator`): both
  engines carried byte-identical copies of the throttled activity broadcast,
  indicator sets and per-peer expiry. Engines keep the channel lifecycle and
  sync channel/name in before each use; the service surface is unchanged.
- **P3b** ✓ — one `LastSeenCursor` for the unread divider's device-local
  last-seen timestamp, parameterized by each engine's exact existing
  UserDefaults key (incl. the DM legacy-key migration) so no stored data
  moves. `firstUnreadId` stays per-engine deliberately — its divergent
  predicate (DM thread-identity vs group senderId) is the whole function.
- **P3c** ✓ — one `ChatMessageStore` for the delete/tombstone/hide row
  mechanics; engines keep their differing local-state patches (DM revision
  bumps vs group row removal) and their own table/key.
- **P3d** ✓ — one realtime channel lifecycle (`ChatRealtimeChannel`): both
  engines carried a near-verbatim copy of subscribe/rebuild, the rejoin
  grace, the storm breaker, the stale-close kill watch and the diagnostics
  banner text — every field lesson (b1036/b1040/b1157/b1173/b1182) fixed
  twice. The shared type owns the channel; each engine passes a
  `Configuration` seam: its scoped topic, its handler registrations
  (returning the retained `RealtimeSubscription` handles) and its
  post-rebuild refetch — DM's incremental merge-load vs the group's cursor
  refetch stay per-engine, exactly as the P3 deferral demands. The group
  chat inherits the DM-only broadcast round-trip self-test, fixing a false
  "live" on a channel whose broadcast relay was dead (typing and the
  msg_new delivery ping both ride on broadcast).
- Deferred within P3 (needs on-device, two-account verification): the
  realtime INSERT reconciliation paths (DM's incremental apply vs group's
  cursor reload — the engines' genuinely different hearts), send's
  post-success bookkeeping, reactions/pin-mark (different data models), and
  the pagination queries (identity-clause construction is RLS-sensitive).
- Next: grow `ChatMessageKind` toward the full `ChatMessage` model +
  `ChatEngine` protocol (P2 tail), then P4's single shell once the deferred
  P3 seams are verified live. The engine-protocol swap is the deepest, most
  behaviour-sensitive step on the core chat path, so it stays incremental and
  CI-verifiable rather than a big-bang rewrite.

## P4 — one message store (the industry model)

Decision (owner-approved): Slack/Matrix/Signal-style — ONE `messages` store;
a DM is a conversation with two members, not a parallel schema. The group
side (`messages` + read/delivery/reaction side tables) is already the
standard shape; `direct_messages` is the historical outlier.

- **P4a ✓ (migration `chat_unification_p4_conversations`)** —
  `conversations` (kind `dm`, canonical `dm_key` = least|greatest of the two
  participant keys: auth id when known, normalized name for accountless
  contacts) + `conversation_members` (user_id / member_id / display_name).
  RLS: members-only select via `is_conversation_member()` (definer).
- **P4b ✓ (same migration)** — `messages.conversation_id` (+ index);
  `messages` RLS rewritten ATOMICALLY with the backfill: every legacy branch
  (own-sender, family main chat, community group) gained a
  `conversation_id is null` guard, so deployed clients see exactly the same
  rows as before; unified DM rows are readable only by the two members AND
  only once `chat_rollout.dm_unified_read` flips (service-role-only
  kill-switch, default false). Backfill: 326/326 DM rows id-preserved into
  `messages`, 5 conversations, parity-checked (zero body mismatches).
  Mirror triggers (definer; trigger-returning, so not Data-API callable) on
  `direct_messages` INSERT/UPDATE/DELETE keep the unified store live while
  the deployed fleet still writes the legacy table — the backfill is
  continuous, not a snapshot.
- **P4c (next)** — client dual-read: DM read path moves to `messages` by
  `conversation_id` (behind the same flag), group/main queries add the
  `conversation_id is null` filter BEFORE the flag flips; receipts/reactions
  backfill into the side tables together with conversation-scoped RLS
  tightening there (deferred from P4b on purpose — DM read receipts must
  not ride the property-scoped side-table policies).
- **P4c-2 ✓** — client dual-read landed: `DirectMessageService.load()`
  reads `conversations`/`conversation_members`/`messages` + the receipt and
  reaction side tables when `chat_rollout.dm_unified_read` is up (fetched
  once per property switch, fail-closed to legacy on any error), maps rows
  back into `DirectMessage`, and snapshots under a separate cache entity
  (`dms.unified`). Flag still OFF — legacy read stays byte-identical.
  Server side: receipts/reactions side-table conversation-scoped RLS +
  backfill done in migration `chat_unification_p4c_receipts`.
- **P4d (last)** — writes flip to `messages` (+ a thread-creation RPC),
  the engines merge into one on the `ChatRealtimeChannel` foundation, and
  `direct_messages` retires to read-only, then drops after a full release
  cycle of parity.
- **P4d-1 ✓ (migration `chat_unification_p4d_reverse_mirror`)** — the mirror
  is now SYMMETRIC: unified writes (`messages` + side tables) project back
  into `direct_messages` (message rows, receipt columns, the reactions
  jsonb map) exactly as legacy writes project forward. Loops die on
  IS DISTINCT guards — the second hop finds nothing to change, so no
  trigger re-fires. `dm_open_conversation()` RPC (definer, caller-inclusive
  only) lets the unified client open a thread. Consequence: the
  `dm_unified_read` flag is safe to flip even on a MIXED fleet — new
  builds read unified/write legacy, stragglers read legacy which the
  reverse mirror keeps complete.
- **P4d-2 ✓** — the DM writes that can safely flip now go to the unified
  store behind the same `dm_unified_read` flag (flag down: byte-identical
  legacy paths): `send()` resolves the conversation (read-cache first,
  `dm_open_conversation` RPC for a fresh thread) and inserts into
  `messages`; read/delivered receipts become `message_reads`/
  `message_deliveries` array upserts (idempotent on (message_id, user_id),
  legacy UPDATE fallback for rows without the NOT-NULL property_id);
  reactions write `message_reactions` (delete-own + insert); edit and
  delete-for-all update the sender's own `messages` row. Pin/mark stay on
  `direct_messages` deliberately — the unified UPDATE RLS is sender-only
  and pin/mark are PEER capabilities; the legacy policy allows both parties
  and the forward mirror syncs. Fail-closed throughout: a unified write
  error is handled exactly like the legacy path's (outbox hand-off on send,
  best-effort elsewhere), never retried on the other store. Next: the two
  engines merge into one on ChatRealtimeChannel; then `direct_messages`
  retires (read-only → drop) after a full release cycle of parity.
