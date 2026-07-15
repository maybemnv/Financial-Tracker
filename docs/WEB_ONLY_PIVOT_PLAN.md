# Web-Only Pivot Plan

## Purpose

Pivot the finance tracker from a cross-platform Flutter app into a web-first, web-only Flutter application deployed as a static web build backed by Supabase.

The goal is not to rewrite the product. The goal is to remove native-only assumptions, make the web build reliable, keep Supabase as the source of truth, and make deployment/configuration predictable.

## Decisions Already Made

- Target platform: Flutter Web only.
- Native runners: delete `android/` and `windows/` from the repo.
- SMS auto-capture: remove `SmsListener` and the `another_telephony` dependency.
- SMS parser: keep `lib/features/sms/sms_parser.dart` because it is pure Dart and can support a future paste/import flow.
- Deployment: build-only for now. Do not deploy during the migration pass.
- Environment config: keep `.env`-style configuration, with Vercel environment variables used during deployment builds.
- Database: keep the current Supabase schema and migrations. No database redesign is part of this pivot.

## Current State Findings

### Existing Web Support

- `web/` exists with the standard Flutter web shell.
- `vercel.json` exists and currently uses:

```json
{
  "buildCommand": "flutter build web",
  "outputDirectory": "build/web",
  "framework": "flutter",
  "devCommand": "flutter run -d web"
}
```

- The app initializes Supabase through `lib/core/supabase.dart` using `AppConstants.supabaseUrl` and `AppConstants.supabaseAnonKey`.
- The app currently loads config through `flutter_dotenv` in `lib/main.dart`.

### Web Build Blocker

`lib/features/sms/sms_listener.dart` imports `package:another_telephony/telephony.dart` unconditionally.

That package is registered only for Android in `.flutter-plugins-dependencies`, not for web. Runtime checks like `kIsWeb` do not solve this because the web compiler still sees the import.

Current dependency:

```yaml
another_telephony: ^0.4.1
```

Current wiring:

- `lib/app.dart` imports `features/sms/sms_listener.dart`.
- `AppShell.initState()` subscribes to `SmsListener().onTransactionParsed`.
- `AppShell.initState()` starts `SmsListener()` after first frame.
- `AppShell.dispose()` stops the listener.

For a web-only app, this should be removed instead of conditionally imported.

### Environment Risk

Flutter web bundles assets into the shipped static app. Because `.env` is listed under `flutter.assets` in `pubspec.yaml`, anything inside `.env` is exposed to users who inspect the web build.

Current client code only needs:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `GEMINI_API_KEY`

Current client code does not use `SUPABASE_SERVICE_KEY`. That key must not be shipped in the web bundle.

Important: `GEMINI_API_KEY` is used by the client-side agent service. If it remains client-side, it will be exposed in the browser bundle. That is acceptable only if treated as a public client key for this personal app. The more secure future path is moving Gemini calls behind a Supabase Edge Function or another server-side proxy.

## Migration Phases

### Phase 1: Remove Native-Only SMS Runtime

Objective: remove the web compiler blocker and eliminate Android-only runtime behavior.

Changes:

- Remove `import 'dart:async';` from `lib/app.dart` if it becomes unused.
- Remove `import 'features/sms/sms_listener.dart';` from `lib/app.dart`.
- Remove `_smsSubscription` from `_AppShellState`.
- Remove the `SmsListener()` subscription and startup logic from `initState()`.
- Remove `SmsListener().stop()` from `dispose()`.
- Delete `lib/features/sms/sms_listener.dart`.
- Keep `lib/features/sms/sms_parser.dart`.
- Remove `another_telephony` from `pubspec.yaml`.
- Run `flutter pub get` to update `pubspec.lock` and generated plugin metadata.

Expected result:

- The app no longer imports Android-only telephony APIs.
- `flutter build web` can compile without the `another_telephony` package.
- Manual transaction entry remains unaffected.
- Supabase realtime remains unaffected.

Validation:

```bash
flutter pub get
flutter analyze
flutter test
flutter build web
```

Risk:

- Android SMS auto-import is removed permanently.
- Existing SMS parsing/dedup logic may remain unused until a web paste/import flow is added.

