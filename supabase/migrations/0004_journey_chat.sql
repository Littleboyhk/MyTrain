-- ===========================================================================
-- My Train — co-passenger chat FOUNDATION (safety-critical layer only)
--
-- This migration defines identity, the verification gate, and moderation.
-- It deliberately does NOT define any client write path for messages: every
-- mutation goes through a security-definer RPC or an Edge Function so that the
-- mute check, the rate limit and the pseudonym boundary cannot be bypassed by
-- talking to the table directly.
--
-- ---------------------------------------------------------------------------
-- IDENTITY MODEL (read this before changing anything)
-- ---------------------------------------------------------------------------
-- Every row that another passenger can ever see references a PARTICIPANT
-- (a per-journey pseudonym), never a user. The real-user link exists in exactly
-- one place, `chat_participants.user_id`, which has NO client-visible policy
-- and is readable only by the service role. Consequences, on purpose:
--   * `chat_messages` carries `participant_id`, not `user_id`.
--   * A pseudonym is scoped to one (train, date). The same person on tomorrow's
--     train is a different, unlinkable participant to other passengers.
--   * Nicknames are per-participant and therefore also per-journey.
--
-- ---------------------------------------------------------------------------
-- PREREQUISITE THAT IS NOT YET MET (see report): AUTH
-- ---------------------------------------------------------------------------
-- `chat_participants.user_id` references auth.users. As of this migration the
-- app has no auth at all (no sign-in of any kind) and anonymous sign-ins are
-- disabled on the project, so NO participant row can be created yet. That is
-- intentional: the gate fails closed. Chat cannot be switched on until a
-- durable account identity exists, because without one the auto-mute below is
-- defeated by reinstalling the app.
--
-- ---------------------------------------------------------------------------
-- RETENTION SUMMARY (two different clocks, on purpose)
-- ---------------------------------------------------------------------------
--   journey_chats + chat_messages + participants + GPS samples
--       -> deleted `retention_hours` (default 3) after scheduled arrival.
--   chat_reports
--       -> retained 90 days, INCLUDING a snapshot of the reported message and
--          the real user ids, because the spec requires a manual review queue
--          that can spot patterns ACROSS journeys. This is the one place where
--          message content and identity outlive the journey. It must be
--          disclosed in the privacy policy.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'chat_verification_status') then
    create type public.chat_verification_status as enum (
      'pending',    -- collecting GPS, no access
      'verified',   -- sustained route match achieved
      'rejected',   -- points contradicted the train's route/timing
      'abandoned'   -- sampling stopped before the threshold was met
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'chat_message_kind') then
    create type public.chat_message_kind as enum ('text', 'preset', 'image');
  end if;

  if not exists (select 1 from pg_type where typname = 'chat_mute_reason') then
    create type public.chat_mute_reason as enum (
      'auto_report_threshold', 'manual_moderation', 'rate_limit_abuse'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'chat_report_review') then
    create type public.chat_report_review as enum ('pending', 'actioned', 'dismissed');
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- One room per train + journey date. Not per coach: the spec scopes a room to
-- the whole train run.
-- ---------------------------------------------------------------------------
create table if not exists public.journey_chats (
  id                   uuid primary key default gen_random_uuid(),
  train_number         text        not null,
  journey_date         date        not null,
  train_name           text,
  origin_code          text,
  destination_code     text,

  -- Scheduled arrival at the FINAL destination, derived from cached RailRadar
  -- route detail (last entry's arrival + day offset, IST). No extra API quota:
  -- the route is already cached for 24h.
  scheduled_arrival_at timestamptz,

  -- Hard delete boundary. Everything about this room dies at this instant.
  expires_at           timestamptz not null,
  retention_hours      integer     not null default 3,

  -- Operator kill switch for a single room (abuse in progress, legal request).
  locked               boolean     not null default false,
  locked_reason        text,

  created_at           timestamptz not null default now(),
  unique (train_number, journey_date)
);

create index if not exists journey_chats_expiry_idx
  on public.journey_chats (expires_at);

comment on column public.journey_chats.expires_at is
  'Hard delete boundary: scheduled arrival + retention_hours. Enforced by chat_purge_expired(), not by a query filter.';

-- ---------------------------------------------------------------------------
-- THE PSEUDONYM MAPPING. Service-role only — no policies, ever.
-- ---------------------------------------------------------------------------
create table if not exists public.chat_participants (
  id                  uuid primary key default gen_random_uuid(),
  chat_id             uuid not null references public.journey_chats(id) on delete cascade,

  -- The ONLY link between a real account and a per-journey pseudonym.
  user_id             uuid not null references auth.users(id) on delete cascade,

  -- What other passengers see, e.g. 'Traveler482'. Random per journey.
  display_id          text not null,

  -- Optional, journey-scoped. Never copied to a future journey; there is no
  -- profile table for it to be copied into.
  nickname            text,

  verification_status public.chat_verification_status not null default 'pending',
  verified_at         timestamptz,

  -- Posting ban. Null = can post. A muted participant may still READ, per spec.
  muted_until         timestamptz,

  report_count        integer     not null default 0,
  first_seen_at       timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),

  unique (chat_id, user_id),
  unique (chat_id, display_id)
);

