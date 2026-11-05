# Supabase de produção (depois de criar o projeto)

Passos curtos para ligar o projeto já criado no painel a este repositório. O contexto completo (SMTP, Codemagic, lojas) está em [codemagic.md](codemagic.md).

## 1. Copiar do painel

| Onde | O quê | Vai para |
| --- | --- | --- |
| Settings → General → **Project ID** (o "ref", ex.: `abcd1234efgh5678ijkl`) | ref | `supabase link --project-ref` |
| Settings → API Keys (ou Connect) → **Project URL** (`https://<ref>.supabase.co`) | URL | `SUPABASE_URL` |
| Settings → API Keys → **Publishable key** (`sb_publishable_...`), ou a legada **anon** | chave pública | `SUPABASE_PUBLISHABLE_KEY` |
| A senha do banco definida ao criar o projeto | senha | pedida pelo `supabase link` |

A **secret key** / `service_role` não é usada: o projeto não tem Edge Functions. Não a coloque no app, no `env/*.json`, no Codemagic nem no chat.

## 2. Ligar e subir as migrations

Na raiz do repositório:

```powershell
supabase login                               # abre o navegador e salva o token na máquina
supabase link --project-ref <ref>            # pede a senha do banco
supabase db push --dry-run                   # deve listar as 3 migrations de supabase/migrations
supabase db push
supabase migration list                      # colunas Local e Remote iguais
```

As migrations criam as extensões que usam (PostGIS e pgcrypto, no schema `extensions`).

**Não rode o seed em produção.** `supabase db push` não envia o `supabase/seed.sql`, então nunca use `--include-seed`, nem `supabase db reset --linked`, que apaga o banco remoto. O seed cria as funções do protótipo (`proto_*`, `dev_*`) e amigos falsos em `auth.users`, e só existe no banco local.

## 3. E-mail com código (OTP)

No painel, em **Authentication**:

1. **Sign In / Providers → Email**: ligado, "Confirm email" ligado, *Email OTP length* 6, *Email OTP expiration* 3600.
2. **Emails → Templates**, em **Magic Link** e **Confirm signup**:
   - assunto `Seu código do Radar Familiar`;
   - corpo copiado de `supabase/templates/otp.html`. O que importa é o `{{ .Token }}`: sem ele, o e-mail leva um link em vez do código que o app pede.
3. **URL Configuration → Redirect URLs**: adicione `br.com.radarfamiliar://login-callback`.
4. Antes de ter usuários reais, configure **SMTP próprio** (Emails → SMTP Settings). O SMTP embutido só envia para membros da organização e tem limite baixo.

## 4. Configurar o app

Copie `env/prod.example.json` para `env/prod.json` (fora do git) e preencha a URL e a publishable key:

```powershell
Copy-Item env\prod.example.json env\prod.json
flutter run --flavor prod --dart-define-from-file=env/prod.json
```

No Codemagic, os mesmos valores vão no grupo `radar_prod` (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`).

O app ainda chama as RPCs do protótipo `proto_ensure_group` e `proto_set_sharing`, que só existem no seed local. Contra a nuvem, o login funciona, mas o mapa mostra erro até essas funções virarem migration (ver [codemagic.md](codemagic.md), seção 1.5).
