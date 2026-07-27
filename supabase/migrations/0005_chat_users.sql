-- ===========================================================================
-- My Train — chat account state (age attestation)
--
-- One row per account, independent of any journey. This is the "have you
-- attested to being 18+" record that gates chat entry, separate from
-- chat_participants (which is per-journey and pseudonymous).
--
-- WHY AN RPC RATHER THAN A CLIENT INSERT
-- The client must not be able to choose `user_id` or `attested_at`. With an
-- insert policy, any signed-in user could attest on another account's behalf or
-- backdate the record. So: RLS lets a user READ their own row and nothing else,
-- and the only write path is chat_attest_age(), which derives user_id from
-- auth.uid() and timestamps server-side.
--
-- NOTE ON ENFORCEMENT (see report): this table records the attestation, but
-- chat-join does not yet consult it — that function is out of scope for this
-- pass. Until it does, the age gate is enforced client-side only.
-- ===========================================================================

create table if not exists public.chat_users (
  user_id           uuid primary key references auth.users(id) on delete cascade,

  -- The user's own declaration. Self-attestation is weak by nature; it is a
  -- deliberate record of what they claimed and when, not proof of age.
  is_adult          boolean     not null,

  attested_at       timestamptz not null default now(),

  -- Bumped when someone re-attests (e.g. declined, came back later). Keeps a
  -- signal that a "no" was later changed to a "yes".
  attestation_count integer     not null default 1,

  updated_at        timestamptz not null default now()
);

comment on table public.chat_users is
  'Per-account chat eligibility. is_adult is a self-attestation, written only via chat_attest_age(); clients may read their own row and nothing else.';

alter table public.chat_users enable row level security;

-- Read your own row (so the client can skip the prompt on a return visit).
drop policy if exists "chat_users read own" on public.chat_users;
create policy "chat_users read own"
  on public.chat_users for select
  to authenticated
  using (user_id = auth.uid());

-- No insert/update/delete policies on purpose: chat_attest_age() is the only
-- write path.

create or replace function public.chat_attest_age(p_is_adult boolean)
returns table (is_adult boolean, attested_at timestamptz, attestation_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_is_adult is null then
    raise exception 'p_is_adult is required' using errcode = '22023';
  end if;

  insert into public.chat_users (user_id, is_adult, attested_at, updated_at)
  values (uid, p_is_adult, now(), now())
  on conflict (user_id) do update
     set is_adult          = excluded.is_adult,
         attested_at       = now(),
         attestation_count = public.chat_users.attestation_count + 1,
         updated_at        = now();

  return query
    select c.is_adult, c.attested_at, c.attestation_count
      from public.chat_users c
     where c.user_id = uid;
end;
$$;

comment on function public.chat_attest_age is
  'Records the caller''s age self-attestation. user_id comes from auth.uid() and timestamps are server-side, so a client cannot attest for another account or backdate it.';
