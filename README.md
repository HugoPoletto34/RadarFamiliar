# Radar Familiar

App Flutter (Android e iOS) para grupos de família e amigos compartilharem localização de forma consensual. Backend no Supabase (Postgres + PostGIS), push via FCM.

Este repositório está no **Marco M0 (Fundação)**: app "olá mundo" com login por código no e-mail, flavors `dev` e `prod`, esquema inicial do banco com RLS, RPCs e testes pgTAP, e CI.

## Estrutura

```
lib/
  main.dart                 inicializa Supabase e Firebase (opcional)
  app/                      MaterialApp e roteamento por sessão
  core/config/              variáveis de ambiente (--dart-define-from-file)
  core/supabase/            cliente Supabase com sessão no Keystore/Keychain
  core/push/                Firebase (só FCM)
  features/auth/            login por código de 6 dígitos no e-mail
  features/home/            tela inicial
env/                        dev.example.json e prod.example.json (copie sem ".example")
supabase/
  migrations/               esquema, RLS e RPCs
  tests/database/           testes pgTAP
  templates/otp.html        e-mail com o código de acesso
tool/db_check/              valida migrations e testes sem Docker (PGlite)
.github/workflows/ci.yml    analyze, testes, build Android/iOS e testes do banco
```

## Pré-requisitos

- Flutter 3.44 (stable), Android Studio com Android SDK, Git.
- [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) 3.x.
- Docker Desktop (para o Supabase local). Sem Docker, use `tool/db_check` para validar o banco.
- Node.js 20+ (só para `tool/db_check`).
- macOS com Xcode e CocoaPods para compilar o iOS.

### Ajustes neste Windows (caminhos com espaço)

O nome de usuário tem espaço (`C:\Users\Hugo Poletto`), o que quebra o NDK e os hooks de assets nativos do Flutter. Já foi configurado:

- Junção `C:\Android\sdk` → `%LOCALAPPDATA%\Android\sdk` e `flutter config --android-sdk C:\Android\sdk`.
- Variável de usuário `PUB_CACHE=C:\PubCache`.

Em outra máquina com o mesmo problema, repita os dois passos.

## Banco de dados

### Supabase local (com Docker)

```powershell
supabase start          # sobe Postgres, Auth, Realtime, Studio e Mailpit
supabase db reset       # aplica migrations e seed
supabase test db        # roda os testes pgTAP
supabase status         # mostra a URL da API e a "Publishable key"
```

Studio: http://127.0.0.1:54323. E-mails de login (Mailpit): http://127.0.0.1:54324.

### Sem Docker

```powershell
cd tool/db_check
npm install
npm run check
```

Aplica as migrations num Postgres 17 em WebAssembly (PGlite, com PostGIS, pgcrypto e pgTAP) usando um stub mínimo dos esquemas `auth` e `extensions` do Supabase, e roda os testes. Não substitui o `supabase test db`, mas pega erros de SQL e de RLS.

### Supabase na nuvem (região São Paulo)

```powershell
supabase login
supabase link --project-ref <ref-do-projeto>
supabase db push
```

No painel: Authentication → Email → mantenha o login por e-mail e coloque `{{ .Token }}` nos templates "Magic Link" e "Confirm signup" (igual a `supabase/templates/otp.html`).

## Rodar o app

1. Copie `env/dev.example.json` para `env/dev.json` e preencha `SUPABASE_PUBLISHABLE_KEY` (de `supabase status`).
   - Emulador Android: `SUPABASE_URL` = `http://10.0.2.2:54321`.
   - Celular Android via USB: rode `adb reverse tcp:54321 tcp:54321` e use `http://127.0.0.1:54321`.
2. Rode:

```powershell
flutter pub get
flutter run --flavor dev --dart-define-from-file=env/dev.json
```

3. Entre com qualquer e-mail, pegue o código no Mailpit e confirme.

Sem `--flavor`, o Flutter usa `dev` (`default-flavor` no `pubspec.yaml`). Sem `--dart-define-from-file`, o app abre uma tela avisando que falta a configuração.

Produção: `env/prod.json` e `--flavor prod`. Ids: `br.com.radarfamiliar` (prod) e `br.com.radarfamiliar.dev` (dev).

**iOS:** os flavors ainda não têm schemes no Xcode. Até criá-los num Mac, rode no iOS sem `--flavor`, passando `--dart-define-from-file=env/dev.json`.

## Rodar no Android Studio

1. Abra a pasta raiz `c:\Projetos\RadarFamiliar` (não a pasta `android/`), com os plugins Flutter e Dart instalados.
2. No seletor de execução, escolha **Radar Familiar (dev)**. Ela vem da pasta `.run/` do repositório e já define:
   - Build flavor: `dev`
   - Additional run args: `--dart-define-from-file=env/dev.json`
3. Escolha o emulador ou o celular e clique em Run.

Se preferir criar a configuração na mão: Run → Edit Configurations → + → Flutter. Em "Dart entrypoint", escolha `lib/main.dart`. Em "Build flavor", coloque `dev`. Em "Additional run args", coloque `--dart-define-from-file=env/dev.json`.

O aviso "Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): firebase_core" é só um aviso: o build funciona. Ele some quando o projeto passar a usar o Built-in Kotlin, que exige Flutter 3.47 ou mais recente (`flutter upgrade`, depois `android.builtInKotlin=true` em `android/gradle.properties`).

## Push (Firebase, só FCM)

O app funciona sem Firebase; o push só liga quando os arquivos existirem:

- Android: `android/app/src/dev/google-services.json` e `android/app/src/prod/google-services.json` (apps `br.com.radarfamiliar.dev` e `br.com.radarfamiliar`).
- iOS: `ios/Runner/GoogleService-Info.plist`, mais a chave APNs (.p8) enviada ao Firebase.

Esses arquivos estão no `.gitignore`.

## Checagens

```powershell
dart format lib test
flutter analyze
flutter test
flutter build apk --debug --flavor dev
```

## O que o banco já tem

- Tabelas da especificação (seção 4.2), incluindo `last_locations` com uma linha por usuário e sem histórico.
- RLS em todas as tabelas. Posições só são lidas por `get_group_locations` (pausa, precisão aproximada em grade de ~2 km, bateria opcional; simetria exigida só em grupos de Amigos).
- RPCs: `create_group`, `create_invite`, `preview_invite`, `accept_invite`, `revoke_invite`, `ingest_location` (limite de 1 posição a cada 20 s), `get_group_locations`, `register_device`.
- Gatilhos: perfil criado no cadastro, bloqueio de menores de 18, registro de consentimento, apagar a última posição quando o usuário desliga em todos os grupos, repasse de admin quando o último sai, aviso ao alvo de um alerta.

Ficam para os próximos marcos: cercas no servidor e Realtime (M3/M4), Edge Function `send-push` e pg_cron (M4/M5), exclusão de conta (M5).
