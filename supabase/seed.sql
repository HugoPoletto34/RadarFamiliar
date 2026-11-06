-- Amigos simulados do protótipo local (botões do flavor dev).
-- Este arquivo só roda no Supabase local (`supabase db reset`); `supabase db push`
-- não envia seeds, então as funções abaixo nunca chegam à nuvem. As funções que o
-- app usa também em produção (proto_*) estão em supabase/migrations.

-- Cria um usuário fictício que já entra no grupo compartilhando, perto de quem chamou.
create or replace function public.dev_add_fake_friend(p_group_id uuid, p_name text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
  v_lat double precision := -23.5505;
  v_lng double precision := -46.6333;
begin
  if not public.is_member(p_group_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;

  select extensions.st_y(geog::extensions.geometry), extensions.st_x(geog::extensions.geometry)
  into v_lat, v_lng
  from public.last_locations where user_id = (select auth.uid());
  v_lat := coalesce(v_lat, -23.5505);
  v_lng := coalesce(v_lng, -46.6333);

  insert into auth.users (
    instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    'fake-' || v_id || '@fake.radarfamiliar.local',
    '{"proto_fake": true}', jsonb_build_object('full_name', p_name), now(), now()
  );

  update public.profiles set birth_date = date '1990-01-01' where id = v_id;

  insert into public.group_members (group_id, user_id, role) values (p_group_id, v_id, 'member');
  insert into public.sharing_settings (group_id, user_id, mode, precision, show_battery, consent_version)
  values (p_group_id, v_id, 'continuous', 'exact', true, 'proto-1');
  insert into public.last_locations (user_id, geog, accuracy_m, battery, recorded_at)
  values (
    v_id,
    extensions.st_setsrid(extensions.st_makepoint(
      v_lng + (random() - 0.5) * 0.02, v_lat + (random() - 0.5) * 0.02), 4326)::extensions.geography,
    15, 50 + floor(random() * 50)::smallint, now()
  );
  return v_id;
end;
$$;

-- Move levemente (até ~50 m) cada amigo fictício do grupo que está compartilhando.
create or replace function public.dev_tick_fake_friends(p_group_id uuid)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  v_count int;
begin
  if not public.is_member(p_group_id) then
    raise exception 'not_a_member' using errcode = '42501';
  end if;

  update public.last_locations l
  set geog = extensions.st_setsrid(extensions.st_makepoint(
        extensions.st_x(l.geog::extensions.geometry) + (random() - 0.5) * 0.001,
        extensions.st_y(l.geog::extensions.geometry) + (random() - 0.5) * 0.001), 4326)::extensions.geography,
      recorded_at = now(),
      received_at = now()
  from public.group_members gm
  join auth.users u on u.id = gm.user_id
  where gm.group_id = p_group_id
    and l.user_id = gm.user_id
    and (u.raw_app_meta_data ->> 'proto_fake')::boolean
    and public.is_sharing(p_group_id, gm.user_id);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Liga ou desliga o compartilhamento de um amigo fictício (para ver o marcador sumir).
create or replace function public.dev_toggle_fake_friend(p_group_id uuid, p_user_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_mode public.sharing_mode;
begin
  if not public.is_member(p_group_id) or not exists (
    select 1 from auth.users
    where id = p_user_id and (raw_app_meta_data ->> 'proto_fake')::boolean
  ) then
    raise exception 'not_a_fake_friend' using errcode = '42501';
  end if;

  update public.sharing_settings
  set mode = case when mode = 'off' then 'continuous'::public.sharing_mode else 'off' end
  where group_id = p_group_id and user_id = p_user_id
  returning mode into v_mode;

  if v_mode = 'continuous' and not exists (select 1 from public.last_locations where user_id = p_user_id) then
    insert into public.last_locations (user_id, geog, accuracy_m, battery, recorded_at)
    select p_user_id, coalesce(
      (select geog from public.last_locations where user_id = (select auth.uid())),
      'SRID=4326;POINT(-46.6333 -23.5505)'::extensions.geography), 15, 60, now();
  end if;
  return v_mode::text;
end;
$$;

revoke execute on function
  public.dev_add_fake_friend(uuid, text),
  public.dev_tick_fake_friends(uuid),
  public.dev_toggle_fake_friend(uuid, uuid)
  from public, anon;
grant execute on function
  public.dev_add_fake_friend(uuid, text),
  public.dev_tick_fake_friends(uuid),
  public.dev_toggle_fake_friend(uuid, uuid)
  to authenticated;