### Phase 2: Make Config Web-Safe

Objective: preserve `.env` workflow while avoiding accidental shipment of server-only secrets.

Local development rules:

- `.env` remains ignored by git.
- Local `.env` should contain only browser-safe variables:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
GEMINI_API_KEY=your-gemini-api-key-here
```

- Do not include `SUPABASE_SERVICE_KEY` in the Flutter app `.env`.
- If service-role access is needed later, it must live only in a server-side environment such as Supabase Edge Functions, Vercel Functions, or a private admin script outside the web bundle.

Vercel build strategy:

- Add the following Vercel environment variables:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
GEMINI_API_KEY
```

- Generate `.env` during the Vercel build from those environment variables, then build Flutter web.
- Treat Vercel variables as build-time inputs. A static Flutter web app cannot read Vercel runtime environment variables after it has already been compiled.
- Update `vercel.json` build command to something equivalent to:

```bash
printf "SUPABASE_URL=%s\nSUPABASE_ANON_KEY=%s\nGEMINI_API_KEY=%s\n" "$SUPABASE_URL" "$SUPABASE_ANON_KEY" "$GEMINI_API_KEY" > .env && flutter build web
```

Recommended `vercel.json` shape:

```json
{
  "buildCommand": "printf \"SUPABASE_URL=%s\\nSUPABASE_ANON_KEY=%s\\nGEMINI_API_KEY=%s\\n\" \"$SUPABASE_URL\" \"$SUPABASE_ANON_KEY\" \"$GEMINI_API_KEY\" > .env && flutter build web",
  "outputDirectory": "build/web",
  "framework": "flutter",
  "devCommand": "flutter run -d web"
}
```

Deployment caveat:

- Verify that the selected Vercel build environment can run `flutter build web`.
- If Vercel does not provide Flutter in the build image, use one of these approaches:
- Add a build step that installs Flutter before `flutter build web`.
- Build `build/web` in GitHub Actions with Flutter installed, then deploy the static output to Vercel.
- Move to a static host with a first-class Flutter build pipeline if Vercel setup becomes brittle.

Validation:

- Confirm `.env` in the build contains only the three expected keys.
- Confirm no service key appears in `build/web`.
- Confirm app boots and Supabase initializes.
- Confirm agent feature can call Gemini if `GEMINI_API_KEY` is set.

Security note:

- The current service key has been present locally. If it was ever committed, uploaded, shared, or bundled, rotate it in Supabase.
- Even if not committed, rotate it if there is any doubt.

Future secure AI path:

- Move Gemini requests from the browser to a Supabase Edge Function.
- Store `GEMINI_API_KEY` as an Edge Function secret.
- The Flutter app calls the Edge Function with the user's prompt/context.
- The browser never receives the Gemini key.

### Phase 3: Delete Native Project Folders

Objective: make the repository intentionally web-only.

Delete:

- `android/`
- `windows/`

Keep:

- `web/`
- `lib/`
- `assets/`
- `supabase/`
- `docs/`
- `test/`

Cleanup:

- Update `.gitignore` to remove stale Android/Windows-specific ignores if desired.
- Keep general ignores like `.dart_tool/`, `build/`, `.env`, `*.log`, `.idea/`, `.vscode/`.
- Re-run `flutter pub get` after deleting native folders.

Validation:

```bash
flutter devices
flutter build web
```

Expected result:

- The repo no longer suggests Android or Windows are supported targets.
- Web build still succeeds.

Risk:

- Re-adding Android/Windows later requires regenerating platform folders with Flutter tooling and re-evaluating dependencies.

### Phase 4: Update Documentation

Objective: make the repo instructions match the new web-only reality.

Update `README.md`:

- Project description: Flutter web personal finance tracker.
- Local setup:

```bash
flutter pub get
flutter run -d chrome
```

- Build:

```bash
flutter build web
```

- Deployment: Vercel uses env vars to generate `.env` at build time.
- Note that SMS auto-capture was removed from the web-only product.

Update `docs/ARCHITECTURE.md`:

