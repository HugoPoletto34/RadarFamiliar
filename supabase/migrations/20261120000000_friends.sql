-- Amizades com código pessoal permanente e convites de grupo só entre amigos.
-- Substitui invites por grupo (expiração + limite de usos) e remove o grupo
-- automático "Amigos" (proto_ensure_group).

-- ---------------------------------------------------------------------------
-- Tipos e tabelas
-- ---------------------------------------------------------------------------

create type public.friendship_status as enum ('pending', 'accepted');

create table public.friend_codes (
  user_id uuid primary key references auth.users (id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now(),
  check (code = public.normalize_invite_code(code) and char_length(code) = 8)
);

create table public.friendships (
  requester_id uuid not null references auth.users (id) on delete cascade,
  addressee_id uuid not null references auth.users (id) on delete cascade,
  status public.friendship_status not null default 'pending',
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id),
  check (
    (status = 'pending' and accepted_at is null)
    or (status = 'accepted' and accepted_at is not null)
  )
);
create unique index friendships_pair_uidx
  on public.friendships (
    least(requester_id, addressee_id),
    greatest(requester_id, addressee_id)
  );
create index friendships_addressee_idx on public.friendships (addressee_id);
create index friendships_requester_idx on public.friendships (requester_id);

create table public.group_invites (
  group_id uuid not null references public.groups (id) on delete cascade,
  invitee_id uuid not null references auth.users (id) on delete cascade,
  invited_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, invitee_id)
);
create index group_invites_invitee_idx on public.group_invites (invitee_id);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create function public.generate_friend_code()
returns text
language plpgsql set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code text;
begin
  loop
    v_bytes := extensions.gen_random_bytes(8);
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % length(v_alphabet)) + 1, 1);
    end loop;
    exit when not exists (
      select 1 from public.friend_codes fc where fc.code = v_code
    );
  end loop;
  return v_code;
end;
$$;

create function public.are_friends(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.friendships f
    where f.status = 'accepted'
      and (
        (f.requester_id = p_a and f.addressee_id = p_b)
        or (f.requester_id = p_b and f.addressee_id = p_a)
      )
  );
$$;

