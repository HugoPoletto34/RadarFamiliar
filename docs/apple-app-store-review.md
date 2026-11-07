# Conta para revisor da Apple (App Store)

O app usa **e-mail e senha** (ou Google). O revisor da Apple não pode depender de código OTP por e-mail.

## Conta padrão

| Campo | Valor |
| --- | --- |
| E-mail | `revisor.apple@radarfamiliar.com` |
| Senha | definida ao rodar o script abaixo (não fica no git) |

## Criar ou atualizar no Supabase (produção)

1. No [painel Supabase](https://supabase.com/dashboard/project/xccwmeuubelmopifwtpk/settings/api), copie a **secret key** / `service_role` (só uso local, nunca no app).
2. Na raiz do repositório:

```powershell
$env:SUPABASE_SERVICE_ROLE_KEY = "sb_secret_..."
$env:APPLE_REVIEWER_PASSWORD = "radarfamiliar123"
powershell -ExecutionPolicy Bypass -File scripts\supabase\create-apple-reviewer.ps1
```

O script confirma o e-mail, define a senha e grava `birth_date` no perfil (necessário para aceitar convites).

Alternativa manual: **Authentication → Users → Add user** → mesmo e-mail, senha, marque **Auto Confirm User**.

## App Store Connect

Em **App Review Information** (ou notas da versão), informe:

- **User name:** `revisor.apple@radarfamiliar.com`
- **Password:** a senha que você definiu
- Texto curto: “Entrar com e-mail e senha na primeira tela. Não é necessário código por e-mail.”

Privacidade e URLs: [privacidade](privacidade.html) e demais docs em `docs/`.
