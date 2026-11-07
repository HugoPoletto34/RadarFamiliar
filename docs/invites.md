# Convites de grupo

Fluxo para trazer familiares/amigos para o **mesmo grupo** no Radar Familiar.

## Quem convida (no app)

1. Mapa → **Amigos** → **Convidar**.
2. O app chama `create_invite` e abre o compartilhar do sistema (WhatsApp, etc.).
3. A mensagem leva o **código** e o deep link  
   `br.com.radarfamiliar://invite?code=XXXXXXXX` (`.dev` no flavor dev).

## Quem aceita

1. Instala o app, **cria conta ou entra** (Google ou senha).
2. Abre o link do WhatsApp **ou** **Amigos → Tenho código**.
3. Confere a prévia (`preview_invite`), informa **data de nascimento** (maior de 18) se ainda não tiver no perfil.
4. **Aceitar** → `accept_invite` e o mapa passa a usar o grupo com mais membros.

## Deep link

| Flavor | Exemplo |
| --- | --- |
| `prod` | `br.com.radarfamiliar://invite?code=ABCD2345` |
| `dev` | `br.com.radarfamiliar.dev://invite?code=ABCD2345` |

Android e iOS declaram o host `invite` no mesmo scheme do login.

## Backend

RPCs em `supabase/migrations/20261104000003_rpcs.sql`: `create_invite`, `preview_invite`, `accept_invite`, `revoke_invite`.
