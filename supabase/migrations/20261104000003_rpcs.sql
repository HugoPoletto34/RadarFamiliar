-- RPCs do protótipo: grupos, convites, envio e leitura de posições, dispositivos.
-- Cercas no servidor, Realtime e push entram nos marcos M3 e M4.

create function public.create_group(p_name text, p_kind public.group_kind)
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

  return v_group_id;
end;
$$;

create function public.normalize_invite_code(p_code text)
returns text
language sql immutable set search_path = ''
as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create function public.hash_invite_code(p_code text)
returns text
language sql immutable set search_path = ''
as $$
  select encode(sha256(convert_to(public.normalize_invite_code(p_code), 'UTF8')), 'hex');
$$;

-- Devolve o código em claro uma única vez; o banco guarda só o hash.
create function public.create_invite(
  p_group_id uuid,
  p_valid_for interval default interval '7 days',
  p_max_uses int default 10
)
returns table (invite_id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_code text;
begin
  if not public.is_member(p_group_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;
  if p_valid_for < interval '1 hour' or p_valid_for > interval '30 days' then
    raise exception 'invalid_validity' using errcode = '22023';
  end if;

  loop
    v_bytes := extensions.gen_random_bytes(8);
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % length(v_alphabet)) + 1, 1);
    end loop;
    exit when not exists (
      select 1 from public.invites i where i.code_hash = public.hash_invite_code(v_code)
    );
  end loop;

  return query
  insert into public.invites (group_id, code_hash, created_by, expires_at, max_uses)
  values (p_group_id, public.hash_invite_code(v_code), (select auth.uid()), now() + p_valid_for, p_max_uses)
  returning invites.id, v_code, invites.expires_at;
end;
$$;

create function public.find_valid_invite(p_code text)
returns public.invites
language sql stable security definer set search_path = ''
as $$
  select *
  from public.invites
  where code_hash = public.hash_invite_code(p_code)
    and revoked_at is null
    and expires_at > now()
    and uses < max_uses;
$$;

