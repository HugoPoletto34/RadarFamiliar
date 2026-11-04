-- Testes de RLS e RPCs. Rodar com: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

-- Ana (admin), João, Bia: membros da Família. Ana e João: Amigos. Carlos: de fora.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@teste.local', '{"full_name": "Ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'joao@teste.local', '{"full_name": "João"}'),
  ('00000000-0000-0000-0000-00000000000c', 'bia@teste.local', '{"full_name": "Bia"}'),
  ('00000000-0000-0000-0000-00000000000d', 'carlos@teste.local', '{"full_name": "Carlos"}');
update public.profiles set birth_date = '1990-01-01';

insert into public.groups (id, name, kind, created_by) values
  ('10000000-0000-0000-0000-000000000001', 'Família', 'family', '00000000-0000-0000-0000-00000000000a'),
  ('10000000-0000-0000-0000-000000000002', 'Amigos', 'friends', '00000000-0000-0000-0000-00000000000a');
insert into public.group_members (group_id, user_id, role) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'admin'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'member'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c', 'member'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'admin'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b', 'member');
insert into public.sharing_settings (group_id, user_id, mode, paused_until, precision, show_battery, consent_version) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'continuous', null, 'exact', true, 'v1'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'continuous', null, 'approx', true, 'v1'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c', 'continuous', now() + interval '1 hour', 'exact', true, 'v1'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'continuous', null, 'exact', false, 'v1'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b', 'off', null, 'approx', false, 'v1');
insert into public.last_locations (user_id, geog, accuracy_m, battery, recorded_at) values
  ('00000000-0000-0000-0000-00000000000a', 'SRID=4326;POINT(-46.633308 -23.550520)', 10, 80, now()),
  ('00000000-0000-0000-0000-00000000000b', 'SRID=4326;POINT(-46.655881 -23.561414)', 12, 55, now()),
  ('00000000-0000-0000-0000-00000000000c', 'SRID=4326;POINT(-46.600000 -23.500000)', 8, 40, now());

-- Quem está fora do grupo não vê nada ---------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000d", "role": "authenticated"}', true);

select is((select count(*) from public.groups), 0::bigint, 'de fora: não vê grupos');
select is((select count(*) from public.group_members), 0::bigint, 'de fora: não vê membros');
select is((select count(*) from public.sharing_settings), 0::bigint, 'de fora: não vê compartilhamento');
select is((select count(*) from public.profiles), 1::bigint, 'de fora: vê só o próprio perfil');
select throws_ok(
  $$select * from public.get_group_locations('10000000-0000-0000-0000-000000000001')$$,
  '42501', null, 'de fora: get_group_locations é negado'
);
select throws_ok($$select * from public.last_locations$$, '42501', null, 'last_locations não é legível');
select throws_ok(
  $$update public.profiles set birth_date = current_date - interval '10 years'
    where id = '00000000-0000-0000-0000-00000000000d'$$,
  'P0001', 'underage', 'menor de 18 é bloqueado'
);
select is(
  public.ingest_location(-23.5, -46.6) ->> 'reason', 'not_sharing',
  'quem não compartilha em nenhum grupo não grava posição'
);

-- Admin não altera o compartilhamento de outro -----------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);

update public.sharing_settings set mode = 'off'
where user_id = '00000000-0000-0000-0000-00000000000b';
select throws_ok(
  $$insert into public.sharing_settings (group_id, user_id, mode, consent_version)
    values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000c', 'continuous', 'v1')$$,
  '42501', null, 'ninguém cria compartilhamento em nome de outro'
);
select throws_ok(
  $$insert into public.group_members (group_id, user_id)
    values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000d')$$,
  '42501', null, 'entrada no grupo só por convite'
);
select is(
  public.ingest_location(-23.55, -46.63) ->> 'reason', 'rate_limited',
  'no máximo 1 posição a cada 20 s'
);

-- Leitura de posições pela RPC ---------------------------------------------
create temp table locs on commit drop as
  select * from public.get_group_locations('10000000-0000-0000-0000-000000000001');

