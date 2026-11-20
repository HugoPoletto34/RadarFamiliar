# Amizades e convites de grupo

Fluxo para conectar pessoas e depois reuní-las em um grupo de compartilhamento.

## Código pessoal

1. Mapa → **Amigos** → cartão **Meu código**.
2. O app chama `my_friend_code` (cria o código na primeira vez).
3. **Copiar** ou **Compartilhar** abre o share do sistema (WhatsApp, etc.).
4. A mensagem leva o **código** e o deep link  
   `radarfamiliar://invite/XXXXXXXX` (`radarfamiliar-dev` no flavor dev).
5. **Gerar novo** chama `regenerate_friend_code` e invalida o código anterior.
6. O código **não expira** por tempo nem por uso.

## Pedido de amizade

1. Quem recebe instala o app, **cria conta ou entra**.
2. Abre o link do WhatsApp **ou** **Amigos → Adicionar amigo**.
3. Confere a prévia (`preview_friend_code`), informa **data de nascimento** (maior de 18) se ainda não tiver no perfil.
4. **Enviar pedido** → `request_friend` (fica pendente).
5. O dono do código aprova ou recusa em **Amigos → Pedidos recebidos** (`respond_friend_request`).

Se já existir um pedido no sentido contrário, o segundo envio aceita na hora.

## Grupo de compartilhamento

1. Crie um grupo em **Grupos → Criar grupo** (opcionalmente já convida amigos).
2. Ou, no grupo ativo, **Membros → Adicionar amigos** (só o admin; só amigos aceitos).
3. O convidado recebe push `group_invite` e vê o convite em **Grupos**.
4. Ao aceitar (`respond_group_invite`), entra no grupo e o admin recebe `member_joined`.

Sem grupo, o mapa mostra só você e sugere criar um. Não há mais grupo automático "Amigos".

## Deep link

| Flavor | Exemplo |
| --- | --- |
| `prod` | `radarfamiliar://invite/ABCD2345` |
| `dev` | `radarfamiliar-dev://invite/ABCD2345` |

O formato antigo `br.com.radarfamiliar://invite?code=ABCD2345` (e o `.dev`) continua abrindo o app.

Android e iOS declaram o host `invite` nos schemes `radarfamiliar` e `radarfamiliar-dev`, além do scheme de login.

## Backend

RPCs em `supabase/migrations/20261120000000_friends.sql`:

- Código: `my_friend_code`, `regenerate_friend_code`, `preview_friend_code`
- Amizade: `request_friend`, `respond_friend_request`, `cancel_friend_request`, `remove_friend`, `list_friends`
- Grupo: `create_group` (com `p_invitee_ids`), `invite_to_group`, `cancel_group_invite`, `respond_group_invite`, `my_group_invites`, `list_group_pending_invites`
