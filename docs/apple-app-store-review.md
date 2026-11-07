# Conta para revisor da Apple (App Store)

O app usa **e-mail e senha** (ou Google). O revisor da Apple não pode depender de código OTP por e-mail.

## Conta padrão

| Campo | Valor |
| --- | --- |
| E-mail | `revisor.apple@radarfamiliar.com` |
| Senha | definida ao rodar o script abaixo (não fica no git) |

## Criar ou atualizar no Supabase (produção)

1. No [painel Supabase](https://supabase.com/dashboard/project/xccwmeuubelmopifwtpk/settings/api), copie a **secret key** / `service_role` (só uso local, nunca no app).
2. **Atualize o clone** (o script foi adicionado no commit `a7f3e18`):

```powershell
cd C:\caminho\para\RadarFamiliar
git pull origin main
Test-Path .\scripts\supabase\create-apple-reviewer.ps1   # deve ser True
```

3. Na **raiz** do repositório (pasta que contém `pubspec.yaml`):

```powershell
$env:SUPABASE_SERVICE_ROLE_KEY = "sb_secret_..."
$env:APPLE_REVIEWER_PASSWORD = "radarfamiliar123"
powershell -ExecutionPolicy Bypass -File .\scripts\supabase\create-apple-reviewer.ps1
```

Se o `-File` ainda falhar, use o caminho absoluto, por exemplo:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Projetos\RadarFamiliar\scripts\supabase\create-apple-reviewer.ps1"
```

### Sem o script (só painel)

**Authentication → Users → Add user** → e-mail `revisor.apple@radarfamiliar.com`, senha, marque **Auto Confirm User**. Depois, em **Table Editor → profiles**, defina `birth_date` = `1990-01-01` para esse usuário.

O script confirma o e-mail, define a senha e grava `birth_date` no perfil (necessário para aceitar convites).

Alternativa manual: **Authentication → Users → Add user** → mesmo e-mail, senha, marque **Auto Confirm User**.

## App Store Connect

Em **App Review Information** (ou notas da versão), informe:

- **User name:** `revisor.apple@radarfamiliar.com`
- **Password:** a senha que você definiu
- Texto curto: “Entrar com e-mail e senha na primeira tela. Não é necessário código por e-mail.”

Privacidade e URLs: [privacidade](privacidade.html) e demais docs em `docs/`.
