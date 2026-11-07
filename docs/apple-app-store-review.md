# Conta para revisor da Apple (App Store)

O app usa **e-mail e senha** (ou Google). O revisor da Apple não pode depender de código OTP por e-mail.

## Conta padrão

| Campo | Valor |
| --- | --- |
| E-mail | `revisor.apple@radarfamiliar.com` |
| Senha | definida ao rodar o script abaixo (não fica no git) |

## Criar ou atualizar no Supabase (produção)

1. [Settings → API](https://supabase.com/dashboard/project/xccwmeuubelmopifwtpk/settings/api):
   - **Não** use a linha **publishable** (`sb_publishable_...`) — é a do `SUPABASE_PUBLISHABLE_KEY` / Codemagic.
   - Use a linha **secret** → **Reveal** → copie `sb_secret_...` para `SUPABASE_SERVICE_ROLE_KEY`.
   - Alternativa: em **Legacy API Keys**, copie **service_role** (`eyJ...`) se ainda existir.
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

### Erro 401 `no_authorization`

Quase sempre é **chave errada**: `sb_publishable_...` ou `anon` no lugar de **secret**. Com `sb_secret_...`, o script não envia `Authorization: Bearer` (não é JWT). Atualize o repo (`git pull`) e rode de novo.

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
