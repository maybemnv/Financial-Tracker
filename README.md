# Finance Tracker

Flutter web personal finance app backed by Supabase. Used via **Brave browser**
on desktop and as a **Brave → Add to Home Screen** shortcut (installed PWA) on
mobile.

## Features

- **Ledger** — Add debits, credits, transfers, and investments with an explicit
  account, labels, primary attribution, merchant/note, and date/time.
- **Real-time Sync** — Ledger pages patch row events and debounce label-join
  refreshes; aggregate views use owner-scoped RPCs.
- **Briefing and Analytics** — A numbers-first Briefing plus a separate monthly
  Analytics workbench with cash flow, label spend, daily pace, net-worth,
  merchant aliases, obligations, and a 30-day forecast.
- **Accounts** — Multiple accounts (SBI, Kotak, PayPal, Cash) with derived balances via `fn_account_balance()` — never stored, never drift
- **Transfers** — Double-entry transfer support: two linked rows with matching `transfer_group_id`, net worth unaffected
- **Investments** — `type = 'investment'` moves money from cash account to investment account, excluded from expense reports
- **Transaction Dates** — `transacted_at` is user-set via date/time picker; falls back to `created_at`. Balance calculation uses `COALESCE(transacted_at, created_at)`.
- **Paytm-Style List** — Transactions grouped by date ("Today", "Yesterday", "Fri, 27 Jun 2026"), 24hr time on each row.
- **Soft Delete** — Financial records use `is_deleted` + `deleted_at`; merchant
  aliases are a deliberate metadata-only delete exception.
- **Labels** — GitHub-style labels support primary attribution, review queues,
  rename, archive, restore, merge, and guarded delete.
- **Goals** — Contribution-backed earmarking with corrections, reallocations,
  status controls, history, and an Emergency Fund pinned by `type`.
- **Invoice Sidebar** — Track freelance invoices with PayPal USD, INR bank receipts, FX rate, and fee chips
- **Finance Agent** — Gemini-powered Q&A behind an authenticated Supabase Edge Function (read-only tools; the key never reaches the browser)
- **Monthly Snapshots** — Previous-month aggregates are written on first open of
  a new month. See `docs/PRD.md` for the current snapshot-basis limitation.

## Tech Stack

| Layer | Tech |
|---|---|
| Frontend | Flutter Web (Dart) |
| Backend / DB | Supabase (Postgres, Realtime) |
| State | Riverpod |
| Charts | fl_chart |
| LLM | Gemini 2.5 Flash |

## Setup

### Prerequisites

- Flutter SDK (stable)
- Supabase account (free tier)
- Gemini API key for the server-side Edge Function

### 1. Environment

Create `.env` in the project root:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

`GEMINI_API_KEY` is **not** a browser value. It lives only as a Supabase Edge
Function secret (`supabase secrets set GEMINI_API_KEY=…`); the browser never
sees it. Never include `SUPABASE_SERVICE_KEY` either — the client does not use
it and it would be exposed in the bundle.

### 2. Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. Run the migrations in `supabase/migrations/` in numeric order, or use the
   paste-ready bundles in `supabase/apply/` (see `supabase/apply/README.md`).
3. Provision the owner: enable an auth provider, sign in once, then register
   your `auth.users` id in `app_owner` — `supabase/apply/01b_register_owner.sql`
   does this from your email. Until then the app fails closed ("Access denied").
4. Deploy the Agent Edge Function: `supabase functions deploy agent` and set the
   `GEMINI_API_KEY` secret.
5. Copy your project URL and anon key into `.env`.

**Going to production?** `docs/RUNBOOK.md` covers backup, owner provisioning,
the migration sequence, key rotation, and snapshot/cache recovery. Run
`scripts/release_gate.sh` for the automated pre-deploy gates.

### 3. Run

```bash
flutter pub get
flutter run -d chrome
```

### 4. Build

```bash
flutter build web
```

Output in `build/web/` — deploy as static files.

## Project Structure

