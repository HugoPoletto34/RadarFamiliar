# App Store Connect — política de privacidade e informações de teste

Guia para preencher o Radar Familiar no TestFlight e na revisão da App Store.

## 1. URL da política de privacidade (obrigatório)

A Apple exige um link **HTTPS público** na ficha do app:

1. Publique o texto (por exemplo `docs/privacidade.html` ou a política no Project store) numa página web.
2. Substitua placeholders de e-mail de contato por um endereço real.
3. Opções rápidas de hospedagem:
   - Página estática no repositório + **GitHub Pages** (`https://<user>.github.io/<repo>/privacidade.html`);
   - Uma rota no domínio que você reservou para o app;
   - Notion/Google Sites com link público (menos ideal, mas aceito se for estável).

No Connect: **App → App Store → (versão) → Informações do app → URL da política de privacidade**.

Para **TestFlight**, a mesma URL costuma ser pedida em **Informações de teste** / metadados do beta.

---

## 2. Privacidade do app (questionário “App Privacy”)

Respostas alinhadas ao **protótipo atual** (login por e-mail, mapa, compartilhamento opcional, Supabase, Maps opcional):

| Tipo de dado | Coletado? | Vinculado à identidade? | Finalidade |
| --- | --- | --- | --- |
| **E-mail** | Sim | Sim | Criação de conta / login |
| **ID de usuário** | Sim | Sim | Funcionalidade do app |
| **Localização precisa** | Sim | Sim | Funcionalidade do app (só com permissão e compartilhamento ativo) |
| **Nome** | Sim (se o usuário preencher) | Sim | Funcionalidade do app |
| **Dados de diagnóstico / crash** | Só se você integrar ferramenta (ex. Firebase Crashlytics) | — | Marque conforme o que **estiver no build** |

Marque **Não** para: publicidade de terceiros, rastreamento entre apps, venda de dados.

**Rastreamento (ATT):** em geral **Não**, se não houver SDK de ads/tracking.

---

## 3. O que a Apple chama de “Informações de teste” (TestFlight)

No painel **TestFlight → Informações de teste** (ou ao enviar build para teste externo):

| Campo | Sugestão em português |
| --- | --- |
| **O que testar** | Login com e-mail e código de 6 dígitos; criar ou entrar em um grupo; ativar compartilhamento por 15 min ou 1 h; ver posição no mapa; desligar compartilhamento. |
| **E-mail de feedback** | Seu e-mail de desenvolvedor (ex. hugopoletto34@gmail.com ou contato do domínio). |
| **Descrição do beta** (se pedido) | “Versão inicial para famílias e amigos: mapa com localização em tempo real apenas enquanto o usuário escolhe compartilhar. Sem anúncios. Público 18+.” |
| **URL da política de privacidade** | A mesma URL pública da seção 1. |

Teste **interno** não exige revisão beta completa; teste **externo** exige e usa esses campos.

---

## 4. Informações para a equipe de revisão (App Review)

Em **App Store Connect → seu app → App Store → Informações da versão → Informações para a revisão**:

| Campo | O que colocar |
| --- | --- |
| **Nome de usuário / senha** | O app **não usa senha**. Use o campo de **notas** (abaixo) e, se couber, deixe o e-mail `revisor.apple@radarfamiliar.com` e senha `-` ou “ver notas”. |
| **Informações de contato** | Nome + telefone + e-mail onde a Apple pode falar com você. |
| **Notas** (texto sugerido): |

```
Login: informe o e-mail revisor.apple@radarfamiliar.com na tela "Entrar".
O app envia um código de 6 dígitos por e-mail (OTP, válido por 1 hora). A equipe
pode solicitar um novo código com o mesmo e-mail se expirar.

Após entrar: permitir localização "Ao usar o app"; no mapa, toque em compartilhar
(15 min ou 1 h) para testar o envio de posição. Para ver outro membro, é necessário
um segundo usuário no mesmo grupo (pode usar outro e-mail de teste).

App 18+, Brasil. Sem compras no app. Política de privacidade: <URL HTTPS>.
```

**Antes da revisão:** registre `radarfamiliar.com`, configure encaminhamento de e-mail para `revisor.apple@radarfamiliar.com`, verifique o domínio no Resend e aplique SMTP + templates em produção — ver [supabase-prod.md](supabase-prod.md) e o relatório interno `revisor-email-prod.md` no Project store. Sem recebimento + SMTP válido a revisão trava no login.

---

## 5. Checklist rápido antes do envio

- [ ] URL HTTPS da política publicada e colada no Connect  
- [ ] E-mail de contato real na política  
- [ ] App Privacy preenchido  
- [ ] Conta de teste + notas de revisão para OTP  
- [ ] Capturas e classificação etária 18+  
- [ ] `ITSAppUsesNonExemptEncryption` = não (já no projeto)

---

Relacionado: [supabase-prod.md](supabase-prod.md), [codemagic.md](codemagic.md).
