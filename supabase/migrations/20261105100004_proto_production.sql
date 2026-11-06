-- Funções usadas pelo app ao abrir o mapa: grupo "Amigos" automático do usuário
-- e ligar/desligar o próprio compartilhamento. Vieram do protótipo (antes só no
-- supabase/seed.sql); as funções dev_* de amigos simulados continuam só no seed.

-- Grupo "Amigos" do usuário, criado no primeiro login.
create or replace function public.proto_ensure_group()
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

  update public.profiles p
  set display_name = left(split_part(u.email, '@', 1), 60)
  from auth.users u
  where p.id = v_uid and u.id = v_uid and p.display_name is null;

  select g.id into v_group_id
  from public.groups g
  join public.group_members gm on gm.group_id = g.id and gm.user_id = v_uid
  where g.created_by = v_uid and g.name = 'Amigos'
  order by g.created_at
  limit 1;

  if v_group_id is null then
    insert into public.groups (name, kind, created_by)
    values ('Amigos', 'friends', v_uid)
    returning id into v_group_id;
    insert into public.group_members (group_id, user_id, role)
    values (v_group_id, v_uid, 'admin');
  end if;

  return v_group_id;
end;
$$;

-- Liga ou desliga o próprio compartilhamento. p_minutes nulo = até desligar.
-- Roda com as permissões do usuário, então a RLS de sharing_settings vale.
create or replace function public.proto_set_sharing(p_group_id uuid, p_on boolean, p_minutes int default null)
returns timestamptz
language plpgsql security invoker set search_path = ''
as $$
declare
  v_mode public.sharing_mode := case
    when not p_on then 'off'
    when p_minutes is null then 'continuous'
    else 'temporary'
  end;
  v_until timestamptz := case when p_on and p_minutes is not null
    then now() + make_interval(mins => p_minutes) end;
begin
  insert into public.sharing_settings (group_id, user_id, mode, temporary_until, precision, consent_version)
  values (p_group_id, (select auth.uid()), v_mode, v_until, 'exact', 'proto-1')
  on conflict (group_id, user_id) do update set
    mode = excluded.mode,
    temporary_until = excluded.temporary_until,
    paused_until = null,
    precision = excluded.precision,
    consent_version = excluded.consent_version;
  return v_until;
end;
$$;

revoke execute on function
  public.proto_ensure_group(),
  public.proto_set_sharing(uuid, boolean, int)
  from public, anon;
grant execute on function
  public.proto_ensure_group(),
  public.proto_set_sharing(uuid, boolean, int)
  to authenticated;