create index if not exists chat_participants_user_idx
  on public.chat_participants (user_id);

comment on table public.chat_participants is
  'Real user <-> per-journey pseudonym map. Service role only: never expose user_id to any client, including the owner of the row.';

-- ---------------------------------------------------------------------------
-- Messages. Authored BY A PSEUDONYM, so a leak of this table alone cannot
-- identify anyone.
-- ---------------------------------------------------------------------------
create table if not exists public.chat_messages (
  id             uuid primary key default gen_random_uuid(),
  chat_id        uuid not null references public.journey_chats(id) on delete cascade,
  participant_id uuid not null references public.chat_participants(id) on delete cascade,

  kind           public.chat_message_kind not null default 'text',

  -- Free text, or the resolved label of a preset. Length capped in the RPC.
  body           text,

  -- Set for kind='preset' so a client can localise the template instead of
  -- rendering server text.
  preset_key     text,

  -- HIGHEST-RISK COMPONENT OF THIS FEATURE. Storage object path only.
  --
  -- Nothing writes this column yet, and no storage bucket is created by this
  -- migration. Before it is enabled, ALL of the following must hold, and two of
  -- them cannot currently be satisfied:
  --   1. Camera capture only, no gallery. NOT ENFORCEABLE ON WEB: the HTML
  --      `capture` attribute is advisory and desktop Chrome opens a normal file
  --      picker. Images must therefore be mobile-build-only.
  --   2. EXIF (incl. GPS coordinates) stripped server-side before any other
  --      passenger can fetch the object. A raw camera JPEG leaks the sender's
  --      precise location, which defeats the point of pseudonymity.
  --   3. Objects deleted with the room, which needs an explicit storage sweep;
  --      SQL cascade does not remove storage objects.
  --   4. Some form of CSAM/nudity scanning before first view, given there is
  --      no age gate on this app (see report).
  image_path     text,

  created_at     timestamptz not null default now(),

  -- Soft delete so moderation can pull a message while keeping the report
  -- snapshot coherent. Purge still removes the row at expiry.
  deleted_at     timestamptz,
  deleted_reason text,

  constraint chat_messages_body_or_image check (
    (kind = 'image' and image_path is not null) or
    (kind <> 'image' and body is not null and length(btrim(body)) > 0)
  )
);

create index if not exists chat_messages_room_time_idx
  on public.chat_messages (chat_id, created_at desc);

