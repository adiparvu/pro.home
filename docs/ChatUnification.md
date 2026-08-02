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
- **P5 ✓ — shared engine core (`ChatEngineCore.swift`), zero behavior
  change.** An honest re-audit of what STILL duplicated after P0–P4d-2
  found ~140 lines of provably identical mechanics; only those merged:
  - the optimistic-send skeleton (append → bounded insert → swap the
    server ack in by id → rollback-and-rethrow to the outbox hand-off) —
    `runOptimisticSend`, generic over the engine's row type via key path,
    so `revision` observation still fires through the property setter;
  - the reliable-delivery broadcast ping, both directions
    (`broadcastDeliveryPing` / `isOwnDeliveryPing` — dm_new/msg_new);
  - the typing-broadcast handler and the realtime DELETE handler
    (`registerTypingHandler` / `registerDeleteHandler`, byte-identical in
    both engines; the DM's extra heads refresh rides its onDelete closure);
  - the `message_reactions` delete-own + insert sequence
    (`persistReactionToggle` — identical wire payloads in both engines);
  - the edit UPDATE (`ChatMessageStore.editRow`, joining the P3c
    delete/tombstone family; each engine keeps its own timestamp formatter
    and local patch).
  Deliberately NOT merged (verified divergent, not forced): the models,
  tables and queries (until `direct_messages` retires per P4d); send's
  post-success bookkeeping (DM heads refresh vs group sync cursor — passed
  as the `onSent` closure, not abstracted); pin/mark (peer-capable legacy
  UPDATE vs definer RPC with optimistic rollback — different semantics);
  receipt persistence (DM's timestamped side-table upserts + legacy column
  fallback vs the group's server-defaulted upserts — different columns);
  INSERT/UPDATE realtime reconciliation (DM incremental apply vs group
  cursor reload — the P3 deferral holds); search queries (`likePattern`
  was already single-sourced in `MessageService`); heads (DM-only).
  Flagged for a later, separately verified pass: `MessageService`'s four
  receipt/reaction/poll-vote channels are near-verbatim copies of each
  other (~260 lines within ONE engine) — realtime-lifecycle-sensitive, so
  not touched in a no-behavior-change hygiene pass.
- **HOTFIX (migration `chat_unification_fix_dm_notification_leak`)** — the
  `messages` notification triggers (`notify_chat_message`,
  `notify_on_group_message`) predate conversation rows and treated every
  mirrored DM as a family-chat message: the DM body went out as a
  notification to ALL active property members, sender included (field
  report: "I received my own message" on 1197). Both triggers now carry
  `WHEN (new.conversation_id IS NULL)`; DM notifications remain solely
  `notify_on_direct_message`'s job (which the symmetric mirror keeps firing
  for both write paths). Spurious in-app notifications from mirrored rows
  were purged; already-delivered pushes cannot be recalled. Review lesson
  recorded: guarding reads (RLS + client queries) is not enough — EVERY
  server-side consumer of `messages` INSERTs (triggers, webhooks) must be
  swept when a new row class enters a shared table.
- **P6 ✓ (client + server) — one store, no flag, no mirror dependency.**
  With `chat_rollout.dm_unified_read` flipped ON and parity verified
  (349/349 messages, 0 missing), the retirement work removed the last
  reasons `direct_messages` had to exist:
  - **Server** (`chat_unification_p6_retirement_server`):
    `dm_conversation_heads` now computes from `conversations` /
    `conversation_members` / `messages` / `message_reads` (same signature
    and row shape — clients can't tell); DM notifications moved to
    `notify_on_dm_message` on `messages` `WHEN (conversation_id IS NOT
    NULL)` and the legacy `trg_notify_on_direct_message` was dropped in the
    same transaction, so a mirrored row can never notify twice;
    `process_scheduled_messages` sends DMs into the unified store; and
    pin/mark got definer RPCs (`dm_set_pin` / `dm_set_mark`) gated on
    conversation membership, because the `messages` UPDATE policy is
    sender-only (right for an edit, wrong for a pin) and RLS cannot scope a
    policy per column. Verified as real users: peer-pin works, an outsider
    gets `not a member of this conversation`, one notification lands on the
    peer only, both mirror directions stay consistent.
  - **Follow-up** (`chat_unification_p6_scheduled_dm_identity`): a
    scheduled DM stores only the recipient's NAME, which would have keyed a
    'n:<name>' participant and forked a second thread. It now resolves the
    peer against the property roster (family_members, then active
    property_members + profiles) before opening the conversation — the
    scheduled message lands in the thread the app already shows.
  - **Client** (`DirectMessageService`): the flag, the dual-read and every
    legacy query are gone. Reads, older pages, search, realtime, send,
    receipts, reactions, edit, delete and pin/mark all address the unified
    store. Realtime is one channel over `messages` + `message_reads` +
    `message_deliveries` + `message_reactions` (receipts are ROWS now, so a
    peer's tick no longer arrives as an UPDATE of the message); DM rows are
    told apart from group rows because a group row cannot decode into
    `UnifiedRow` (non-optional `conversation_id`), the mirror image of the
    group engine's `.is("conversation_id", nil)`. The realtime UPDATE path
    PATCHES fields instead of swapping the row — a unified row carries no
    receipts, so a swap would erase the ticks and reactions already known.
  - **Still standing on purpose**: the table, its mirrors and the
    `chat_rollout` kill-switch. The fleet is mixed until everyone updates,
    and 1199 reads `direct_messages` for realtime. The DROP is P6's final
    migration, to be run only after the family confirms the retirement
    build — with `cleanup_expired_chat_ephemera` and `delete_my_account`
    swept in the same change.
  - **⚠ Kill-switch semantics changed.** `messages_select` still gates the
    DM branch on `dm_unified_read_enabled()`, and that stays until the drop
    — today it is a real rollback lever, because 1199 falls back to
    `direct_messages` when the flag goes false. Once the retirement build is
    on the family's phones that is no longer true: flipping the flag back
    would leave those clients with NO readable DMs at all, since they have
    no legacy path left. From that moment the only supported rollback is
    shipping a previous build. The drop migration removes the flag from the
    policy and the `chat_rollout` row in the same change, so the lever
    disappears rather than lingering as a trap.
- **P6 field correction (b1200 → b1201): the WAKE-UP goes back on the
  mirrored stream.** b1200 moved the DM realtime listener onto `messages`
  along with the reads. The field evidence turned against it within hours:
  a recipient's device stopped stamping delivered/read for inbound rows
  while the server-side chain was verified INTACT end to end — notification
  row written (one, to the peer only), webhook HTTP 200, APNs `sent:1`, and
  the recipient's RLS visibility confirmed by querying as that user. The
  asymmetry (one device consuming, the other not) pointed at the only piece
  of the receive path b1200 changed, so the listener returns to
  `direct_messages` — the stream that delivered reliably through
  b1177–b1199 — while reads, writes, history, search and pin/mark stay
  unified. WHERE WE READ and WHAT WAKES US UP are separate decisions; the
  mirrors make the two views of a row identical and ids are preserved, so a
  legacy-shaped event addresses exactly the unified row the UI shows. Bonus:
  the mirrored row carries receipts and reactions in its own columns, so one
  swap brings ticks and reactions — no side-table channels to get right.
  Also fixed here: the receipt writers resolved the user id from the
  `myUserId` cache only, so a transiently-nil cache silently swallowed every
  tick (the retired legacy path stamped by row id and needed no identity) —
  they now take the session as the authority.
  **Consequence for the drop:** retiring `direct_messages` is now gated on
  the unified listener being proven on-device, NOT on the reads (already
  unified fleet-wide). Until then the table, its mirrors and the flag stay.
- **P6b ✓ — ChatSideChannel.** The four receipt/reaction/poll side channels
  in MessageService (~260 near-verbatim lines) share one lifecycle type:
  scope-topic, liveness idempotency, 15s timebox, clean teardown — and, for
  the first time on these channels, the b1197 socket-wait with the b1198
  cancellation lesson baked in.
- **P6c ✓ — dm_bootstrap.** The DM window is ONE round-trip (SECURITY
  INVOKER jsonb RPC: conversations + members + message window + all three
  side tables); the client tries it first and falls back to the shipped
  multi-query path on any failure. Verified as a real user: 5/9/366 with
  full receipts.
- **G1 ✓ (scaffolding only) — group conversations may now EXIST.**
  `conversations.kind` accepts 'group', `group_key` ('main:<property>' /
  'grp:<chat_group_id>', unique) names them. NOTHING creates or reads such
  rows yet: every shipped client filters group reads on `conversation_id IS
  NULL`, so stamping group messages is a phased rollout of its own (G2:
  dual-write behind a chat_rollout-style flag; G3: reads; G4: retire
  group_id) — the same playbook P4 proved on DMs.
- **P6 FINAL (prepared, NOT applied)** —
  `docs/pending-migrations/p6_final_drop_direct_messages.sql`: mirrors
  first (msg_mirror_insert would otherwise error inside every send), then
  cleanup/delete_my_account sweeps, then the kill-switch (policy stops
  consulting `dm_unified_read_enabled()`, function + chat_rollout drop),
  then the table. Gate: EVERY device on 1201+, owner-confirmed.
- **P6 FINAL ✓ APPLIED (2026-08-02, owner-ordered)** — `direct_messages`
  is GONE (migration `chat_p6_final_drop_direct_messages`). Verified
  before: parity 366/366, 0 missing, 0 orphaned poll votes, no
  policies/views referencing it. The first apply attempt taught the
  audit's last lesson: the REVERSE receipt/reaction mirrors lived as
  triggers on the three side tables — all EIGHT mirror triggers dropped
  by name, in the same transaction, mirrors-before-table (msg_mirror_insert
  fired inside every send). `dm_poll_votes.message_id` FK repointed to
  `messages(id)` (ids identical by construction). `cleanup_expired_chat_
  ephemera` + `delete_my_account` swept. The kill-switch left with the
  table: `messages_select` no longer consults `dm_unified_read_enabled()`
  (function dropped, column dropped); `chat_rollout` survives as the
  carrier of the NEXT flag — `group_unified_read`, default false (G2).
  Verified after, as a real user in a rolled-back transaction: DM insert
  clean, exactly one notification to the peer only, zero mirror triggers
  left. Devices ≤1199: DM realtime/pin/mark broken until they update —
  consequence accepted by the owner at order time.
- **G2 ✓ (server applied + client shipped, flag OFF)** — groups get the P4
  playbook. Server (`chat_g2_group_conversations_server`): conversations
  carry groups (dm_key nullable + shape check, chat_group_id,
  `group_open_conversation` definer RPC, membership-gated, idempotent on
  group_key); `is_conversation_reader` authorizes by KIND — dm → explicit
  member rows, group → the same DYNAMIC predicates the legacy filters use
  (group rosters churn; mirroring them into conversation_members would be
  a sync liability); all three messages policies use it (byte-equivalent
  for dm); `notify_on_dm_message` became kind-aware NOW, not at G3 — the
  b1197 leak's lesson applied proactively. Client: one scoped query for
  all four group reads (conversation when `chat_rollout.group_unified_read`
  is up, the legacy triple otherwise), flag read once per property,
  fail-closed; WRITES stay legacy. `groupHasMatch` already calls the G3
  search RPC with a legacy fallback. G3 (prepared,
  `docs/pending-migrations/chat_g3_group_unified_flip.sql`): backfill +
  server-side stamping of new inserts + the two group-notification
  triggers rebuilt kind-aware + the flip — apply ONLY with the whole
  fleet on a G2 build.
