# Repository Guidelines

## Project Structure & Module Organization
This is a Flutter **web-only** personal finance app backed by Supabase (the Android and Windows runners were removed). Application code lives in `lib/`: `main.dart` initializes services, `app.dart` defines the app shell, `core/` holds shared services and constants, `models/` contains data models, `providers/` contains Riverpod state and CRUD logic, `features/` contains screens and feature-specific services, and `widgets/` contains reusable UI. Tests live in `test/`, mirroring `lib/` (`test/core/`, `test/models/`, `test/features/`). Static assets are in `assets/`, web files in `web/`, and database migrations in `supabase/migrations/`. Product and architecture notes are in `docs/` — start with `docs/PRD.md` (boundaries and canonical financial metrics) and `docs/TODO.md` (phased roadmap).

## Build, Test, and Development Commands
- `flutter pub get`: install Dart and Flutter dependencies.
- `flutter run`: run locally on the selected device or platform.
- `flutter test`: run the Flutter test suite.
- `flutter analyze`: run static analysis using `analysis_options.yaml`.
- `flutter build web`: build the release web bundle (what Vercel deploys).

Run Supabase migrations manually from `supabase/migrations/` when provisioning a database.

## Coding Style & Naming Conventions
Use Dart conventions: two-space indentation, `snake_case.dart` file names, `PascalCase` classes, `camelCase` members, and `lowerCamelCase` providers. Keep feature UI under `lib/features/<feature>/`, shared UI under `lib/widgets/`, and cross-cutting logic under `lib/core/`. The project uses `flutter_lints` with `prefer_const_constructors` and `prefer_const_declarations`; prefer `const` where possible and run `flutter analyze` before submitting changes.

## Testing Guidelines
Use `flutter_test` for widget and unit tests. Name test files with the `_test.dart` suffix and place them under `test/`, mirroring the relevant `lib/` feature or module when practical. Add tests for provider logic, parsing/deduplication, date grouping, and UI behavior that affects finance calculations. Run `flutter test` before opening a pull request.

## Commit & Pull Request Guidelines
Recent commits use short, imperative subjects such as `Add visible error screen for web init failures` and `Fix: 24hr clock format...`. Follow that style: describe the behavior change, keep the subject focused, and use `Fix:` when correcting a bug.

Pull requests should include a concise description, testing performed, linked issue or task when available, and screenshots or screen recordings for UI changes. Note any database migration, `.env` change, or platform-specific impact.

## Security & Configuration Tips
Do not commit real secrets from `.env`. Use `.env.example` for required variable names such as `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `GEMINI_API_KEY` (the Gemini key is browser-side today and moves to a Supabase Edge Function secret in Phase 3 of `docs/TODO.md`). Preserve the app's finance safety rules: soft-delete records, derive balances through database functions, keep every transaction on its explicitly selected account, treat goal allocation as earmarking (never a balance change), and never let AI features modify money without explicit user confirmation.