-- Tela 7 (prévia do convite): quem convida e quem já está no grupo.
create function public.preview_invite(p_code text)
returns table (
  group_id uuid,
  group_name text,
  kind public.group_kind,
  member_names text[],
  invited_by text,
  expires_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_invite public.invites;
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  v_invite := public.find_valid_invite(p_code);
  if v_invite.id is null then
    raise exception 'invalid_invite' using errcode = 'P0002';
  end if;

  return query
  select g.id, g.name, g.kind,
    array(
      select coalesce(pr.display_name, 'Sem nome')
      from public.group_members gm
      join public.profiles pr on pr.id = gm.user_id
      where gm.group_id = g.id
      order by gm.joined_at
    ),
    (select pr.display_name from public.profiles pr where pr.id = v_invite.created_by),
    v_invite.expires_at
  from public.groups g
  where g.id = v_invite.group_id;
end;
$$;

create function public.accept_invite(p_code text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_invite public.invites;
  v_birth date;
  v_name text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select birth_date, display_name into v_birth, v_name
  from public.profiles where id = v_uid;
  if v_birth is null then
    raise exception 'birth_date_required' using errcode = 'P0001';
  end if;

  select * into v_invite
  from public.invites
  where code_hash = public.hash_invite_code(p_code)
  for update;

  if v_invite.id is null or v_invite.revoked_at is not null
     or v_invite.expires_at <= now() or v_invite.uses >= v_invite.max_uses then
    raise exception 'invalid_invite' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.group_members
    where group_id = v_invite.group_id and user_id = v_uid
  ) then
    return v_invite.group_id;
  end if;

  insert into public.group_members (group_id, user_id, role)
  values (v_invite.group_id, v_uid, 'member');

  update public.invites set uses = uses + 1 where id = v_invite.id;

  insert into public.notifications_outbox (user_id, type, payload)
  select gm.user_id, 'member_joined', jsonb_build_object(
    'group_id', v_invite.group_id,
    'member_id', v_uid,
    'member_name', v_name
  )
  from public.group_members gm
  where gm.group_id = v_invite.group_id and gm.role = 'admin' and gm.user_id <> v_uid;

  return v_invite.group_id;
end;
$$;

create function public.revoke_invite(p_invite_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.invites
  set revoked_at = now()
  where id = p_invite_id
    and revoked_at is null
    and (created_by = (select auth.uid()) or public.is_admin(group_id));

  if not found then
    raise exception 'invite_not_found' using errcode = 'P0002';
  end if;
end;
$$;

-- Recebe a posição do próprio usuário. Uma linha por usuário, sem histórico.
create function public.ingest_location(
  p_lat double precision,
  p_lng double precision,
  p_accuracy_m real default null,
  p_speed real default null,
  p_battery smallint default null,
  p_recorded_at timestamptz default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_recorded timestamptz := least(coalesce(p_recorded_at, now()), now());
  v_prev public.last_locations;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid_coordinates' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.sharing_settings where user_id = v_uid and mode <> 'off'
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'not_sharing');
  end if;

  select * into v_prev from public.last_locations where user_id = v_uid for update;

  if v_prev.user_id is not null then
    if v_prev.received_at > now() - interval '20 seconds' then
      return jsonb_build_object('accepted', false, 'reason', 'rate_limited');
    end if;
    if v_recorded <= v_prev.recorded_at then
      return jsonb_build_object('accepted', false, 'reason', 'stale');
    end if;
  end if;

  insert into public.last_locations (user_id, geog, accuracy_m, speed, battery, recorded_at, received_at)
  values (
    v_uid,
    extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography,
    p_accuracy_m,
    p_speed,
    p_battery,
    v_recorded,
    now()
  )
  on conflict (user_id) do update set
    geog = excluded.geog,
    accuracy_m = excluded.accuracy_m,
    speed = excluded.speed,
    battery = excluded.battery,
    recorded_at = excluded.recorded_at,
    received_at = excluded.received_at;

  return jsonb_build_object('accepted', true);
end;
$$;

-- Única forma de ler posições. Aplica pausa, modo, precisão e bateria por membro.
-- Grupos de amigos exigem simetria (quem não compartilha não vê coordenadas);
-- na Família é permitido ver sem compartilhar.
create function public.get_group_locations(p_group_id uuid)
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  role public.member_role,
  status text,
  "precision" public.location_precision,
  lat double precision,
  lng double precision,
  accuracy_m real,
  battery smallint,
  last_seen_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
  v_kind public.group_kind;
  v_caller_sharing boolean;
begin
  if not public.is_member(p_group_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;

  select g.kind into v_kind from public.groups g where g.id = p_group_id;
  v_caller_sharing := public.is_sharing(p_group_id, v_uid);

  return query
  select
    gm.user_id,
    pr.display_name,
    pr.avatar_url,
    gm.role,
    st.status,
    s.precision,
    extensions.st_y(pt.geom),
    extensions.st_x(pt.geom),
    case when v.visible and not v.approx then l.accuracy_m end,
    case when v.visible and (v.is_self or s.show_battery) then l.battery end,
    case
      when not v.visible then null
      when v.approx then date_bin(interval '15 minutes', l.recorded_at, timestamptz '2000-01-01')
      else l.recorded_at
    end
  from public.group_members gm
  join public.profiles pr on pr.id = gm.user_id
  left join public.sharing_settings s on s.group_id = gm.group_id and s.user_id = gm.user_id
  left join public.last_locations l on l.user_id = gm.user_id
  cross join lateral (
    select public.sharing_status(s.mode, s.temporary_until, s.paused_until) as status
  ) st
  cross join lateral (
    select
      gm.user_id = v_uid as is_self,
      l.user_id is not null and (
        gm.user_id = v_uid
        or (st.status = 'sharing' and (v_kind = 'family' or v_caller_sharing))
      ) as visible,
      gm.user_id <> v_uid and s.precision = 'approx' as approx
  ) v
  cross join lateral (
    select case
      when not v.visible then null
      when v.approx then extensions.st_snaptogrid(l.geog::extensions.geometry, 0.02)
      else l.geog::extensions.geometry
    end as geom
  ) pt
  where gm.group_id = p_group_id
  order by gm.joined_at;
end;
$$;

create function public.register_device(
  p_platform text,
  p_fcm_token text,
  p_app_version text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  insert into public.devices (user_id, platform, fcm_token, app_version, last_seen_at)
  values (v_uid, p_platform, p_fcm_token, p_app_version, now())
  on conflict (fcm_token) do update set
    user_id = excluded.user_id,
    platform = excluded.platform,
    app_version = excluded.app_version,
    last_seen_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function
  public.create_group(text, public.group_kind),
  public.normalize_invite_code(text),
  public.hash_invite_code(text),
  public.create_invite(uuid, interval, int),
  public.find_valid_invite(text),
  public.preview_invite(text),
  public.accept_invite(text),
  public.revoke_invite(uuid),
  public.ingest_location(double precision, double precision, real, real, smallint, timestamptz),
  public.get_group_locations(uuid),
  public.register_device(text, text, text)
  from public, anon;

revoke execute on function public.find_valid_invite(text) from authenticated;

grant execute on function
  public.create_group(text, public.group_kind),
  public.create_invite(uuid, interval, int),
  public.preview_invite(text),
  public.accept_invite(text),
  public.revoke_invite(uuid),
  public.ingest_location(double precision, double precision, real, real, smallint, timestamptz),
  public.get_group_locations(uuid),
  public.register_device(text, text, text)
  to authenticated;
