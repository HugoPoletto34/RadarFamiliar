# Publicação: Supabase na nuvem, Codemagic, App Store e Play Store

O `codemagic.yaml` segue o modelo do `ilover-mobile`: as mesmas etapas de keychain e assinatura e o mesmo cálculo de versão (`scripts/ci/version_helpers.sh`, copiado de lá). A diferença é que aqui existem os flavors `dev` e `prod`, e só o `prod` é publicado.

| Workflow | Quando roda | O que faz |
| --- | --- | --- |
| `checks` | push e pull request | `flutter analyze` e `flutter test` (Linux) |
| `android-prod` | tag `v*` ou manual | App Bundle `prod` assinado com o keystore de upload |
| `ios-prod` | tag `v*` ou manual | IPA `prod` assinado e enviado para o TestFlight |

O flavor `dev` aponta para o Supabase local (`10.0.2.2`) e serve só no emulador. Por isso ele não tem workflow.

## Ordem

1. Supabase na nuvem (seção 1). Sem ele, a build de produção não tem backend.
2. Tirar o app da dependência das RPCs do protótipo (seção 1.5). Sem isso, a build de produção abre e falha no mapa.
3. Repositório remoto e Codemagic (seção 2).
4. Apple: App ID, app no App Store Connect, assinatura (seção 3), depois a primeira build `ios-prod` para o TestFlight.
5. Google Play (seção 4), depois a primeira build `android-prod`.
6. Opcionais: chave do Google Maps e Firebase/push (seção 5).

## 1. Supabase na nuvem (região São Paulo)

### 1.1 Criar o projeto

