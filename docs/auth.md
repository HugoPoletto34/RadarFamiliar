# Autenticação (Google + e-mail e senha)

O app oferece **duas formas de entrar**:

| Caminho | Cadastro | Login diário | Código por e-mail |
| --- | --- | --- | --- |
| **Google** | Primeiro uso do botão cria a conta | Mesmo botão | Não |
| **E-mail e senha** | Tela “Cadastrar” | E-mail + senha | **Só na confirmação** do cadastro (6 dígitos) |

Não há mais login diário só por código OTP.

## Produção (Supabase na nuvem)

1. **Authentication → Providers → Google**: ative Google e cole o **Client ID** e o **Client secret** do tipo *Web application* no Google Cloud Console.
2. **Authentication → URL configuration**: inclua `br.com.radarfamiliar://login-callback` em *Redirect URLs*.
3. **Authentication → Providers → Email**: deixe *Email* ligado; *Confirm email* ligado (confirmação com o template que contém `{{ .Token }}`).
4. SMTP: use **Resend** ou **Brevo** com domínio verificado — veja [supabase-prod.md](supabase-prod.md). O remetente (`admin_email`) **não** pode ser `@gmail.com` no Resend; o usuário pode **receber** o e-mail num Gmail normalmente.

### Google Cloud (OAuth)

No mesmo projeto (ou um dedicado) em [console.cloud.google.com](https://console.cloud.google.com):

1. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
2. Crie um cliente **Web application** (é o que o Supabase usa no fluxo com redirect).
   - *Authorized redirect URIs*: a URL de callback do painel Supabase (`https://<project-ref>.supabase.co/auth/v1/callback`).
3. Para Android (recomendado para evitar avisos no consent screen): crie também um cliente **Android** com o package `br.com.radarfamiliar` e o SHA-1 do keystore de release/upload.
4. Cole o par Web (ID + secret) no provedor Google do Supabase.

O app chama `signInWithOAuth` com redirect `br.com.radarfamiliar://login-callback` (flavor `prod`).

## Local (`supabase start`)

1. E-mails de confirmação aparecem no **Mailpit**: http://127.0.0.1:54324.
2. `supabase/config.toml` local tem `enable_confirmations = true` e templates com `supabase/templates/otp.html`.
3. Google no Auth local (opcional): defina antes de `supabase start`:

```powershell
$env:SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID = "....apps.googleusercontent.com"
$env:SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET = "GOCSPX-..."
supabase start
```

Redirect local: `br.com.radarfamiliar.dev://login-callback` (flavor `dev`).

## SMTP: Gmail só para teste pontual

| Cenário | Remetente | Observação |
| --- | --- | --- |
| **Resend / Brevo (produção)** | `nao-responda@seudominio.com.br` | Domínio verificado no provedor. Destinatário pode ser `@gmail.com`. |
| **SMTP Gmail no painel Supabase** | Seu `@gmail.com` | Senha de app (2FA). Cota baixa; não use em escala. **Não** é “Gmail dentro do Resend”. |
| **Resend sandbox** | `onboarding@resend.dev` | Só entrega para o e-mail da conta Resend. |

## Fluxo no app

1. **Google** → navegador → volta pelo deep link → sessão aberta.
2. **Cadastro** → `signUp` → se a confirmação estiver ligada, o usuário digita o código do e-mail (`OtpType.signup`) → depois entra com senha.
3. **Login** → `signInWithPassword`. Se o e-mail ainda não foi confirmado, a tela pede o código de confirmação.

Mais contexto de deploy: [codemagic.md](codemagic.md).
