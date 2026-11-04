import { PGlite } from '@electric-sql/pglite'
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto'
import { postgis } from '@electric-sql/pglite-postgis'
import { pgtap } from '@electric-sql/pglite-pgtap'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

const root = process.argv[2]
const pg = new PGlite({ extensions: { pgcrypto, postgis, pgtap } })

// Stub mínimo do que o Supabase provê: roles, schema extensions e auth.
await pg.exec(`
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;
  create schema extensions;
  grant usage on schema extensions to public;
  create schema auth;
  grant usage on schema auth to anon, authenticated, service_role;
  grant usage on schema public to anon, authenticated, service_role;
  create table auth.users (
    id uuid primary key, email text, raw_user_meta_data jsonb default '{}'
  );
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid
  $$;
  grant execute on function auth.uid() to public;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
  set search_path = public, extensions;
`)

const migDir = join(root, 'supabase', 'migrations')
for (const f of readdirSync(migDir).sort()) {
  try {
    await pg.exec(readFileSync(join(migDir, f), 'utf8'))
    console.log(`OK migration ${f}`)
  } catch (e) {
    console.error(`FALHA migration ${f}: ${e.message}`)
    process.exit(1)
  }
}

const testDir = join(root, 'supabase', 'tests', 'database')
let failed = false
for (const f of readdirSync(testDir).sort()) {
  try {
    const results = await pg.exec(readFileSync(join(testDir, f), 'utf8'))
    for (const r of results) {
      for (const row of r.rows) {
        const v = Object.values(row)[0]
        if (typeof v === 'string' && /^(ok|not ok|1\.\.|#)/.test(v)) {
          console.log(v)
          if (v.startsWith('not ok') || /Looks like you failed/.test(v)) failed = true
        }
      }
    }
  } catch (e) {
    console.error(`ERRO no teste ${f}: ${e.message}`)
    failed = true
    try { await pg.exec('rollback') } catch {}
  }
}
process.exit(failed ? 1 : 0)
