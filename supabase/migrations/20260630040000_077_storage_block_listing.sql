-- 077: S4 (phase 1) — stop public buckets from leaking their full file list.
--
-- The audit flagged `public_bucket_allows_listing` on avatars, documents and
-- task-photos: each had a broad SELECT policy on storage.objects scoped only to
-- `bucket_id = '<bucket>'`, which lets any (often anon) client enumerate EVERY
-- file in the bucket and then fetch them.
--
-- The app never lists buckets — it only uploads and reads by the public URL it
-- stored at send time (paths use unguessable UUIDs). Public buckets serve those
-- URLs through the `/object/public/...` endpoint, which bypasses RLS, so removing
-- these SELECT policies blocks enumeration with ZERO impact on media display.
-- Upload / update / delete owner-scoped policies are left untouched.
--
-- NOTE: this does not make the buckets private. Time-limited signed URLs (true
-- private storage) are a larger, data-sensitive refactor — the app persists full
-- public URLs in attachment_url/avatar_url, and signed URLs expire — so that is
-- tracked as a Phase-4 item. Combined with the message-RLS fixes in 076, a media
-- URL now only reaches someone who can already read the message.

DROP POLICY IF EXISTS "Documents are publicly readable" ON storage.objects;
DROP POLICY IF EXISTS "documents_read_authenticated"   ON storage.objects;
DROP POLICY IF EXISTS "documents_storage_select"       ON storage.objects;
DROP POLICY IF EXISTS "Public avatar read"             ON storage.objects;
DROP POLICY IF EXISTS "task_photos_select"             ON storage.objects;