- Replace Android/Windows system diagram with Web App -> Supabase -> Gemini.
- Remove SMS Listener from system overview.
- Keep manual entry, transaction CRUD, Supabase realtime, invoices, goals, dashboard, and agent desk.

Update `docs/TODO.md`:

- Mark native SMS capture as retired or superseded.
- Add web-only deployment checklist.
- Add future item for pasted statement/SMS import if desired.

Update `.env.example`:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
GEMINI_API_KEY=your-gemini-api-key-here
```

Do not include `SUPABASE_SERVICE_KEY`.

Validation:

- Docs no longer tell users to build Android app bundles or Windows desktop builds.
- Docs clearly state that the browser bundle contains the anon Supabase key and client Gemini key.

### Phase 5: Web UX Pass

Objective: make the product feel intentional on desktop browsers rather than a stretched mobile app.

Initial audit targets:

- `widgets/newsprint_shell.dart`
- `features/transactions/transaction_list_screen.dart`
- `features/dashboard/dashboard_screen.dart`
- `features/goals/goals_screen.dart`
- `features/invoices/invoice_sidebar.dart`
- `features/agent/agent_chat_screen.dart`

Recommended web layout direction:

- Keep the existing visual language and newsprint theme.
- Use constrained content widths for ledger and forms.
- Prefer desktop side navigation or a wider shell when viewport width is large.
- Preserve mobile behavior for small browser widths.
- Ensure add/edit forms work well at desktop size and do not become overly wide.
- Keep the invoice drawer if it works well; otherwise make it a right-side panel on desktop.

Validation:

- Chrome desktop width around 1440px.
- Narrow responsive width around 390px.
- Transaction add/edit path.
- Dashboard charts and cards.
- Invoice drawer/panel.
- Agent chat prompt/response flow.

This phase can be done after the technical web-only migration is complete.

### Phase 6: Deployment Verification

Objective: prove the production web artifact works before public use.

Local production build:

```bash
flutter build web
```

Local static serving:

```bash
npx serve build/web
```

Manual checks:

- App boots without initialization error.
- Supabase transactions load.
- Add transaction works.
- Edit/delete transaction works.
- Realtime refresh works across two browser tabs.
- Dashboard aggregates current-month data correctly.
- Goals load and allocations work.
- Invoice drawer loads and writes.
- Agent chat works if `GEMINI_API_KEY` is configured.
- Browser console has no serious runtime errors.

Vercel checks after deployment setup:

- Environment variables are present in Vercel project settings.
- Build log shows `.env` generation before `flutter build web`.
- Deployment serves `build/web`.
- Refreshing deep links does not 404 if deep links/routes are later added.

## Final Migration Checklist

- [ ] Remove `SmsListener` from `lib/app.dart`.
- [ ] Delete `lib/features/sms/sms_listener.dart`.
- [ ] Remove `another_telephony` from `pubspec.yaml`.
- [ ] Run `flutter pub get`.
- [ ] Update `.env.example` to browser-safe keys only.
- [ ] Remove `SUPABASE_SERVICE_KEY` from local `.env`.
- [ ] Update `vercel.json` to generate `.env` from Vercel env vars.
- [ ] Delete `android/`.
- [ ] Delete `windows/`.
- [ ] Clean `.gitignore` native-only entries.
- [ ] Update `README.md`.
- [ ] Update `docs/ARCHITECTURE.md`.
- [ ] Update `docs/TODO.md`.
- [ ] Run `flutter analyze`.
- [ ] Run `flutter test`.
- [ ] Run `flutter build web`.
- [ ] Search `build/web` to confirm `SUPABASE_SERVICE_KEY` is absent.

## Non-Goals

- Do not redesign the database.
- Do not move money-modifying actions into AI automation.
- Do not deploy during the planning/build-only pass.
- Do not implement Gemini Edge Function proxy unless explicitly chosen later.
- Do not build Android or Windows artifacts after this pivot.

## Open Questions For Later

- Should the agent move behind a Supabase Edge Function before the app is shared with anyone else?
- Should the web app add a pasted bank-statement importer to replace SMS auto-capture?
- Should the UI move from bottom navigation to sidebar navigation on desktop widths?
- Should auth be added before wider deployment, or is this still a private single-user app with permissive RLS?
