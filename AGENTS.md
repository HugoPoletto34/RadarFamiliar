# AGENTS.md — Radar Familiar

Guia operacional para agentes e humanos. Leia isto antes de alterar o código.

## O que é este projeto

App Flutter para grupos de família e amigos compartilharem localização de forma consensual. Backend no Supabase (Postgres + PostGIS). Push via FCM, só quando os arquivos do Firebase existirem.

O padrão de código segue o **Meu Kapital** (feature-first, `AppScope`, telas e serviços) e o design system do **iLover** (tokens em `lib/core/theme/`).

## Mapa

| Caminho | Função |
| --- | --- |
| `lib/main.dart` | Composition root: Supabase, push e serviços |
| `lib/app.dart` | `RadarFamiliarApp` + `AppScope` + `MaterialApp` |
| `lib/core/` | Config, tema, DI, Supabase, localização, auth, convites |
| `lib/features/{nome}/` | `models`, `services`, `screens`, `widgets`, `controllers` |
| `lib/shared/widgets/` | `LoadingView`, `ErrorBox` |
| `supabase/` | Migrations, RLS, RPCs e testes pgTAP |
| `docs/` | Auth, convites, produção e CI |

## Arquitetura

- **Estado:** `ChangeNotifier` no controller da feature. Sem Riverpod, BLoC ou GetIt.
- **DI:** manual. Serviços nascem em `main.dart` e descem pelo `AppScope`.
- **Dados:** `RadarService` e `InviteService` falam com o Supabase. A tela não instancia cliente.
- **Auth:** `AuthGate` observa a sessão e mostra `LoginScreen` ou `MapScreen`.
- **UI:** `import 'package:radar_familiar/core/theme/theme.dart'`. Não hardcodar cor ou espaçamento se o token existir.
- **Idioma:** português em código, comentários, UI e mensagens.

## Comandos

```powershell
dart format lib test
flutter analyze
flutter test
```

## Limites

Sem pedido explícito, não fazer:

- deploy (`supabase db push`, Codemagic, lojas)
- commit de `env/*.json` (exceto `*.example.json`), keystores ou `google-services.json`
- alterar `pubspec.yaml` version ou assinatura de release

As RPCs `dev_*` existem só no banco local (`supabase/seed.sql`). Não levá-las para a nuvem.
