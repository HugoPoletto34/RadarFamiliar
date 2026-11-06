# Supabase de produção

Projeto `radar-familiar` (ref `xccwmeuubelmopifwtpk`, região São Paulo). O contexto completo (Codemagic, lojas) está em [codemagic.md](codemagic.md).

## Estado atual

| Item | Situação |
| --- | --- |
| `supabase link` | feito |
| Migrations (`supabase db push --remote`) | as 3 aplicadas, sem seed |
| OTP de 6 dígitos e redirect `br.com.radarfamiliar://login-callback` | aplicados com `config push` |
| SMTP próprio | **falta** |
| Templates com o código (`{{ .Token }}`) | **falta**: depende do SMTP |

Enquanto os templates não sobem, o e-mail de login leva o link padrão do Supabase, sem código, e o app não consegue entrar.

## 1. Copiar do painel

| Onde | O quê | Vai para |
| --- | --- | --- |
| Settings → General → **Project ID** | ref | `--remote=<ref>`, `supabase link` |
| Settings → API Keys → **Project URL** | URL | `SUPABASE_URL` |
| Settings → API Keys → **Publishable key** (`sb_publishable_...`), ou a legada **anon** | chave pública | `SUPABASE_PUBLISHABLE_KEY` |

A **secret key** / `service_role` não é usada: o projeto não tem Edge Functions. Não a coloque no app, no `env/*.json`, no Codemagic nem no chat.

## 2. Migrations

```powershell
supabase login
supabase link --project-ref xccwmeuubelmopifwtpk
supabase db push --remote --dry-run     # "seeds" deve vir vazio
supabase db push --remote
supabase migration list --remote        # colunas local e remote iguais
```

Na CLI 3.x, os comandos de banco apontam para o Supabase **local** por padrão. Para mirar a nuvem, passe `--remote`.

**Nunca rode o seed em produção:** não use `--include-seed` nem `supabase db reset --remote`, que apaga o banco. O `supabase/seed.sql` cria as funções do protótipo (`proto_*`, `dev_*`) e amigos falsos em `auth.users`, e é só para o banco local.

## 3. Auth: por que o template não aparece

No plano Free, com o e-mail embutido do Supabase:

- O painel não deixa editar os templates. O `config push` recusa com "Email template modification is not available for free tier projects using the default email provider. Please upgrade your plan or configure a custom SMTP provider."
- O e-mail embutido só entrega para endereços de **membros da organização** do Supabase, com limite de poucos e-mails por hora. Serve para o Hugo testar, não para usuários.

Há dois caminhos: **SMTP próprio**, que é gratuito (abaixo), ou o plano **Pro** do Supabase. O Pro libera a edição de templates e tira a pausa por inatividade, mas o e-mail embutido continua limitado, então para usuários reais o SMTP próprio é necessário de qualquer forma.

### Ordem

1. Criar a conta no provedor de SMTP, verificar o domínio e gerar a chave (3.1).
2. Ligar o SMTP no projeto (3.2).
3. Subir os templates `magic_link` e `confirmation` com `supabase config push` (3.3).
4. Ajustar o limite de e-mails por hora (3.4).

### 3.1 Provedor de SMTP (planos gratuitos)

**Resend** (3.000 e-mails por mês, 100 por dia):

