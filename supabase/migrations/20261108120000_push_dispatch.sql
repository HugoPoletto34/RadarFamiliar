-- Envia a fila de push assim que um aviso é gravado.
-- Sem pg_net (checagem local em PGlite) o aviso fica na fila e nada quebra.

create schema if not exists internal;

revoke all on schema internal from public, anon, authenticated;

create table internal.push_hook (
  id int primary key default 1 check (id = 1),
  url text not null,
  bearer text not null
);

alter table internal.push_hook enable row level security;
revoke all on internal.push_hook from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_net') then
    return;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension pg_net;
  end if;
end $$;

create function internal.dispatch_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_bearer text;
  v_schema text;
  v_request_id bigint;
begin
  select n.nspname into v_schema
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where p.proname = 'http_post'
    and n.nspname in ('net', 'extensions', 'public')
  order by case n.nspname when 'net' then 0 when 'extensions' then 1 else 2 end
  limit 1;

  if v_schema is null then
    return new;
  end if;

  select h.url, h.bearer into v_url, v_bearer
  from internal.push_hook h
  where h.id = 1;

  if v_url is null or v_bearer is null or v_url = '' then
    return new;
  end if;

  execute format('select %I.http_post($1, $2, $3, $4, $5)', v_schema)
    into v_request_id
    using v_url,
          jsonb_build_object('id', new.id),
          '{}'::jsonb,
          jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_bearer
          ),
          5000;
  return new;
exception
  when others then
    raise warning 'dispatch_push: %', sqlerrm;
    return new;
end;
$$;

revoke all on function internal.dispatch_push() from public, anon, authenticated;

create trigger notifications_outbox_dispatch
  after insert on public.notifications_outbox
  for each row execute function internal.dispatch_push();

-- O toque no alerta abre o grupo do lugar.
create or replace function public.notify_alert_subject()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.notifications_outbox (user_id, type, payload)
  select new.subject_id, 'alert_created_about_you', jsonb_build_object(
    'alert_id', new.id,
    'place_id', new.place_id,
    'place_name', p.name,
    'group_id', p.group_id,
    'watcher_id', new.watcher_id,
    'watcher_name', pr.display_name
  )
  from public.places p
  left join public.profiles pr on pr.id = new.watcher_id
  where p.id = new.place_id;
  return null;
end;
$$;

revoke execute on function public.notify_alert_subject()
  from public, anon, authenticated;
