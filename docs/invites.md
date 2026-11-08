# Convites de grupo

Fluxo para trazer familiares/amigos para o **mesmo grupo** no Radar Familiar.

## Quem convida (no app)

1. Mapa → **Amigos** → **Convidar**.
2. O app chama `create_invite` e abre o compartilhar do sistema (WhatsApp, etc.).
3. A mensagem leva o **código** e o deep link  
   `radarfamiliar://invite/XXXXXXXX` (`radarfamiliar-dev` no flavor dev).  
   O scheme não tem pontos: o WhatsApp lia `br.com.radarfamiliar.dev` como site e descartava o código.

## Quem aceita

1. Instala o app, **cria conta ou entra** (Google ou senha).
2. Abre o link do WhatsApp **ou** **Amigos → Tenho código**.
3. Confere a prévia (`preview_invite`), informa **data de nascimento** (maior de 18) se ainda não tiver no perfil.
4. **Aceitar** → `accept_invite` e o mapa passa a usar o grupo com mais membros.

## Deep link

| Flavor | Exemplo |
| --- | --- |
| `prod` | `radarfamiliar://invite/ABCD2345` |
| `dev` | `radarfamiliar-dev://invite/ABCD2345` |

O formato antigo `br.com.radarfamiliar://invite?code=ABCD2345` (e o `.dev`) continua abrindo o app.

Android e iOS declaram o host `invite` nos schemes `radarfamiliar` e `radarfamiliar-dev`, além do scheme de login.

## Backend

RPCs em `supabase/migrations/20261104000003_rpcs.sql`: `create_invite`, `preview_invite`, `accept_invite`, `revoke_invite`.
