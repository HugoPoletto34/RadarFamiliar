-- Radar Familiar: esquema base (seção 4.2 da especificação).
-- Sem histórico de localização: last_locations guarda só a última posição.

create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create type public.group_kind as enum ('family', 'friends');
create type public.member_role as enum ('admin', 'member', 'guardian');
create type public.sharing_mode as enum ('off', 'continuous', 'temporary');
create type public.location_precision as enum ('exact', 'approx');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) between 1 and 60),
  avatar_url text,
  birth_date date,
  created_at timestamptz not null default now()
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  kind public.group_kind not null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  plan text not null default 'free'
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.member_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_id_idx on public.group_members (user_id);

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  code_hash text not null unique,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  max_uses int not null default 10 check (max_uses between 1 and 50),
  uses int not null default 0 check (uses >= 0),
  revoked_at timestamptz
);
create index invites_group_id_idx on public.invites (group_id);

create table public.sharing_settings (
  group_id uuid not null,
  user_id uuid not null,
  mode public.sharing_mode not null default 'off',
  temporary_until timestamptz,
  paused_until timestamptz,
  precision public.location_precision not null default 'exact',
  show_battery boolean not null default false,
  consent_version text not null,
  updated_at timestamptz not null default now(),
  primary key (group_id, user_id),
  foreign key (group_id, user_id)
    references public.group_members (group_id, user_id) on delete cascade,
  check (mode <> 'temporary' or temporary_until is not null)
);
create index sharing_settings_user_id_idx on public.sharing_settings (user_id);

-- Sem FK: o registro de consentimento sobrevive (pseudonimizado) à exclusão da conta.
create table public.consent_log (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  group_id uuid,
  action text not null,
  consent_version text,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index consent_log_user_id_idx on public.consent_log (user_id);

create table public.last_locations (
  user_id uuid primary key references auth.users (id) on delete cascade,
  geog extensions.geography(point, 4326) not null,
  accuracy_m real check (accuracy_m >= 0),
  speed real,
  battery smallint check (battery between 0 and 100),
  recorded_at timestamptz not null,
  received_at timestamptz not null default now()
);

create table public.places (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  center extensions.geography(point, 4326) not null,
  radius_m int not null check (radius_m between 150 and 500),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index places_group_id_idx on public.places (group_id);
create index places_center_gist on public.places using gist (center);

create table public.place_alerts (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references public.places (id) on delete cascade,
  watcher_id uuid not null references auth.users (id) on delete cascade,
  subject_id uuid not null references auth.users (id) on delete cascade,
  on_enter boolean not null default true,
  on_exit boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (place_id, watcher_id, subject_id),
  check (watcher_id <> subject_id),
  check (on_enter or on_exit)
);
create index place_alerts_subject_id_idx on public.place_alerts (subject_id);

create table public.place_presence (
  place_id uuid not null references public.places (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  inside boolean not null,
  changed_at timestamptz not null default now(),
  primary key (place_id, user_id)
);

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null check (platform in ('android', 'ios')),
  fcm_token text not null unique,
  app_version text,
  last_seen_at timestamptz not null default now()
);
create index devices_user_id_idx on public.devices (user_id);

create table public.notifications_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  type text not null,
  payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  error text
);
create index notifications_outbox_pending_idx
  on public.notifications_outbox (created_at) where sent_at is null;

create table public.abuse_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references auth.users (id) on delete set null,
  group_id uuid references public.groups (id) on delete set null,
  reported_user_id uuid references auth.users (id) on delete set null,
  reason text not null check (char_length(reason) between 1 and 2000),
  created_at timestamptz not null default now(),
  status text not null default 'open' check (status in ('open', 'reviewing', 'closed'))
);

-- Marco Civil, art. 15: retenção de 6 meses. Sem FK para sobreviver à exclusão da conta.
create table public.access_logs (
  id bigint generated always as identity primary key,
  user_id uuid,
  ip inet,
  event text not null,
  created_at timestamptz not null default now()
);
create index access_logs_created_at_idx on public.access_logs (created_at);