1. Em [supabase.com/dashboard](https://supabase.com/dashboard), crie uma organização (o plano Free serve para começar) e depois **New project**:
   - Name: `radar-familiar`
   - Region: **South America (São Paulo)** (`sa-east-1`)
   - Database password: gere uma senha forte e guarde-a num gerenciador de senhas. Ela é pedida no `supabase link` e no `supabase db push`, e não vai em nenhum arquivo do repositório.
2. Anote o **Project ref**: o trecho `abcd1234` de `https://abcd1234.supabase.co`, que também aparece em Settings → General.
3. Em **Settings → API Keys**, copie:
   - **Project URL**, que vira `SUPABASE_URL`.
   - **Publishable key** (`sb_publishable_...`), que vira `SUPABASE_PUBLISHABLE_KEY`. Ela pode ir no app, porque quem protege os dados é o RLS. Também funciona a chave legada `anon`.
   - A **secret key** (antiga `service_role`) **não** é usada: o projeto não tem Edge Functions, e o app nunca deve recebê-la. Não a coloque no Codemagic nem em `env/*.json`.

No plano Free, um projeto sem uso por 7 dias é pausado e não há backup point-in-time. Para usuários reais, avalie o plano Pro.

### 1.2 Subir as migrations

Na raiz do repositório:

```powershell
supabase login
supabase link --project-ref <project-ref>   # pede a senha do banco
supabase db push --remote --dry-run                # lista as migrations que vão subir
supabase db push --remote
supabase migration list --remote            # local e remoto devem bater
```

`supabase db push` envia só `supabase/migrations/*.sql` (schema, RLS e RPCs). Ele **não** roda `supabase/seed.sql`. Nunca use `--include-seed` neste projeto: o seed cria as funções `dev_*` (amigos falsos em `auth.users`), que são só para o banco local.

### 1.3 Auth por código de e-mail

No painel, em **Authentication**:

1. **Sign In / Providers → Email**: mantenha ligado, com "Confirm email" ligado, OTP de 6 dígitos e validade de 3600 s (iguais a `supabase/config.toml`).
2. **Emails → Templates**, em **Magic Link** e **Confirm signup**:
   - Assunto: `Seu código do Radar Familiar`
   - Corpo: o conteúdo de `supabase/templates/otp.html`. O essencial é o `{{ .Token }}`: sem ele o e-mail leva um link, e o app espera o código.
3. **URL Configuration**: em Redirect URLs, adicione `br.com.radarfamiliar://login-callback`. O login por código não usa redirect, mas isso deixa a configuração igual à local.
4. **SMTP (obrigatório antes de ter usuários):** o e-mail embutido do Supabase só envia para membros da organização e tem limite muito baixo por hora. Em **Emails → SMTP Settings**, configure um provedor (Resend, Brevo, Amazon SES…) com um remetente do seu domínio. Depois ajuste em **Rate Limits** o limite de e-mails por hora.

### 1.4 `env/prod.json` (local) e variáveis do Codemagic

Para rodar contra a nuvem na sua máquina, copie `env/prod.example.json` para `env/prod.json` (ele fica fora do git) e preencha:

```json
{
  "FLAVOR": "prod",
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "GOOGLE_MAPS_API_KEY": ""
}
```

```powershell
flutter run --flavor prod --dart-define-from-file=env/prod.json
```

No Codemagic, os mesmos valores ficam no grupo `radar_prod` (seção 2). O `scripts/ci/write_env.sh` gera `env/prod.json` e `ios/Flutter/Secrets.xcconfig` durante a build, e falha se faltar `SUPABASE_URL` ou `SUPABASE_PUBLISHABLE_KEY`, ou se a URL de produção não for `https://`.

### 1.5 Antes da primeira build de produção: RPCs do protótipo

Resolvido: `proto_ensure_group` e `proto_set_sharing` foram para a migration `20261105100004_proto_production.sql` e estão no projeto da nuvem. Os nomes ainda são do protótipo: quando existirem convites e vários grupos, troque por RPCs definitivas e cubra-as com testes. As funções `dev_*` (amigos simulados) continuam só no seed, e os botões delas só aparecem no flavor `dev`.

## 2. Repositório e Codemagic

1. **Repositório remoto:** o Codemagic lê o código do GitHub, GitLab ou Bitbucket, e hoje o projeto está só nesta máquina. Crie um repositório **privado** (por exemplo `HugoPoletto34/radar-familiar`), depois `git remote add origin ...` e `git push -u origin main`.
2. Em [codemagic.io](https://codemagic.io), entre com a mesma conta do ilover. Em **Add application**, escolha o repositório e o tipo Flutter, com configuração por **codemagic.yaml**.
3. **Team settings → Integrations → Developer Portal:** a chave `apple_key` do ilover serve se o app ficar no mesmo time Apple. Se for outro time, crie uma API key no App Store Connect (Users and Access → Integrations → App Store Connect API, papel **App Manager**) e cadastre-a com o nome `apple_key`.
4. **Code signing identities:**
   - **iOS certificates:** o certificado *Apple Distribution* do ilover serve, porque um certificado vale para todos os apps do time.
   - **iOS provisioning profiles:** depois de criar o App ID (seção 3), use "Fetch profiles" ou crie um perfil *App Store* para `br.com.radarfamiliar`. O `ios_signing` do workflow escolhe o perfil pelo bundle id.
   - **Android keystores:** suba o keystore de upload (seção 4) com o nome de referência **`radar_upload`**.
5. **Environment variables**, grupo **`radar_prod`**. Marque todas como *Secure*:

| Variável | Valor |
| --- | --- |
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_...` |
| `GOOGLE_MAPS_API_KEY` | opcional (seção 5) |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS` | opcional; JSON da service account do Play Console |

6. No `codemagic.yaml`, preencha `IOS_APPLE_ID` com o Apple ID numérico do app, depois de criá-lo no App Store Connect.
7. Para disparar: `git tag v1.0.0 && git push origin v1.0.0`, ou **Start new build** no painel.

O build number é sempre o maior entre loja, `pubspec.yaml` e contador do Codemagic, mais 1. O build name é `MAJOR.MINOR` do `pubspec.yaml` mais esse número (por exemplo `1.0.7`). Com `IS_BETA: "true"`, fica `1.0.7-beta`, como no ilover.

## 3. Apple (App Store / TestFlight)

1. **Apple Developer Program** ativo (o mesmo do ilover, se for o mesmo time).
2. **Certificates, Identifiers & Profiles → Identifiers:** crie o App ID explícito `br.com.radarfamiliar`. Ligue *Push Notifications* só quando o push for implementado no iOS.
3. **App Store Connect → Apps → New App:** plataforma iOS, nome "Radar Familiar" (se estiver ocupado, escolha outro), idioma principal português (Brasil), bundle id `br.com.radarfamiliar`, SKU `radar-familiar`. Copie o **Apple ID** numérico para `IOS_APPLE_ID`.
4. Rode `ios-prod`. A build aparece no TestFlight: adicione testadores internos.
5. Antes de enviar para revisão:
   - **Política de privacidade** publicada numa URL.
   - **App Privacy:** localização precisa, e-mail e identificador do usuário, ligados à identidade e não usados para rastreamento.
   - **Conta para o revisor:** com login por código de e-mail, o revisor não recebe o código. É preciso definir antes como ele vai entrar, por exemplo com uma conta de demonstração com código fixo ou um e-mail de revisão que você acompanha.
   - Screenshots de iPhone 6,9" e 6,5".

O iOS ganhou os flavors no Xcode: configurações `Debug/Release/Profile-dev` e `-prod`, schemes `dev` e `prod`. No `dev`, o bundle é `br.com.radarfamiliar.dev` e o nome é "Radar Familiar Dev". No `prod`, `br.com.radarfamiliar` e "Radar Familiar". Isso foi feito editando o `project.pbxproj` sem Mac: a primeira build `ios-prod` é o teste real. Se o Xcode reclamar, abra `ios/Runner.xcworkspace` num Mac e confira em Runner → Info → Configurations.

## 4. Google Play

1. Conta de desenvolvedor do Google Play (taxa única).
2. Keystore de upload, gerado uma vez e guardado com backup (se perder, só o suporte do Google troca):

```powershell
keytool -genkey -v -keystore radar-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

3. Suba o `.jks` no Codemagic como `radar_upload` (seção 2). Para builds locais de release, crie `android/key.properties`, que fica fora do git:

```properties
storeFile=C:\\caminho\\radar-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

4. No Play Console, crie o app `br.com.radarfamiliar` e suba **à mão** o primeiro `.aab` do artifact `android-prod` na faixa de teste interno. A API do Play não cria apps.
5. Para publicar direto pelo Codemagic: crie uma service account com acesso ao app, salve o JSON em `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS` e descomente `google_play:` no `codemagic.yaml`.
6. No Play Console, preencha também a Segurança de dados (localização precisa, e-mail) e a declaração de permissão de localização.

## 5. Opcionais

- **Google Maps:** crie uma chave no Google Cloud (exige conta de faturamento) com *Maps SDK for Android* e *Maps SDK for iOS*, restrita ao pacote e ao bundle `br.com.radarfamiliar`. Coloque-a em `GOOGLE_MAPS_API_KEY`. Sem chave, o app usa os tiles do OpenStreetMap, cuja política de uso não permite um app publicado. Para produção, use a chave do Google ou um provedor de tiles com plano próprio.
- **Firebase (push):** crie o projeto e registre os apps Android (`br.com.radarfamiliar`, `.dev`) e iOS. Coloque os `google-services.json` em `android/app/src/<flavor>/`. No iOS, o `GoogleService-Info.plist` e a chave APNs ficam para quando o push no iOS for implementado. O app funciona sem Firebase.
