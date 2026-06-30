-- 078: Communities — multiple chat groups per property (workers, family, …).
--
-- Until now a property had ONE implicit group chat (messages scoped by
-- property_id). Communities lets a property hold several named sub-groups.
--
-- Design is additive & zero-downtime: messages.group_id is nullable and NULL
-- means "the property-wide main group" (current behaviour). Existing rows and
-- the existing client keep working untouched; the group picker is layered on
-- top later. messages RLS is left property-member based for now — group-level
-- scoping is tightened once the client sets group_id.

-- ─── Group entities ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_groups (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
    name        text NOT NULL DEFAULT '',
    description text NOT NULL DEFAULT '',
    avatar_url  text,
    kind        text NOT NULL DEFAULT 'custom',   -- 'family' | 'work' | 'custom'
    created_by  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_chat_groups_property ON public.chat_groups(property_id);

-- Membership is contact-based (member_id text), matching chat_member_labels:
-- family members are not necessarily auth.users, so we key on the family member
-- id (as text) or the literal 'you' for the current user.
CREATE TABLE IF NOT EXISTS public.chat_group_members (
    group_id    uuid NOT NULL REFERENCES public.chat_groups(id) ON DELETE CASCADE,
    member_id   text NOT NULL,
    member_name text NOT NULL DEFAULT '',
    role        text NOT NULL DEFAULT 'member',   -- 'admin' | 'member'
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, member_id)
);
CREATE INDEX IF NOT EXISTS idx_chat_group_members_group ON public.chat_group_members(group_id);

-- ─── messages.group_id (NULL = property-wide main group) ───────────────────
ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES public.chat_groups(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_messages_group ON public.messages(group_id);

-- ─── RLS: property members manage groups within their own property ─────────
ALTER TABLE public.chat_groups        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_group_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS groups_select ON public.chat_groups;
DROP POLICY IF EXISTS groups_write  ON public.chat_groups;

CREATE POLICY groups_select ON public.chat_groups
    FOR SELECT TO authenticated
    USING (public.is_property_member(property_id));

CREATE POLICY groups_write ON public.chat_groups
    FOR ALL TO authenticated
    USING (public.is_property_member(property_id))
    WITH CHECK (public.is_property_member(property_id));

DROP POLICY IF EXISTS group_members_select ON public.chat_group_members;
DROP POLICY IF EXISTS group_members_write  ON public.chat_group_members;

-- Visible to any member of the group's property
CREATE POLICY group_members_select ON public.chat_group_members
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.chat_groups g
        WHERE g.id = chat_group_members.group_id
          AND public.is_property_member(g.property_id)
    ));

-- Manageable by any member of the group's property (admin model layered later)
CREATE POLICY group_members_write ON public.chat_group_members
    FOR ALL TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.chat_groups g
        WHERE g.id = chat_group_members.group_id
          AND public.is_property_member(g.property_id)
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.chat_groups g
        WHERE g.id = chat_group_members.group_id
          AND public.is_property_member(g.property_id)
    ));

-- ─── Realtime ──────────────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                   WHERE pubname='supabase_realtime' AND tablename='chat_groups') THEN
        EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_groups';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                   WHERE pubname='supabase_realtime' AND tablename='chat_group_members') THEN
        EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_group_members';
    END IF;
EXCEPTION WHEN others THEN NULL;
END $$;
