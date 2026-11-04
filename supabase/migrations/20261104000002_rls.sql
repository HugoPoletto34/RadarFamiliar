-- Funções auxiliares, gatilhos e políticas de RLS (seção 4.3 da especificação).

-- ---------------------------------------------------------------------------
-- Funções auxiliares
-- ---------------------------------------------------------------------------

create function public.is_member(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = (select auth.uid())
  );
$$;

create function public.is_admin(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = (select auth.uid()) and role = 'admin'
  );
$$;

create function public.shares_group_with(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members me
    join public.group_members other on other.group_id = me.group_id
    where me.user_id = (select auth.uid()) and other.user_id = p_user_id
  );
$$;

-- 'sharing', 'paused' ou 'not_sharing' (off, temporário expirado ou sem consentimento).
create function public.sharing_status(
  p_mode public.sharing_mode,
  p_temporary_until timestamptz,
  p_paused_until timestamptz
)
returns text
language sql stable set search_path = ''
as $$
  select case
    when p_mode is null or p_mode = 'off' then 'not_sharing'
    when p_mode = 'temporary' and (p_temporary_until is null or p_temporary_until <= now())
      then 'not_sharing'
    when p_paused_until is not null and p_paused_until > now() then 'paused'
    else 'sharing'
  end;
$$;

create function public.is_sharing(p_group_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select public.sharing_status(s.mode, s.temporary_until, s.paused_until) = 'sharing'
    from public.sharing_settings s
    where s.group_id = p_group_id and s.user_id = p_user_id
  ), false);
$$;

revoke execute on function public.is_member(uuid), public.is_admin(uuid),
  public.shares_group_with(uuid), public.is_sharing(uuid, uuid),
  public.sharing_status(public.sharing_mode, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.is_member(uuid), public.is_admin(uuid),
  public.shares_group_with(uuid), public.is_sharing(uuid, uuid),
  public.sharing_status(public.sharing_mode, timestamptz, timestamptz)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Gatilhos
-- ---------------------------------------------------------------------------

create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    nullif(left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'), 60), ''),
    new.raw_user_meta_data ->> 'avatar_url'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- MVP só para maiores de 18 anos (seção 1 da especificação).
create function public.enforce_adult_birth_date()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.birth_date is not null then
    if new.birth_date > current_date - interval '18 years' then
      raise exception 'underage' using errcode = 'P0001',
        hint = 'O Radar Familiar é só para maiores de 18 anos no momento.';
    end if;
    if new.birth_date < date '1900-01-01' then
      raise exception 'invalid_birth_date' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_enforce_adult
  before insert or update of birth_date on public.profiles
  for each row execute function public.enforce_adult_birth_date();

-- Grupo sem admin passa para o membro mais antigo; grupo vazio é apagado.
create function public.handle_member_removed()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_next uuid;
begin
  if not exists (select 1 from public.group_members where group_id = old.group_id) then
    delete from public.groups where id = old.group_id;
    return null;
  end if;

  if old.role = 'admin' and not exists (
    select 1 from public.group_members where group_id = old.group_id and role = 'admin'
  ) then
    select user_id into v_next
    from public.group_members
    where group_id = old.group_id
    order by joined_at, user_id
    limit 1;

    update public.group_members set role = 'admin'
    where group_id = old.group_id and user_id = v_next;
  end if;
  return null;
end;
$$;

create trigger group_members_after_delete
  after delete on public.group_members
  for each row execute function public.handle_member_removed();

create function public.touch_sharing_settings()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  if new.mode <> 'temporary' then
    new.temporary_until := null;
  end if;
  return new;
end;
$$;

create trigger sharing_settings_touch
  before insert or update on public.sharing_settings
  for each row execute function public.touch_sharing_settings();

-- Prova do consentimento (LGPD, art. 8º §2º) e remoção da última posição
-- quando o titular deixa de compartilhar em todos os grupos.
create function public.log_sharing_change()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.consent_log (user_id, group_id, action, consent_version, details)
  values (
    new.user_id,
    new.group_id,
    case when tg_op = 'INSERT' then 'consent_given' else 'settings_changed' end,
    new.consent_version,
    jsonb_build_object(
      'mode', new.mode,
      'temporary_until', new.temporary_until,
      'paused_until', new.paused_until,
      'precision', new.precision,
      'show_battery', new.show_battery
    )
  );

  if new.mode = 'off' and not exists (
    select 1 from public.sharing_settings
    where user_id = new.user_id and mode <> 'off'
  ) then
    delete from public.last_locations where user_id = new.user_id;
  end if;
  return null;
end;
$$;

create trigger sharing_settings_log
  after insert or update on public.sharing_settings
  for each row execute function public.log_sharing_change();

-- O alvo de um alerta só pode desativá-lo; quem criou pode editar tudo.
create function public.guard_place_alert_update()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if (select auth.uid()) = old.subject_id and (select auth.uid()) <> old.watcher_id then
    if new.active or (to_jsonb(new) - 'active') <> (to_jsonb(old) - 'active') then
      raise exception 'subject_can_only_deactivate' using errcode = '42501';
    end if;
  end if;
  if new.watcher_id <> old.watcher_id or new.subject_id <> old.subject_id
     or new.place_id <> old.place_id then
    raise exception 'immutable_alert_fields' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger place_alerts_guard_update
  before update on public.place_alerts
  for each row execute function public.guard_place_alert_update();

create function public.notify_alert_subject()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.notifications_outbox (user_id, type, payload)
  select new.subject_id, 'alert_created_about_you', jsonb_build_object(
    'alert_id', new.id,
    'place_id', new.place_id,
    'place_name', p.name,
    'watcher_id', new.watcher_id,
    'watcher_name', pr.display_name
  )
  from public.places p
  left join public.profiles pr on pr.id = new.watcher_id
  where p.id = new.place_id;
  return null;
end;
$$;

create trigger place_alerts_notify_subject
  after insert on public.place_alerts
  for each row execute function public.notify_alert_subject();

revoke execute on function public.handle_new_user(), public.enforce_adult_birth_date(),
  public.handle_member_removed(), public.touch_sharing_settings(),
  public.log_sharing_change(), public.guard_place_alert_update(),
  public.notify_alert_subject()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.invites enable row level security;
alter table public.sharing_settings enable row level security;
alter table public.consent_log enable row level security;
alter table public.last_locations enable row level security;
alter table public.places enable row level security;
alter table public.place_alerts enable row level security;
alter table public.place_presence enable row level security;
alter table public.devices enable row level security;
alter table public.notifications_outbox enable row level security;
alter table public.abuse_reports enable row level security;
alter table public.access_logs enable row level security;

-- Tabelas só acessíveis por RPC ou service role: last_locations, place_presence,
-- notifications_outbox (RLS ligada e nenhuma política).
revoke all on public.last_locations, public.place_presence, public.notifications_outbox
  from anon, authenticated;
revoke all on all tables in schema public from anon;

-- profiles
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.shares_group_with(id));

create policy profiles_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

revoke insert, update, delete on public.profiles from authenticated;
grant update (display_name, avatar_url, birth_date) on public.profiles to authenticated;

-- groups (criação pela RPC create_group, que já inclui o criador como admin)
create policy groups_select on public.groups
  for select to authenticated
  using (public.is_member(id));

create policy groups_update on public.groups
  for update to authenticated
  using (public.is_admin(id))
  with check (public.is_admin(id));

create policy groups_delete on public.groups
  for delete to authenticated
  using (public.is_admin(id));

revoke insert, update on public.groups from authenticated;
grant update (name) on public.groups to authenticated;

-- group_members (entrada só pela RPC accept_invite)
create policy group_members_select on public.group_members
  for select to authenticated
  using (public.is_member(group_id));

create policy group_members_delete on public.group_members
  for delete to authenticated
  using (user_id = (select auth.uid()) or public.is_admin(group_id));

revoke insert, update on public.group_members from authenticated;

-- invites (criação e revogação por RPC)
create policy invites_select on public.invites
  for select to authenticated
  using (created_by = (select auth.uid()) or public.is_admin(group_id));

revoke insert, update, delete on public.invites from authenticated;

-- sharing_settings: membros leem; só o próprio titular grava.
create policy sharing_settings_select on public.sharing_settings
  for select to authenticated
  using (public.is_member(group_id));

create policy sharing_settings_insert on public.sharing_settings
  for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_member(group_id));

