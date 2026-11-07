# Supabase de produção

Projeto `radar-familiar` (ref `xccwmeuubelmopifwtpk`, região São Paulo). O contexto completo (Codemagic, lojas) está em [codemagic.md](codemagic.md).

## Estado atual

| Item | Situação |
| --- | --- |
| `supabase link` | feito |
| Migrations (`supabase db push --remote`) | as 4 aplicadas, sem seed (a 4ª traz `proto_ensure_group` e `proto_set_sharing`) |
| OTP de 6 dígitos e redirect `br.com.radarfamiliar://login-callback` | aplicados com `config push` |
| SMTP próprio (Resend) | **declarado na nuvem** (`onboarding@resend.dev`); envio falhou em teste API — conferir `SUPABASE_AUTH_SMTP_PASS` e domínio verificado |
| Templates com o código (`{{ .Token }}`) | **sem drift** no `config diff`; revalidar após SMTP válido |

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

**Nunca rode o seed em produção:** não use `--include-seed` nem `supabase db reset --remote`, que apaga o banco. O `supabase/seed.sql` cria as funções de amigos simulados (`dev_*`), que inserem usuários falsos em `auth.users`, e é só para o banco local. As funções `proto_ensure_group` e `proto_set_sharing`, que o app usa ao abrir o mapa, estão na migration `20261105100004_proto_production.sql`.

## 3. Auth: por que o template não aparece

No plano Free, com o e-mail embutido do Supabase:

- O painel não deixa editar os templates. O `config push` recusa com "Email template modification is not available for free tier projects using the default email provider. Please upgrade your plan or configure a custom SMTP provider."
- O e-mail embutido só entrega para endereços de **membros da organização** do Supabase, com limite de poucos e-mails por hora. Serve para o Hugo testar, não para usuários.

Há dois caminhos: **SMTP próprio**, que é gratuito (abaixo), ou o plano **Pro** do Supabase. O Pro libera a edição de templates e tira a pausa por inatividade, mas o e-mail embutido continua limitado, então para usuários reais o SMTP próprio é necessário de qualquer forma.

### Ordem

1. Criar a conta no provedor de SMTP, verificar o domínio e gerar a chave (3.1).
2. Ligar o SMTP no projeto (3.2, etapa 1).
3. Subir os templates `magic_link` e `confirmation` (3.3, etapa 2).
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

### 3.2 Ligar o SMTP (etapa 1)

A configuração de produção fica em `supabase-prod/supabase/config.toml`. Ela declara só o necessário, e o `config push` não toca no resto do projeto.

**Não ponha o SMTP no `supabase/config.toml` da raiz** e não rode `supabase config push` sem `--workdir supabase-prod`. O arquivo da raiz é do Supabase local: tem `site_url` em 127.0.0.1, confirmação de e-mail e MFA desligados, URLs do flavor dev e `[auth.rate_limit] email_sent = 2`. Com o SMTP ligado, esse limite também é enviado.

1. Em `supabase-prod/supabase/config.toml`, o bloco `[auth.email.smtp]` já está ativo, com os dados do Resend. Troque `admin_email` pelo remetente do domínio que você verificou no provedor. Não pode ser `@gmail.com`: o Resend e o Brevo só enviam de domínios verificados. Se usar Brevo, troque também host (`smtp-relay.brevo.com`), porta (`587`) e usuário (o Login SMTP).

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

