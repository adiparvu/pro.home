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
- Deferred (runtime-behaviour-sensitive, needs on-device verification before
  touching): the **conversation-list** previews and the **DM** reply/preview
  path intentionally differ from the bubble (the list prefers a caption over a
  media label; DM's `DMRich` yields richer snippets), so they are *not* a
  mechanical reroute — converging them can regress captioned-media and
  structured-payload cases and must be verified live, not just CI-compiled.
- Next: grow `ChatMessageKind` toward the full `ChatMessage` model +
  `ChatEngine` protocol. The engine-protocol swap is the deepest, most
  behaviour-sensitive step on the core chat path, so it stays incremental and
  CI-verifiable rather than a big-bang rewrite.