create policy sharing_settings_update on public.sharing_settings
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

revoke update, delete on public.sharing_settings from authenticated;
grant update (mode, temporary_until, paused_until, precision, show_battery, consent_version)
  on public.sharing_settings to authenticated;

-- consent_log e access_logs: cada um vê só os próprios; escrita por gatilho/RPC.
create policy consent_log_select on public.consent_log
  for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete on public.consent_log from authenticated;

create policy access_logs_select on public.access_logs
  for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete on public.access_logs from authenticated;

-- places
create policy places_select on public.places
  for select to authenticated
  using (public.is_member(group_id));

create policy places_insert on public.places
  for insert to authenticated
  with check (public.is_member(group_id) and created_by = (select auth.uid()));

create policy places_update on public.places
  for update to authenticated
  using (created_by = (select auth.uid()) or public.is_admin(group_id))
  with check (public.is_member(group_id));

create policy places_delete on public.places
  for delete to authenticated
  using (created_by = (select auth.uid()) or public.is_admin(group_id));

-- place_alerts: só sobre quem está no mesmo grupo e compartilhando.
create policy place_alerts_select on public.place_alerts
  for select to authenticated
  using (watcher_id = (select auth.uid()) or subject_id = (select auth.uid()));

create policy place_alerts_insert on public.place_alerts
  for insert to authenticated
  with check (
    watcher_id = (select auth.uid())
    and exists (
      select 1 from public.places p
      where p.id = place_id
        and public.is_member(p.group_id)
        and public.is_sharing(p.group_id, subject_id)
    )
  );

create policy place_alerts_update on public.place_alerts
  for update to authenticated
  using (watcher_id = (select auth.uid()) or subject_id = (select auth.uid()))
  with check (watcher_id = (select auth.uid()) or subject_id = (select auth.uid()));

create policy place_alerts_delete on public.place_alerts
  for delete to authenticated
  using (watcher_id = (select auth.uid()));

-- devices: leitura e remoção dos próprios; gravação pela RPC register_device.
create policy devices_select on public.devices
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy devices_delete on public.devices
  for delete to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update on public.devices from authenticated;

-- abuse_reports
create policy abuse_reports_insert on public.abuse_reports
  for insert to authenticated
  with check (reporter_id = (select auth.uid()));

create policy abuse_reports_select on public.abuse_reports
  for select to authenticated
  using (reporter_id = (select auth.uid()));
revoke update, delete on public.abuse_reports from authenticated;