2. Rode a etapa 1 na raiz do repositório:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\supabase\push-prod-auth.ps1 -Etapa smtp
```

O script:
- confere se o bloco SMTP está ativo, se `pass` usa `env(SUPABASE_AUTH_SMTP_PASS)` e se `admin_email` não é o exemplo nem um e-mail gratuito;
- pede a chave SMTP com `Read-Host` (não aparece na tela nem fica no histórico), se `$env:SUPABASE_AUTH_SMTP_PASS` não estiver definida;
- sobe uma cópia do config **sem os templates**, mostra o `config diff` e só faz o push se você digitar `s`.

**Sem o script**, a mesma coisa à mão. Nesse caso, o push envia SMTP e templates juntos:

```powershell
$s = Read-Host "Chave SMTP" -AsSecureString
$env:SUPABASE_AUTH_SMTP_PASS = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
supabase config diff --workdir supabase-prod --remote=xccwmeuubelmopifwtpk
supabase config push --workdir supabase-prod --remote=xccwmeuubelmopifwtpk
Remove-Item Env:SUPABASE_AUTH_SMTP_PASS    # ao terminar
```

Sobre a variável: a CLI troca `env(NOME)` pelo valor da variável de ambiente `NOME`, exatamente com esse nome. Neste projeto é `SUPABASE_AUTH_SMTP_PASS`, porque é o que o config declara. Também serve um `supabase-prod/supabase/.env` com `SUPABASE_AUTH_SMTP_PASS=...`, que está no `.gitignore`. Se a variável não existir, a CLI **não avisa**: o `diff` mostra a senha como "masked", e o push envia a senha vazia.

Pelo painel, o caminho equivalente é **Authentication → Emails → SMTP Settings → Enable custom SMTP**, com os mesmos dados.

### 3.3 Templates (etapa 2)

Os templates estão declarados em `supabase-prod/supabase/config.toml`, com assunto "Seu código do Radar Familiar" e corpo `supabase-prod/supabase/templates/otp.html`, que tem o `{{ .Token }}`. Depois que a etapa 1 passar:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\supabase\push-prod-auth.ps1 -Etapa templates
```

Esse `otp.html` é uma cópia de `supabase/templates/otp.html` (o do ambiente local), porque o `config push` só aceita arquivos dentro da pasta do `--workdir`. Ao mudar um, copie para o outro.

Para conferir, `supabase config diff --workdir supabase-prod --remote=xccwmeuubelmopifwtpk` não deve listar nada em `auth.email.smtp` nem em `auth.email.template`. Depois, entre no app de produção com um e-mail qualquer: deve chegar o código de 6 dígitos.

Pelo painel, depois de ligar o SMTP: **Authentication → Emails → Templates** (*Magic link* e *Confirm sign up*). Cole o assunto e o HTML de `otp.html`.

### Erros comuns

| Mensagem | Causa | O que fazer |
| --- | --- | --- |
| `Email template modification is not available for free tier projects using the default email provider` | Templates enviados sem SMTP próprio ligado | Etapa 1 antes da etapa 2 |
| 401 `Custom SMTP required ... Missing SMTP_PASS` | A variável do `env(...)` não existia no shell que rodou o push (por exemplo `env(SMTP_PASS)` sem `$env:SMTP_PASS`), então a senha foi vazia | Use `pass = "env(SUPABASE_AUTH_SMTP_PASS)"` e rode o script, que pede a chave |
| `... SMTP_SENDER_NAME` / `RATE_LIMIT_EMAIL_SENT` no mesmo erro | Push feito com o `supabase/config.toml` da raiz (sem `--workdir supabase-prod`), que declara `[auth.rate_limit]`, ou SMTP incompleto | Sempre `--workdir supabase-prod`. O limite de e-mails se ajusta no painel (3.4) |
| `content_path ... resolves outside the project root` | Template fora da pasta do `--workdir` | Use `./supabase/templates/otp.html` dentro de `supabase-prod` |
| E-mail não chega, sem erro no push | `admin_email` de um domínio não verificado, ou chave errada | Veja os logs do provedor (Resend → Emails / Brevo → Logs) e do Supabase (**Logs → Auth**) |

Um push que falha no Auth não desfaz o que já foi aplicado em outros serviços (API, banco, storage). Depois de um push errado com o config da raiz, rode `supabase config diff --remote=xccwmeuubelmopifwtpk` (sem `--workdir`, lendo o config da raiz) e confira se `site_url`, MFA e pooler ainda aparecem como diferenças. Se aparecerem, eles não foram sobrescritos com os valores locais.

### 3.4 Limite de e-mails

O limite por hora não é gerenciado pelo `config push`. Ajuste-o no painel em **Authentication → Rate Limits → "Rate limit for sending emails"**, de acordo com o plano do provedor (por exemplo, 30 por hora).

## 4. Configurar o app

```powershell
Copy-Item env\prod.example.json env\prod.json   # preencha SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY
flutter run --flavor prod --dart-define-from-file=env/prod.json
```

O `env/prod.json` fica fora do git. No Codemagic, os mesmos valores vão no grupo `radar_prod`.

As RPCs que o app chama ao abrir o mapa (`proto_ensure_group`, `proto_set_sharing`, `get_group_locations`, `ingest_location`) estão todas nas migrations. Se aparecer `PGRST202 ... not in schema cache`, confira com `supabase migration list --remote=<ref>` se a última migration subiu.
