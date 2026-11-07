# Radar Familiar

App Flutter (Android e iOS) para grupos de família e amigos compartilharem localização de forma consensual. Backend no Supabase (Postgres + PostGIS), push via FCM.

Este repositório está no **Marco M0 (Fundação)**: app "olá mundo" com login por **Google** ou **e-mail e senha** (código de 6 dígitos só na confirmação do cadastro), flavors `dev` e `prod`, esquema inicial do banco com RLS, RPCs e testes pgTAP, e CI.

## Estrutura

```
lib/
  main.dart                 inicializa Supabase e Firebase (opcional)
  app/                      MaterialApp e roteamento por sessão
  core/config/              variáveis de ambiente (--dart-define-from-file)
  core/supabase/            cliente Supabase com sessão no Keystore/Keychain
  core/push/                Firebase (só FCM)
  features/auth/            Google + e-mail/senha (OTP só na confirmação do cadastro)
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
supabase db push --remote --dry-run
supabase db push --remote
```

`db push` sobe só as migrations. O `seed.sql` (funções `dev_*` dos amigos simulados) fica só no banco local: nunca use `--include-seed`.

Passos curtos depois de criar o projeto: [docs/supabase-prod.md](docs/supabase-prod.md). O passo a passo completo está em [docs/codemagic.md](docs/codemagic.md): criar o projeto, chaves, templates `{{ .Token }}`, SMTP e a pendência das RPCs do protótipo.

## Rodar o app

1. Copie `env/dev.example.json` para `env/dev.json` e preencha `SUPABASE_PUBLISHABLE_KEY` (de `supabase status`).
   - Emulador Android: `SUPABASE_URL` = `http://10.0.2.2:54321`.
   - Celular Android via USB: rode `adb reverse tcp:54321 tcp:54321` e use `http://127.0.0.1:54321`.
2. Rode:

```powershell
flutter pub get
flutter run --flavor dev --dart-define-from-file=env/dev.json
```

3. Crie conta com e-mail e senha, confirme com o código de 6 dígitos no Mailpit (ou entre com Google, se configurado).

Sem `--flavor`, o Flutter usa `dev` (`default-flavor` no `pubspec.yaml`). Sem `--dart-define-from-file`, o app abre uma tela avisando que falta a configuração.

Produção: `env/prod.json` e `--flavor prod`. Ids: `br.com.radarfamiliar` (prod) e `br.com.radarfamiliar.dev` (dev).

**iOS:** os schemes `dev` e `prod` existem no Xcode (`Debug/Release/Profile-<flavor>`), então `--flavor dev|prod` também vale no iOS. A chave do Google Maps no iOS vem de `ios/Flutter/Secrets.xcconfig` (fora do git), com uma linha `GOOGLE_MAPS_API_KEY=...`. Sem o arquivo, o app usa o OpenStreetMap.

## Publicação (Codemagic)

Build e publicação (TestFlight e App Bundle do Play) ficam no `codemagic.yaml`, no mesmo modelo do ilover-mobile. Configuração, variáveis e a ordem dos passos: [docs/codemagic.md](docs/codemagic.md).

## Protótipo local

Um fluxo mínimo para testar no emulador com o Supabase local: mapa, amigos e compartilhamento por tempo limitado.

1. Rode `supabase db reset`. Ele carrega `supabase/seed.sql`, que cria as funções `dev_*` dos amigos simulados. Elas só existem no banco local e não vão para a nuvem. As funções `proto_*` (grupo "Amigos" e compartilhamento) estão nas migrations e existem também na nuvem.
2. Em `env/dev.json`, `GOOGLE_MAPS_API_KEY` é opcional:
   - Com a chave (Maps SDK for Android, criada no Google Cloud, exige conta de faturamento), o app usa o Google Maps.
   - Vazia, o app usa o OpenStreetMap (flutter_map). Isso serve para desenvolvimento, mas não para produção (política de uso dos tiles do OSM).
3. Defina a posição do emulador: `adb emu geo fix -46.6388 -23.5489` (longitude primeiro). Também dá para usar Extended controls → Location.
4. Rode o app, entre (senha ou Google) e permita a localização.
5. Use o app:
   - O mapa mostra o seu marcador "Eu".
   - Em **Amigos** (ícone no topo), toque em **Adicionar amigo simulado** (Ana, Bruno, Carla…). Os amigos simulados aparecem perto de você, já compartilhando, e se movem um pouco a cada atualização (5 s).
   - O botão ao lado de cada amigo simula ele parar ou voltar a compartilhar.
   - Em **Compartilhar**, escolha 15 minutos, 1 hora ou até desligar. Enquanto estiver ligado, o app envia a posição pelo `ingest_location` (no máximo a cada 20 s). No grupo "Amigos", criado automaticamente, só vê os outros quem também está compartilhando. Por isso, desligado, o mapa mostra "Compartilhe para ver N amigo(s)".
   - Toque num marcador para ver nome, horário e bateria. Toque num amigo da lista para centralizar nele.

O botão de amigo simulado só aparece no flavor `dev`.

**Estilo do mapa:** o mapa é só fundo, então fica com pouca cor e pouco texto, para os marcadores (círculo com a inicial) serem o destaque.
- Google Maps: `assets/map_style.json` remove POIs, transporte público e nomes de rua (fica só o nome das vias principais), e usa cinza claro com água e parques suaves. Prédios 3D, trânsito, bússola e botões nativos ficam desligados. Para ajustar, gere outro JSON em [mapstyle.withgoogle.com](https://mapstyle.withgoogle.com) e substitua o arquivo.
- OpenStreetMap (sem chave): os tiles não aceitam estilo, então o app aplica um filtro de tons de cinza clareado (`_minimalFilter` em `osm_radar_map.dart`), que apaga as cores e os textos.
- Sobre o mapa ficam só um aviso curto de status, o botão de compartilhar e o de "mostrar todos". A lista de amigos é compacta: avatar, nome e uma linha curta de status.

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
- RPCs: `create_group`, `create_invite`, `preview_invite`, `accept_invite`, `revoke_invite`, `ingest_location` (limite de 1 posição a cada 20 s), `get_group_locations`, `register_device`. No app: **Convidar** (share/WhatsApp) e **Tenho código** — [docs/invites.md](docs/invites.md).
- Gatilhos: perfil criado no cadastro, bloqueio de menores de 18, registro de consentimento, apagar a última posição quando o usuário desliga em todos os grupos, repasse de admin quando o último sai, aviso ao alvo de um alerta.

Ficam para os próximos marcos: cercas no servidor e Realtime (M3/M4), Edge Function `send-push` e pg_cron (M4/M5), exclusão de conta (M5).