create function public.is_connected_to(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select
    p_user_id = (select auth.uid())
    or exists (
      select 1
      from public.friendships f
      where f.status in ('pending', 'accepted')
        and (
          (f.requester_id = (select auth.uid()) and f.addressee_id = p_user_id)
          or (f.addressee_id = (select auth.uid()) and f.requester_id = p_user_id)
        )
    )
    or exists (
      select 1
      from public.group_invites gi
      where (
          gi.invitee_id = (select auth.uid()) and gi.invited_by = p_user_id
        ) or (
          gi.invited_by = (select auth.uid()) and gi.invitee_id = p_user_id
        ) or (
          gi.invitee_id = p_user_id and public.is_admin(gi.group_id)
        )
    );
$$;

revoke execute on function
  public.generate_friend_code(),
  public.are_friends(uuid, uuid),
  public.is_connected_to(uuid)
  from public, anon;
grant execute on function
  public.are_friends(uuid, uuid),
  public.is_connected_to(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Backfill: quem já divide um grupo vira amigo aceito
-- ---------------------------------------------------------------------------

insert into public.friendships (requester_id, addressee_id, status, accepted_at)
select distinct on (
  least(a.user_id, b.user_id),
  greatest(a.user_id, b.user_id)
)
  least(a.user_id, b.user_id),
  greatest(a.user_id, b.user_id),
  'accepted'::public.friendship_status,
  now()
from public.group_members a
join public.group_members b
  on a.group_id = b.group_id and a.user_id < b.user_id
order by
  least(a.user_id, b.user_id),
  greatest(a.user_id, b.user_id);

-- Grupos automáticos "Amigos" só com o criador
delete from public.groups g
where g.name = 'Amigos'
  and g.kind = 'friends'
  and g.created_by is not null
  and (
    select count(*) from public.group_members gm where gm.group_id = g.id
  ) = 1
  and exists (
    select 1 from public.group_members gm
    where gm.group_id = g.id and gm.user_id = g.created_by
  );

-- ---------------------------------------------------------------------------
-- RPCs de código e amizade
-- ---------------------------------------------------------------------------

create function public.my_friend_code()
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_code text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select fc.code into v_code from public.friend_codes fc where fc.user_id = v_uid;
  if v_code is not null then
    return v_code;
  end if;

  v_code := public.generate_friend_code();
  insert into public.friend_codes (user_id, code) values (v_uid, v_code);
  return v_code;
end;
$$;

create function public.regenerate_friend_code()
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_code text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  v_code := public.generate_friend_code();
  insert into public.friend_codes (user_id, code)
  values (v_uid, v_code)
  on conflict (user_id) do update set code = excluded.code, created_at = now();
  return v_code;
end;
$$;

create function public.preview_friend_code(p_code text)
returns table (
  user_id uuid,
  display_name text,
  avatar_url text
)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
  v_norm text := public.normalize_invite_code(p_code);
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if v_norm is null or char_length(v_norm) <> 8 then
    raise exception 'invalid_code' using errcode = 'P0002';
  end if;

  return query
  select pr.id, pr.display_name, pr.avatar_url
  from public.friend_codes fc
  join public.profiles pr on pr.id = fc.user_id
  where fc.code = v_norm;

  if not found then
    raise exception 'invalid_code' using errcode = 'P0002';
  end if;
end;
$$;

create function public.request_friend(p_code text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_norm text := public.normalize_invite_code(p_code);
  v_target uuid;
  v_birth date;
  v_name text;
  v_status public.friendship_status;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select birth_date, display_name into v_birth, v_name
  from public.profiles where id = v_uid;
  if v_birth is null then
    raise exception 'birth_date_required' using errcode = 'P0001';
  end if;

  if v_norm is null or char_length(v_norm) <> 8 then
    raise exception 'invalid_code' using errcode = 'P0002';
  end if;

  select fc.user_id into v_target
  from public.friend_codes fc
  where fc.code = v_norm;
  if v_target is null then
    raise exception 'invalid_code' using errcode = 'P0002';
  end if;
  if v_target = v_uid then
    raise exception 'cannot_friend_self' using errcode = 'P0001';
  end if;

  if public.are_friends(v_uid, v_target) then
    raise exception 'already_friends' using errcode = 'P0001';
  end if;

  -- Pedido no sentido contrário: aceita na hora.
  update public.friendships
  set status = 'accepted', accepted_at = now()
  where requester_id = v_target
    and addressee_id = v_uid
    and status = 'pending'
  returning status into v_status;

  if v_status = 'accepted' then
    insert into public.notifications_outbox (user_id, type, payload)
    values (
      v_target,
      'friend_accepted',
      jsonb_build_object(
        'friend_id', v_uid,
        'friend_name', coalesce(v_name, 'Alguém')
      )
    );
    return 'accepted';
  end if;

  if exists (
    select 1 from public.friendships
    where requester_id = v_uid and addressee_id = v_target
  ) then
    raise exception 'already_pending' using errcode = 'P0001';
  end if;

  insert into public.friendships (requester_id, addressee_id, status)
  values (v_uid, v_target, 'pending');

  insert into public.notifications_outbox (user_id, type, payload)
  values (
    v_target,
    'friend_request',
    jsonb_build_object(
      'friend_id', v_uid,
      'friend_name', coalesce(v_name, 'Alguém')
    )
  );

  return 'pending';
end;
$$;

create function public.respond_friend_request(p_requester_id uuid, p_accept boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_name text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_accept then
    update public.friendships
    set status = 'accepted', accepted_at = now()
    where requester_id = p_requester_id
      and addressee_id = v_uid
      and status = 'pending';
    if not found then
      raise exception 'request_not_found' using errcode = 'P0002';
    end if;

    select display_name into v_name from public.profiles where id = v_uid;
    insert into public.notifications_outbox (user_id, type, payload)
    values (
      p_requester_id,
      'friend_accepted',
      jsonb_build_object(
        'friend_id', v_uid,
        'friend_name', coalesce(v_name, 'Alguém')
      )
    );
  else
    delete from public.friendships
    where requester_id = p_requester_id
      and addressee_id = v_uid
      and status = 'pending';
    if not found then
      raise exception 'request_not_found' using errcode = 'P0002';
    end if;
  end if;
end;
$$;

create function public.cancel_friend_request(p_addressee_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  delete from public.friendships
  where requester_id = v_uid
    and addressee_id = p_addressee_id
    and status = 'pending';
  if not found then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;
end;
$$;

create function public.remove_friend(p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  delete from public.friendships
  where status = 'accepted'
    and (
      (requester_id = v_uid and addressee_id = p_user_id)
      or (requester_id = p_user_id and addressee_id = v_uid)
    );
  if not found then
    raise exception 'friend_not_found' using errcode = 'P0002';
  end if;
end;
$$;

create function public.list_friends()
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  kind text,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  return query
  select
    case when f.requester_id = v_uid then f.addressee_id else f.requester_id end,
    pr.display_name,
    pr.avatar_url,
    case
      when f.status = 'accepted' then 'friend'
      when f.requester_id = v_uid then 'outgoing'
      else 'incoming'
    end,
    f.created_at
  from public.friendships f
  join public.profiles pr on pr.id = case
    when f.requester_id = v_uid then f.addressee_id
    else f.requester_id
  end
  where f.requester_id = v_uid or f.addressee_id = v_uid
  order by
    case
      when f.status = 'accepted' then 2
      when f.addressee_id = v_uid then 0
      else 1
    end,
    coalesce(pr.display_name, ''),
    f.created_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPCs de convite de grupo
-- ---------------------------------------------------------------------------

-- Remove a assinatura antiga antes de criar a nova (evita ambiguidade com default).
drop function if exists public.create_group(text, public.group_kind);

create function public._invite_users_to_group(
  p_group_id uuid,
  p_user_ids uuid[],
  p_invited_by uuid
)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_name text;
  v_count int := 0;
begin
  select display_name into v_name from public.profiles where id = p_invited_by;

  foreach v_id in array coalesce(p_user_ids, '{}'::uuid[]) loop
    if v_id = p_invited_by then
      continue;
    end if;
    if not public.are_friends(p_invited_by, v_id) then
      raise exception 'not_friends' using errcode = 'P0001';
    end if;
    if exists (
      select 1 from public.group_members
      where group_id = p_group_id and user_id = v_id
    ) then
      continue;
    end if;

    insert into public.group_invites (group_id, invitee_id, invited_by)
    values (p_group_id, v_id, p_invited_by)
    on conflict (group_id, invitee_id) do nothing;

    if found then
      v_count := v_count + 1;
      insert into public.notifications_outbox (user_id, type, payload)
      select
        v_id,
        'group_invite',
        jsonb_build_object(
          'group_id', p_group_id,
          'group_name', g.name,
          'invited_by', p_invited_by,
          'invited_by_name', coalesce(v_name, 'Alguém')
        )
      from public.groups g
      where g.id = p_group_id;
    end if;
  end loop;

  return v_count;
end;
$$;

create or replace function public.create_group(
  p_name text,
  p_kind public.group_kind,
  p_invitee_ids uuid[] default '{}'
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_group_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  insert into public.groups (name, kind, created_by)
  values (trim(p_name), p_kind, v_uid)
  returning id into v_group_id;

  insert into public.group_members (group_id, user_id, role)
  values (v_group_id, v_uid, 'admin');

  perform public._invite_users_to_group(v_group_id, p_invitee_ids, v_uid);

  return v_group_id;
end;
$$;

create function public.invite_to_group(p_group_id uuid, p_user_ids uuid[])
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not public.is_admin(p_group_id) then
    raise exception 'not_admin' using errcode = '42501';
  end if;

  return public._invite_users_to_group(p_group_id, p_user_ids, v_uid);
end;
$$;

create function public.cancel_group_invite(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin(p_group_id) then
    raise exception 'not_admin' using errcode = '42501';
  end if;

  delete from public.group_invites
  where group_id = p_group_id and invitee_id = p_user_id;
  if not found then
    raise exception 'invite_not_found' using errcode = 'P0002';
  end if;
end;
$$;

create function public.respond_group_invite(p_group_id uuid, p_accept boolean)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_name text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.group_invites
    where group_id = p_group_id and invitee_id = v_uid
  ) then
    raise exception 'invite_not_found' using errcode = 'P0002';
  end if;

  if not p_accept then
    delete from public.group_invites
    where group_id = p_group_id and invitee_id = v_uid;
    return null;
  end if;

  if not exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = v_uid
  ) then
    insert into public.group_members (group_id, user_id, role)
    values (p_group_id, v_uid, 'member');
  end if;

  delete from public.group_invites
  where group_id = p_group_id and invitee_id = v_uid;

  select display_name into v_name from public.profiles where id = v_uid;

  insert into public.notifications_outbox (user_id, type, payload)
  select gm.user_id, 'member_joined', jsonb_build_object(
    'group_id', p_group_id,
    'member_id', v_uid,
    'member_name', coalesce(v_name, 'Alguém')
  )
  from public.group_members gm
  where gm.group_id = p_group_id and gm.role = 'admin' and gm.user_id <> v_uid;

  return p_group_id;
end;
$$;

create function public.my_group_invites()
returns table (
  group_id uuid,
  group_name text,
  kind public.group_kind,
  invited_by uuid,
  invited_by_name text,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  return query
  select
    gi.group_id,
    g.name,
    g.kind,
    gi.invited_by,
    coalesce(pr.display_name, 'Alguém'),
    gi.created_at
  from public.group_invites gi
  join public.groups g on g.id = gi.group_id
  left join public.profiles pr on pr.id = gi.invited_by
  where gi.invitee_id = v_uid
  order by gi.created_at desc;
end;
$$;

create function public.list_group_pending_invites(p_group_id uuid)
returns table (
  invitee_id uuid,
  display_name text,
  avatar_url text,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not public.is_admin(p_group_id) then
    raise exception 'not_admin' using errcode = '42501';
  end if;

  return query
  select gi.invitee_id, pr.display_name, pr.avatar_url, gi.created_at
  from public.group_invites gi
  join public.profiles pr on pr.id = gi.invitee_id
  where gi.group_id = p_group_id
  order by gi.created_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.friend_codes enable row level security;
alter table public.friendships enable row level security;
alter table public.group_invites enable row level security;

revoke all on public.friend_codes, public.friendships, public.group_invites
  from anon, authenticated;
grant select on public.friend_codes, public.friendships, public.group_invites
  to authenticated;

create policy friend_codes_select on public.friend_codes
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy friendships_select on public.friendships
  for select to authenticated
  using (
    requester_id = (select auth.uid())
    or addressee_id = (select auth.uid())
  );

create policy group_invites_select on public.group_invites
  for select to authenticated
  using (
    invitee_id = (select auth.uid())
    or invited_by = (select auth.uid())
    or public.is_admin(group_id)
  );

drop policy profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    public.shares_group_with(id) or public.is_connected_to(id)
  );

-- ---------------------------------------------------------------------------
-- Remoção do modelo antigo de convite e do grupo automático
-- ---------------------------------------------------------------------------

drop function if exists public.create_invite(uuid, interval, int);
drop function if exists public.preview_invite(text);
drop function if exists public.accept_invite(text);
drop function if exists public.revoke_invite(uuid);
drop function if exists public.find_valid_invite(text);
drop function if exists public.hash_invite_code(text);
drop function if exists public.proto_ensure_group();
drop table if exists public.invites;

revoke execute on function
  public.my_friend_code(),
  public.regenerate_friend_code(),
  public.preview_friend_code(text),
  public.request_friend(text),
  public.respond_friend_request(uuid, boolean),
  public.cancel_friend_request(uuid),
  public.remove_friend(uuid),
  public.list_friends(),
  public._invite_users_to_group(uuid, uuid[], uuid),
  public.create_group(text, public.group_kind, uuid[]),
  public.invite_to_group(uuid, uuid[]),
  public.cancel_group_invite(uuid, uuid),
  public.respond_group_invite(uuid, boolean),
  public.my_group_invites(),
  public.list_group_pending_invites(uuid)
  from public, anon;

revoke execute on function
  public.generate_friend_code(),
  public._invite_users_to_group(uuid, uuid[], uuid)
  from authenticated;

grant execute on function
  public.my_friend_code(),
  public.regenerate_friend_code(),
  public.preview_friend_code(text),
  public.request_friend(text),
  public.respond_friend_request(uuid, boolean),
  public.cancel_friend_request(uuid),
  public.remove_friend(uuid),
  public.list_friends(),
  public.create_group(text, public.group_kind, uuid[]),
  public.invite_to_group(uuid, uuid[]),
  public.cancel_group_invite(uuid, uuid),
  public.respond_group_invite(uuid, boolean),
  public.my_group_invites(),
  public.list_group_pending_invites(uuid)
  to authenticated;