```
lib/
├── main.dart                  # Entry point (inits Supabase + runs MonthlySnapshotJob)
├── app.dart                   # Auth-gated shell with lazy tabs + invoice drawer
├── core/
│   ├── theme.dart             # Newsprint AppTheme and design tokens
│   ├── supabase.dart          # SupabaseService singleton
│   ├── analytics_types.dart   # Typed analytics query and bundle DTOs
│   ├── dedup.dart             # SHA-256 dedup for SMS
│   └── monthly_snapshot.dart  # Backfill monthly aggregates
├── models/
│   ├── transaction.dart       # Debit/credit/transfer/investment ledger entry
│   ├── goal.dart              # Savings goal (emergency_fund / custom)
│   ├── invoice.dart           # Freelance invoice with FX fields
│   ├── account.dart           # Account (SBI, Kotak, PayPal, Cash)
│   ├── category_rule.dart     # Rule engine match pattern
│   ├── recurring_expense.dart # Known recurring outflows
│   ├── recurring_income.dart  # Expected recurring inflows
│   └── monthly_snapshot.dart  # Pre-computed monthly totals
├── providers/
│   ├── ledger_provider        # Paged ledger + targeted Realtime updates
│   ├── analytics_provider     # Analytics and merchant RPCs
│   ├── transaction_provider   # Legacy transfer/investment writes
│   ├── goal_provider          # Contribution-backed goal lifecycle
│   ├── invoice_provider       # CRUD + soft delete
│   ├── account_provider       # Load + per-account balance + net worth RPCs
│   ├── recurring_expense_provider
│   └── recurring_income_provider
├── features/
│   ├── auth/                  # Owner auth gate and sign-in flow
│   ├── transactions/          # Paged ledger, quick capture, add/edit forms
│   ├── dashboard/             # Numbers-first monthly Briefing
│   ├── analytics/             # Charts, merchants, obligations, forecast
│   ├── labels/                # Lifecycle management and review queue
│   ├── goals/                 # Contribution-backed savings board
│   ├── invoices/              # Slide-in sidebar with FX chips
│   ├── agent/                 # Thin Edge Function chat client
│   └── sms/                   # SMS parser (kept for future paste/import)
└── widgets/                   # Shared UI components (EmptyState, SummaryCard)
```

## Deployment

This app is designed for Vercel deployment.

1. Push the repo to GitHub
2. Import into Vercel
3. Set environment variables in the Vercel project dashboard:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
4. `vercel-build.sh` writes the browser-safe `.env` and builds `build/web`.

Deploy the Edge Function separately and set `GEMINI_API_KEY` and an explicit
`ALLOWED_ORIGINS` allowlist with `supabase secrets set`. `vercel.json` permits
Git deployments only from `master`; deploy a feature branch manually if needed.

### Security Notes

- The browser bundle contains only `SUPABASE_ANON_KEY`, which is intended to be
  public when owner-only RLS is applied. Gemini remains a server-side Edge
  Function secret.
- `SUPABASE_SERVICE_KEY` must never be added to the Flutter `.env` or Vercel env vars — it would grant full database access to anyone who inspects the web bundle.
- Apply migrations `00006`-`00020`, provision the owner, and deploy `agent`
  before treating this branch as production-ready.

## Design Principles

- **AI never modifies money** — categorize/summarize/answer only. Edit/delete requires user confirmation.
- **Soft-delete financial records** — `is_deleted` + `deleted_at`; aliases are
  the narrow metadata exception.
- **Double-entry transfers** — two rows linked by `transfer_group_id`, net worth unchanged.
- **Investments are not expenses** — `type = 'investment'`, net worth unchanged.
- **Immutable history** — `edit_history` JSONB stores every change.
- **Balances are derived** — `accounts` has `opening_balance` + `opening_date`. Current balance is `fn_account_balance()`. No `balance` column.
- **Agent uses tool-use, not context injection** — the Edge Function runs 10
  read-only tools; the browser does not pre-fetch data or hold the Gemini key.
- **No streaming** — Agent responses appear after 2–4s. SSE removed from scope permanently.