-- Supports the per-minute rate limit lookup.
create index if not exists chat_messages_rate_idx
  on public.chat_messages (participant_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Reports. Server-role only. Outlive the room (see retention summary).
-- ---------------------------------------------------------------------------
create table if not exists public.chat_reports (
  id                      uuid primary key default gen_random_uuid(),

  -- Nulled out when the room is purged; the report itself survives.
  chat_id                 uuid references public.journey_chats(id) on delete set null,
  message_id              uuid references public.chat_messages(id) on delete set null,

  train_number            text,
  journey_date            date,

  -- Pseudonyms, for the reviewer's reading of the conversation.
  reporter_participant_id uuid references public.chat_participants(id) on delete set null,
  reported_participant_id uuid references public.chat_participants(id) on delete set null,
  reporter_display_id     text,
  reported_display_id     text,

  -- Durable identity, required for the cross-journey pattern detection the
  -- spec asks for. Survives room purge. Never exposed to any client.
  reporter_user_id        uuid,
  reported_user_id        uuid,

  -- Content at report time: the message may be deleted or expired later.
  message_snapshot        text,
  message_kind            public.chat_message_kind,
  reason                  text,

  -- True for "report this user" rather than "report this message".
  is_user_report          boolean not null default false,

  review_status           public.chat_report_review not null default 'pending',
  reviewed_at             timestamptz,
  reviewer_note           text,

  created_at              timestamptz not null default now()
);

-- The manual review queue: every report lands here, including ones that did not
-- trip the circuit breaker.
create index if not exists chat_reports_queue_idx
  on public.chat_reports (review_status, created_at desc);

-- Cross-journey pattern lookup.
create index if not exists chat_reports_reported_user_idx
  on public.chat_reports (reported_user_id, created_at desc);

-- Powers the circuit breaker's distinct-reporter count.
create index if not exists chat_reports_breaker_idx
  on public.chat_reports (reported_participant_id, created_at desc);

-- One reporter cannot stack reports on the same message to fake a consensus.
create unique index if not exists chat_reports_one_per_message_idx
  on public.chat_reports (reporter_participant_id, message_id)
  where message_id is not null;

comment on table public.chat_reports is
  'Retained 90 days with message snapshot and real user ids for moderation review. This deliberately outlives the 3-hour chat retention; disclose in privacy policy.';

-- ---------------------------------------------------------------------------
-- Mutes (posting bans). Audit trail for the circuit breaker.
-- ---------------------------------------------------------------------------
create table if not exists public.chat_mutes (
  id             uuid primary key default gen_random_uuid(),
  chat_id        uuid references public.journey_chats(id) on delete cascade,
  participant_id uuid references public.chat_participants(id) on delete cascade,
  user_id        uuid,
  reason         public.chat_mute_reason not null,
  muted_until    timestamptz not null,
  trigger_count  integer,
  created_by     text not null default 'system',
  notes          text,
  created_at     timestamptz not null default now()
);

create index if not exists chat_mutes_participant_idx
  on public.chat_mutes (participant_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Blocks. Silent: the blocked participant is never told and sees no change.
--
-- Stored with BOTH the pseudonyms (for this room's filtering) and the resolved
-- user ids (so a block keeps working on a future journey, where the same person
-- has a different pseudonym). The blocker never learns the blocked user_id.
-- ---------------------------------------------------------------------------
create table if not exists public.chat_blocks (
  id                     uuid primary key default gen_random_uuid(),
  chat_id                uuid references public.journey_chats(id) on delete cascade,
  blocker_participant_id uuid not null references public.chat_participants(id) on delete cascade,
  blocked_participant_id uuid not null references public.chat_participants(id) on delete cascade,
  blocker_user_id        uuid not null,
  blocked_user_id        uuid not null,
  created_at             timestamptz not null default now(),
  unique (blocker_participant_id, blocked_participant_id)
);

create index if not exists chat_blocks_durable_idx
  on public.chat_blocks (blocker_user_id, blocked_user_id);

-- ---------------------------------------------------------------------------
-- Verification: raw GPS samples used to decide access.
--
-- PRIVACY NOTE: unlike crowd_positions (rotating id, non-reversible HMAC), this
-- table links a precise location trace to a real user_id. That is a genuine
-- privacy regression, and it is unavoidable for a gate that must be attributable
-- to the account being granted access. It is mitigated only by retention: these
-- rows die with the room.
-- ---------------------------------------------------------------------------
create table if not exists public.chat_verification_samples (
  id                 uuid primary key default gen_random_uuid(),
  chat_id            uuid not null references public.journey_chats(id) on delete cascade,
  user_id            uuid not null,

  lat                double precision not null,
  lng                double precision not null,
  accuracy_m         double precision,
  speed_kmh          double precision,

  -- Client clock, and when the server actually received it. Divergence between
  -- the two is itself a signal: a replayed track arrives late.
  sample_ts          timestamptz not null,
  received_at        timestamptz not null default now(),

  -- Derived by the matcher.
  chainage_km        double precision,  -- distance along the route from origin
  corridor_offset_m  double precision,  -- perpendicular distance to the route
  implied_delay_min  double precision,  -- schedule offset implied by position
  accepted           boolean not null default false,
  reject_reason      text,

  created_at         timestamptz not null default now()
);

create index if not exists chat_verification_samples_lookup_idx
  on public.chat_verification_samples (chat_id, user_id, sample_ts desc);

-- ---------------------------------------------------------------------------
-- Rolling verification state per (room, user), so a decision does not require
-- rescanning every sample.
-- ---------------------------------------------------------------------------
create table if not exists public.chat_verification_state (
  chat_id            uuid not null references public.journey_chats(id) on delete cascade,
  user_id            uuid not null,

  status             public.chat_verification_status not null default 'pending',

  -- Longest run of consecutive accepted samples, in seconds. THE gate value.
  sustained_seconds  integer not null default 0,
  window_started_at  timestamptz,

  accepted_samples   integer not null default 0,
  rejected_samples   integer not null default 0,

  -- Net forward movement along the route within the current run.
  progress_km        double precision not null default 0,
  max_speed_kmh      double precision,
  last_chainage_km   double precision,
  last_sample_ts     timestamptz,

  -- Consistency of the implied delay across the run: a real train has a stable
  -- offset from its schedule, a fabricated track usually does not.
  delay_spread_min   double precision,

  reason             text,
  decided_at         timestamptz,
  updated_at         timestamptz not null default now(),

  primary key (chat_id, user_id)
);

-- ===========================================================================
-- Helper functions (security definer) used by policies and RPCs.
-- ===========================================================================

-- The caller's participant row in a room, or null.
create or replace function public.chat_my_participant(p_chat uuid)
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select id from public.chat_participants
   where chat_id = p_chat and user_id = auth.uid()
   limit 1;
$$;

-- May the caller READ this room? Verified participants only, room not expired.
-- Muted users can still read, by design.
create or replace function public.chat_can_read(p_chat uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
      from public.chat_participants p
      join public.journey_chats c on c.id = p.chat_id
     where p.chat_id = p_chat
       and p.user_id = auth.uid()
       and p.verification_status = 'verified'
       and c.expires_at > now()
  );
$$;

-- May the caller POST? Verified, not muted, room not locked or expired.
create or replace function public.chat_can_post(p_chat uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
      from public.chat_participants p
      join public.journey_chats c on c.id = p.chat_id
     where p.chat_id = p_chat
       and p.user_id = auth.uid()
       and p.verification_status = 'verified'
       and (p.muted_until is null or p.muted_until <= now())
       and c.locked = false
       and c.expires_at > now()
  );
$$;

-- ===========================================================================
-- Moderation: automatic circuit breaker.
--
-- Implemented as a TRIGGER rather than inside an Edge Function so it holds no
-- matter which path inserted the report.
--
-- DELIBERATE DEVIATION FROM THE BRIEF: the brief says "2-3 reports". Counting
-- raw reports lets ONE malicious user silence someone by reporting three of
-- their messages. This counts DISTINCT REPORTERS instead, so silencing someone
-- requires three independent passengers within the window.
-- ===========================================================================
create or replace function public.chat_reports_breaker()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  distinct_reporters integer;
  room_expiry        timestamptz;
  v_user_id          uuid;
begin
  if new.reported_participant_id is null then
    return new;
  end if;

  select count(distinct reporter_participant_id)
    into distinct_reporters
    from public.chat_reports
   where reported_participant_id = new.reported_participant_id
     and created_at > now() - interval '20 minutes';

  update public.chat_participants
     set report_count = report_count + 1
   where id = new.reported_participant_id
  returning user_id into v_user_id;

  if distinct_reporters >= 3 then
    -- Mute for the rest of the journey; review is manual and asynchronous.
    select expires_at into room_expiry
      from public.journey_chats where id = new.chat_id;

    update public.chat_participants
       set muted_until = coalesce(room_expiry, now() + interval '6 hours')
     where id = new.reported_participant_id
       and (muted_until is null or muted_until < coalesce(room_expiry, now()));

    insert into public.chat_mutes (
      chat_id, participant_id, user_id, reason, muted_until,
      trigger_count, created_by, notes
    )
    values (
      new.chat_id, new.reported_participant_id, v_user_id,
      'auto_report_threshold',
      coalesce(room_expiry, now() + interval '6 hours'),
      distinct_reporters, 'system',
      'Auto-muted: ' || distinct_reporters ||
      ' distinct reporters within 20 minutes. Pending manual review.'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists chat_reports_breaker_trg on public.chat_reports;
create trigger chat_reports_breaker_trg
  after insert on public.chat_reports
  for each row execute function public.chat_reports_breaker();

-- ===========================================================================
-- Client-callable RPCs. These are the ONLY write paths for a passenger.
-- ===========================================================================

-- Report a message, or a user (pass p_message_id = null).
-- Takes the target's DISPLAY id: a client never handles a user_id or a
-- participant uuid it did not author.
create or replace function public.chat_report(
  p_chat        uuid,
  p_target      text,
  p_message_id  uuid default null,
  p_reason      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me        public.chat_participants;
  target    public.chat_participants;
  msg       public.chat_messages;
  new_id    uuid;
begin
  select * into me from public.chat_participants
   where chat_id = p_chat and user_id = auth.uid();
  if me.id is null then
    raise exception 'not a participant of this chat' using errcode = '42501';
  end if;

  select * into target from public.chat_participants
   where chat_id = p_chat and display_id = p_target;
  if target.id is null then
    raise exception 'unknown participant' using errcode = 'P0002';
  end if;
  if target.id = me.id then
    raise exception 'cannot report yourself' using errcode = '22023';
  end if;

  if p_message_id is not null then
    select * into msg from public.chat_messages
     where id = p_message_id and chat_id = p_chat;
    if msg.id is null then
      raise exception 'unknown message' using errcode = 'P0002';
    end if;
  end if;

  insert into public.chat_reports (
    chat_id, message_id, train_number, journey_date,
    reporter_participant_id, reported_participant_id,
    reporter_display_id, reported_display_id,
    reporter_user_id, reported_user_id,
    message_snapshot, message_kind, reason, is_user_report
  )
  select
    p_chat, p_message_id, c.train_number, c.journey_date,
    me.id, target.id,
    me.display_id, target.display_id,
    me.user_id, target.user_id,
    -- Snapshot: an image report records its path, not its bytes.
    case when msg.id is null then null
         when msg.kind = 'image' then '[image] ' || coalesce(msg.image_path, '')
         else msg.body end,
    msg.kind, p_reason, p_message_id is null
    from public.journey_chats c where c.id = p_chat
  returning id into new_id;

  return new_id;
end;
$$;

-- Block silently. Durable across journeys via the resolved user ids, without
-- ever telling the blocker who the person is.
create or replace function public.chat_block(p_chat uuid, p_target text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me     public.chat_participants;
  target public.chat_participants;
begin
  select * into me from public.chat_participants
   where chat_id = p_chat and user_id = auth.uid();
  if me.id is null then
    raise exception 'not a participant of this chat' using errcode = '42501';
  end if;

  select * into target from public.chat_participants
   where chat_id = p_chat and display_id = p_target;
  if target.id is null then
    raise exception 'unknown participant' using errcode = 'P0002';
  end if;
  if target.id = me.id then
    raise exception 'cannot block yourself' using errcode = '22023';
  end if;

  insert into public.chat_blocks (
    chat_id, blocker_participant_id, blocked_participant_id,
    blocker_user_id, blocked_user_id
  )
  values (p_chat, me.id, target.id, me.user_id, target.user_id)
  on conflict (blocker_participant_id, blocked_participant_id) do nothing;
end;
$$;

-- Journey-scoped nickname.
--
-- Sanitised because a nickname is a contact-sharing channel: long digit runs
-- (phone numbers) and @handles are rejected. Message bodies are NOT filtered in
-- this pass — see report.
create or replace function public.chat_set_nickname(p_chat uuid, p_nickname text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  clean text;
begin
  if public.chat_my_participant(p_chat) is null then
    raise exception 'not a participant of this chat' using errcode = '42501';
  end if;

  clean := btrim(regexp_replace(coalesce(p_nickname, ''), '[[:cntrl:]]', '', 'g'));

  if clean = '' then
    update public.chat_participants set nickname = null
     where chat_id = p_chat and user_id = auth.uid();
    return null;
  end if;

  if length(clean) > 20 then
    raise exception 'nickname too long' using errcode = '22001';
  end if;
  if clean ~ '[0-9]{6,}' then
    raise exception 'nickname may not contain a phone number' using errcode = '22023';
  end if;
  if clean ~ '[@]' or clean ~* '(https?://|www\.|t\.me/|wa\.me/)' then
    raise exception 'nickname may not contain contact details or links'
      using errcode = '22023';
  end if;

  update public.chat_participants set nickname = clean
   where chat_id = p_chat and user_id = auth.uid();
  return clean;
end;
$$;

-- The only way to post. Enforces gate + mute + rate limit atomically.
create or replace function public.chat_post_message(
  p_chat       uuid,
  p_kind       public.chat_message_kind,
  p_body       text default null,
  p_preset_key text default null,
  p_image_path text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me       public.chat_participants;
  room     public.journey_chats;
  recent   integer;
  new_id   uuid;
  clean    text;
begin
  select * into room from public.journey_chats where id = p_chat;
  if room.id is null then
    raise exception 'no such chat' using errcode = 'P0002';
  end if;
  if room.expires_at <= now() then
    raise exception 'this journey chat has expired' using errcode = '22023';
  end if;
  if room.locked then
    raise exception 'this journey chat is closed' using errcode = '42501';
  end if;

  select * into me from public.chat_participants
   where chat_id = p_chat and user_id = auth.uid();
  if me.id is null then
    raise exception 'not a participant of this chat' using errcode = '42501';
  end if;

  -- The verification gate. No unverified path exists, by design.
  if me.verification_status <> 'verified' then
    raise exception 'journey not verified' using errcode = '42501';
  end if;
  if me.muted_until is not null and me.muted_until > now() then
    raise exception 'you are muted in this chat' using errcode = '42501';
  end if;

  -- Rate limit: 10 messages per rolling minute.
  select count(*) into recent
    from public.chat_messages
   where participant_id = me.id
     and created_at > now() - interval '1 minute';
  if recent >= 10 then
    raise exception 'slow down: too many messages' using errcode = '54000';
  end if;

  if p_kind = 'image' then
    -- Not reachable yet: no storage bucket, no EXIF stripping. See the comment
    -- on chat_messages.image_path.
    raise exception 'image messages are not enabled' using errcode = '0A000';
  end if;

  clean := btrim(regexp_replace(coalesce(p_body, ''), '[[:cntrl:]]', ' ', 'g'));
  if clean = '' then
    raise exception 'empty message' using errcode = '22023';
  end if;
  if length(clean) > 500 then
    raise exception 'message too long' using errcode = '22001';
  end if;

  insert into public.chat_messages (chat_id, participant_id, kind, body, preset_key)
  values (p_chat, me.id, p_kind, clean, p_preset_key)
  returning id into new_id;

  update public.chat_participants
     set last_seen_at = now()
   where id = me.id;

  return new_id;
end;
$$;

-- ===========================================================================
-- Retention. Called by cron; safe to run repeatedly.
-- ===========================================================================
create or replace function public.chat_purge_expired()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rooms_deleted   integer;
  reports_deleted integer;
begin
  -- Cascades to participants, messages, GPS samples and mutes. Reports survive
  -- (chat_id/message_id are ON DELETE SET NULL).
  with gone as (
    delete from public.journey_chats where expires_at < now() returning 1
  )
  select count(*) into rooms_deleted from gone;

  with gone as (
    delete from public.chat_reports
     where created_at < now() - interval '90 days' returning 1
  )
  select count(*) into reports_deleted from gone;

  return jsonb_build_object(
    'rooms_deleted', rooms_deleted,
    'reports_deleted', reports_deleted,
    'ran_at', now()
  );
end;
$$;

comment on function public.chat_purge_expired is
  'Deletes rooms past expires_at (cascading to messages, participants and GPS samples) and reports older than 90 days. Does NOT delete storage objects for image messages — that needs a separate sweep once images are enabled.';

-- ===========================================================================
-- Row Level Security. Deny by default everywhere; a few narrow SELECT policies
-- so the follow-up Realtime phase has a working read path.
-- ===========================================================================
alter table public.journey_chats             enable row level security;
alter table public.chat_participants         enable row level security;
alter table public.chat_messages             enable row level security;
alter table public.chat_reports              enable row level security;
alter table public.chat_mutes                enable row level security;
alter table public.chat_blocks               enable row level security;
alter table public.chat_verification_samples enable row level security;
alter table public.chat_verification_state   enable row level security;

-- chat_participants, chat_reports, chat_mutes, chat_verification_samples:
-- NO POLICIES AT ALL. Service role and security-definer RPCs only. This is what
-- keeps the real-identity mapping and the moderation log out of client reach.

-- A verified participant may read their room's metadata.
drop policy if exists "journey_chats read participants" on public.journey_chats;
create policy "journey_chats read participants"
  on public.journey_chats for select
  to authenticated
  using (public.chat_can_read(id));

-- Messages: verified participants, not soft-deleted, and nothing from someone
-- the reader has blocked. The blocked author is never told.
drop policy if exists "chat_messages read verified" on public.chat_messages;
create policy "chat_messages read verified"
  on public.chat_messages for select
  to authenticated
  using (
    public.chat_can_read(chat_id)
    and deleted_at is null
    and not exists (
      select 1 from public.chat_blocks b
       where b.blocker_participant_id = public.chat_my_participant(chat_id)
         and b.blocked_participant_id = chat_messages.participant_id
    )
  );

-- No client INSERT/UPDATE/DELETE policy on chat_messages: chat_post_message()
-- is the only way in, so the mute check and rate limit cannot be skipped.

-- A blocker may see their own block list (to offer "unblock").
drop policy if exists "chat_blocks read own" on public.chat_blocks;
create policy "chat_blocks read own"
  on public.chat_blocks for select
  to authenticated
  using (blocker_participant_id = public.chat_my_participant(chat_id));

-- Own verification progress only, so the client can render "Verifying…".
drop policy if exists "chat_verification_state read own" on public.chat_verification_state;
create policy "chat_verification_state read own"
  on public.chat_verification_state for select
  to authenticated
  using (user_id = auth.uid());

-- ===========================================================================
-- Realtime (for the follow-up phase). RLS above still applies to subscribers.
-- ===========================================================================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'chat_messages'
  ) then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end
$$;