1. Crie uma conta em [resend.com](https://resend.com).
2. Em **Domains → Add domain**, adicione um domínio seu (por exemplo `radarfamiliar.com.br`) e crie no DNS os registros que ele mostrar (SPF/DKIM). Espere ficar *Verified*. Sem domínio verificado, o Resend só envia do remetente de teste `onboarding@resend.dev`, e só para o e-mail da própria conta: serve para testar, não para usuários.
3. Em **API Keys → Create API key**, com permissão *Sending access*, copie a chave (`re_...`). Ela é a senha do SMTP.
4. Dados do SMTP: host `smtp.resend.com`, porta `465`, usuário `resend`, senha = a chave.

**Brevo** (300 e-mails por dia), alternativa que aceita remetente sem domínio próprio (com entrega pior):

1. Crie uma conta em [brevo.com](https://www.brevo.com).
2. Em **Senders, Domains & Dedicated IPs**, verifique um remetente (e-mail) ou, de preferência, um domínio.
3. Em **SMTP & API → SMTP**, gere uma *SMTP key*. Anote o *Login* (algo como `xxxx@smtp-brevo.com`) e a chave.
4. Dados do SMTP: host `smtp-relay.brevo.com`, porta `587`, usuário = o Login, senha = a SMTP key.

### 3.2 Ligar o SMTP

A configuração de produção fica em `supabase-prod/supabase/config.toml`. Ela declara só o necessário, e o `config push` não toca no resto do projeto. Não use o `supabase/config.toml` da raiz contra a nuvem: ele tem valores do ambiente local.

1. Descomente o bloco `[auth.email.smtp]` e preencha `admin_email` com o remetente verificado. Se usar Brevo, troque também host, porta e usuário.

```toml
[auth.email.smtp]
enabled = true
host = "smtp.resend.com"
port = 465
user = "resend"
pass = "env(SUPABASE_AUTH_SMTP_PASS)"
admin_email = "nao-responda@SEU-DOMINIO"
sender_name = "Radar Familiar"
```

2. A senha **não** vai no arquivo. Defina-a só na sessão do PowerShell:

```powershell
$env:SUPABASE_AUTH_SMTP_PASS = Read-Host "Chave SMTP"   # cole a chave; ela não vai para o histórico
```

   Outra opção: criar `supabase-prod/supabase/.env` com `SUPABASE_AUTH_SMTP_PASS=...`, que está no `.gitignore`.

3. Confira e aplique:

```powershell
supabase config diff --workdir supabase-prod --remote=xccwmeuubelmopifwtpk
supabase config push --workdir supabase-prod --remote=xccwmeuubelmopifwtpk
```

O mesmo push envia o SMTP e os templates. Se ainda vier o erro do plano Free, ligue o SMTP pelo painel (**Authentication → Emails → SMTP Settings → Enable custom SMTP**, com os mesmos dados) e rode o `config push` de novo.
### 3.3 Templates

Os templates já estão declarados em `supabase-prod/supabase/config.toml`, com assunto "Seu código do Radar Familiar" e corpo `supabase-prod/supabase/templates/otp.html`, que tem o `{{ .Token }}`. O push do passo 3.2 os envia.

Esse `otp.html` é uma cópia de `supabase/templates/otp.html` (o do ambiente local), porque o `config push` só aceita arquivos dentro da pasta do `--workdir`. Ao mudar um, copie para o outro.

Para conferir, `supabase config diff ...` não deve mostrar nada em `auth.email.template`. Depois, entre no app de produção com um e-mail qualquer: deve chegar o código de 6 dígitos.

Pelo painel, depois de ligar o SMTP: **Authentication → Emails → Templates** (*Magic link* e *Confirm sign up*). Cole o assunto e o HTML de `otp.html`.

### 3.4 Limite de e-mails

O limite por hora não é gerenciado pelo `config push`. Ajuste-o no painel em **Authentication → Rate Limits → "Rate limit for sending emails"**, de acordo com o plano do provedor (por exemplo, 30 por hora).

## 4. Configurar o app

```powershell
Copy-Item env\prod.example.json env\prod.json   # preencha SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY
flutter run --flavor prod --dart-define-from-file=env/prod.json
```

O `env/prod.json` fica fora do git. No Codemagic, os mesmos valores vão no grupo `radar_prod`.

O app ainda chama as RPCs do protótipo `proto_ensure_group` e `proto_set_sharing`, que só existem no seed local. Contra a nuvem, o login funciona (depois dos templates), mas o mapa mostra erro até essas funções virarem migration (ver [codemagic.md](codemagic.md), seção 1.5).