select is(
  (select status from locs where user_id = '00000000-0000-0000-0000-00000000000c'),
  'paused', 'pausado aparece como pausado'
);
select ok(
  (select lat is null and lng is null and battery is null and last_seen_at is null
   from locs where user_id = '00000000-0000-0000-0000-00000000000c'),
  'pausado não expõe coordenadas, bateria nem horário'
);
select ok(
  (select lat <> -23.561414 and lng <> -46.655881 and accuracy_m is null
   from locs where user_id = '00000000-0000-0000-0000-00000000000b'),
  'aproximado nunca devolve a coordenada exata'
);
select is(
  (select array[round(lat::numeric, 4), round(lng::numeric, 4)]
   from locs where user_id = '00000000-0000-0000-0000-00000000000b'),
  array[-23.5600, -46.6600]::numeric[], 'aproximado cai na grade de ~2 km'
);
select is(
  (select array[lat, lng] from locs where user_id = '00000000-0000-0000-0000-00000000000a'),
  array[-23.550520, -46.633308]::double precision[], 'o próprio titular vê a posição exata'
);

-- Simetria só em Amigos ----------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated"}', true);
select is(
  (select lat from public.get_group_locations('10000000-0000-0000-0000-000000000002')
   where user_id = '00000000-0000-0000-0000-00000000000a'),
  null, 'Amigos: quem não compartilha não vê coordenadas'
);
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000c", "role": "authenticated"}', true);
select isnt(
  (select lat from public.get_group_locations('10000000-0000-0000-0000-000000000001')
   where user_id = '00000000-0000-0000-0000-00000000000a'),
  null, 'Família: é possível ver sem compartilhar'
);

-- Convites -----------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);
select set_config('test.code',
  (select code from public.create_invite('10000000-0000-0000-0000-000000000001')), true);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000d", "role": "authenticated"}', true);
select is(
  (select group_name from public.preview_invite(lower(current_setting('test.code')))),
  'Família', 'prévia do convite mostra o grupo'
);
select is(
  public.accept_invite(current_setting('test.code')),
  '10000000-0000-0000-0000-000000000001'::uuid, 'convite válido coloca no grupo'
);
select is((select count(*) from public.groups), 1::bigint, 'novo membro passa a ver o grupo');

-- Alertas de lugar ---------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);
insert into public.places (id, group_id, name, center, radius_m, created_by) values (
  '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Casa',
  'SRID=4326;POINT(-46.633308 -23.550520)', 200, '00000000-0000-0000-0000-00000000000a'
);
select throws_ok(
  $$insert into public.place_alerts (place_id, watcher_id, subject_id) values
    ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000c')$$,
  '42501', null, 'não cria alerta sobre quem está pausado'
);
insert into public.place_alerts (place_id, watcher_id, subject_id) values
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b');

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated"}', true);
select throws_ok(
  $$update public.place_alerts set on_exit = true$$,
  '42501', 'subject_can_only_deactivate', 'o alvo do alerta não edita o alerta'
);
update public.place_alerts set active = false;

reset role;
select is(
  (select active from public.place_alerts), false, 'o alvo do alerta pode desativá-lo'
);
select is(
  (select sharing_settings.mode::text from public.sharing_settings
   where user_id = '00000000-0000-0000-0000-00000000000b' and group_id = '10000000-0000-0000-0000-000000000001'),
  'continuous', 'admin não alterou o compartilhamento de outro membro'
);
select is(
  (select count(*) from public.notifications_outbox
   where user_id = '00000000-0000-0000-0000-00000000000b' and type = 'alert_created_about_you'),
  1::bigint, 'o alvo é avisado quando criam um alerta sobre ele'
);
select is(
  (select count(*) from public.notifications_outbox
   where user_id = '00000000-0000-0000-0000-00000000000a' and type = 'member_joined'),
  1::bigint, 'o admin é avisado quando alguém entra'
);

select * from finish();
rollback;
