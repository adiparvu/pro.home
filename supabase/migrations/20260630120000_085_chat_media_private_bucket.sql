-- 085: Phase 4 (D) — private bucket for chat media + signed-URL access.
--
-- Chat attachments/voice/status currently live in the public `documents` bucket,
-- so their URLs never expire and a shared link grants permanent access. This
-- creates a PRIVATE `chat-media` bucket that the client reads via short-lived
-- signed URLs. Rollout is non-breaking: new chat uploads go here, while old
-- media keeps working through its existing public URL.
--
-- Object path convention: `{property_id}/{...}`. RLS scopes read/write to members
-- of that property, so createSignedURL only succeeds for people in the chat.

INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-media', 'chat-media', false)
ON CONFLICT (id) DO NOTHING;

-- Property members can read objects in their property's folder (needed so
-- createSignedURL succeeds for them).
DROP POLICY IF EXISTS "chat_media_select_member" ON storage.objects;
CREATE POLICY "chat_media_select_member" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'chat-media'
        AND public.is_property_member(((storage.foldername(name))[1])::uuid)
    );

DROP POLICY IF EXISTS "chat_media_insert_member" ON storage.objects;
CREATE POLICY "chat_media_insert_member" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'chat-media'
        AND public.is_property_member(((storage.foldername(name))[1])::uuid)
    );

DROP POLICY IF EXISTS "chat_media_delete_member" ON storage.objects;
CREATE POLICY "chat_media_delete_member" ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'chat-media'
        AND public.is_property_member(((storage.foldername(name))[1])::uuid)
    );
