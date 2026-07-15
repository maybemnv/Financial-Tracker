# Finance Tracker

Flutter web personal finance app backed by Supabase.

## Features

- **Manual Entry** — Add transactions with account selector, type (debit/credit/transfer/investment), category, merchant, custom tags, date & time picker (Paytm-style)
- **Real-time Sync** — Powered by Supabase Realtime; add a transaction in one browser tab, appears in another within seconds
- **Dashboard** — Emergency Fund progress card, Savings Rate (target 20%+), per-account balance breakdown, summary cards (Earned/Spent/Saved/Net) + category pie chart
- **Accounts** — Multiple accounts (SBI, Kotak, PayPal, Cash) with derived balances via `fn_account_balance()` — never stored, never drift
- **Transfers** — Double-entry transfer support: two linked rows with matching `transfer_group_id`, net worth unaffected
- **Investments** — `type = 'investment'` moves money from cash account to investment account, excluded from expense reports
- **Custom Tags** — Free-form tag input on every transaction (chip builder). Tags are normalised to lowercase, deduped, and shown as pills on each row.
- **Transaction Dates** — `transacted_at` is user-set via date/time picker; falls back to `created_at`. Balance calculation uses `COALESCE(transacted_at, created_at)`.
- **Paytm-Style List** — Transactions grouped by date ("Today", "Yesterday", "Fri, 27 Jun 2026"), 24hr time on each row.
- **Soft Delete** — Nothing is ever hard-deleted; `is_deleted` + `deleted_at` on all tables + confirmation dialog
- **Immutable Audit Trail** — `edit_history` JSONB stores old/new values + `edited_at` on every change
- **Smart Categorization** — Rule-based (priority-ordered) + Gemini LLM fallback
- **Goals** — Set savings goals with live progress tracking; Emergency Fund goal detected by `type` field, pinned to top
- **Invoice Sidebar** — Track freelance invoices with PayPal USD, INR bank receipts, FX rate, and fee chips
- **Finance Agent** — Gemini-powered Q&A with tool-use (8 tools that query your actual data)
- **Monthly Snapshots** — Pre-computed monthly aggregates written on first open of each new month

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
- Gemini API key

### 1. Environment

Create `.env` in the project root:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
GEMINI_API_KEY=your-gemini-api-key
```

Do not include `SUPABASE_SERVICE_KEY` — it is not used by the client and would be exposed in the browser bundle.

### 2. Supabase

1. Create a project at [supabase.com](https://supabase.com)
2. Run `supabase/migrations/00001_init.sql` in the SQL editor (creates all 8 tables, RPCs, RLS, Realtime, seed accounts)
3. Run remaining migrations in `supabase/migrations/` in order
4. Copy your project URL and anon key into `.env`

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
├── app.dart                   # App shell with bottom nav + invoice drawer
├── core/
│   ├── theme.dart             # AppTheme (dark palette)
│   ├── supabase.dart          # SupabaseService singleton
│   ├── constants.dart         # Categories, AppConstants
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
│   ├── transaction_provider   # CRUD + Realtime + dedup + edit_history + transfer
│   ├── goal_provider          # CRUD + soft delete
│   ├── invoice_provider       # CRUD + soft delete
│   ├── account_provider       # Load + per-account balance + net worth RPCs
│   ├── recurring_expense_provider
│   └── recurring_income_provider
├── features/
│   ├── transactions/          # Transaction list (Paytm-style date grouping, custom tags) + add form (date/time picker, tag input, account selector)
│   ├── dashboard/             # Emergency Fund, Savings Rate, per-account balances, pie chart
│   ├── goals/                 # Goal list (emergency fund pinned) + add/allocate
│   ├── invoices/              # Slide-in sidebar with FX chips
│   ├── agent/                 # Chat UI + Gemini tool-use service (8 tools)
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
   - `GEMINI_API_KEY`
4. Vercel builds with `vercel.json` which generates `.env` from these vars before `flutter build web`

### Security Notes

- The browser bundle contains `SUPABASE_ANON_KEY` and `GEMINI_API_KEY` — both are visible to users. This is acceptable for a personal single-user app.
- `SUPABASE_SERVICE_KEY` must never be added to the Flutter `.env` or Vercel env vars — it would grant full database access to anyone who inspects the web bundle.
- For higher security, move Gemini calls behind a Supabase Edge Function so the API key never reaches the browser.

## Design Principles

- **AI never modifies money** — categorize/summarize/answer only. Edit/delete requires user confirmation.
- **Soft-delete everything** — `is_deleted` + `deleted_at` on all tables.
- **Double-entry transfers** — two rows linked by `transfer_group_id`, net worth unchanged.
- **Investments are not expenses** — `type = 'investment'`, net worth unchanged.
- **Immutable history** — `edit_history` JSONB stores every change.
- **Balances are derived** — `accounts` has `opening_balance` + `opening_date`. Current balance is `fn_account_balance()`. No `balance` column.
- **Agent uses tool-use, not context injection** — Gemini decides which of the 8 tools to call per turn. No pre-fetching data.
- **No streaming** — Agent responses appear after 2–4s. SSE removed from scope permanently.
