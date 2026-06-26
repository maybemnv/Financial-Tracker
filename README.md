# Finance Tracker

Cross-platform (Android + Windows) personal finance app built with Flutter.

## Features

- **Manual Entry** — Add transactions with account selector, type (debit/credit/transfer/investment), category, merchant, custom tags, date & time picker (Paytm-style)
- **Real-time Sync** — Powered by Supabase Realtime; add a transaction on phone, appears on Windows within seconds
- **Dashboard** — Emergency Fund progress card, Savings Rate (target 20%+), per-account balance breakdown, summary cards (Earned/Spent/Saved/Net) + category pie chart
- **Accounts** — Multiple accounts (SBI, Kotak, PayPal, Cash) with derived balances via `fn_account_balance()` — never stored, never drift
- **Transfers** — Double-entry transfer support: two linked rows with matching `transfer_group_id`, net worth unaffected
- **Investments** — `type = 'investment'` moves money from cash account to investment account, excluded from expense reports
- **Custom Tags** — Free-form tag input on every transaction (chip builder). Tags are normalised to lowercase, deduped, and shown as pills on each row.
- **Transaction Dates** — `transacted_at` is user-set via date/time picker; falls back to `created_at`. Balance calculation uses `COALESCE(transacted_at, created_at)`.
- **Paytm-Style List** — Transactions grouped by date ("Today", "Yesterday", "Fri, 27 Jun 2026"), 24hr time on each row.
- **Soft Delete** — Nothing is ever hard-deleted; `is_deleted` + `deleted_at` on all tables + confirmation dialog
- **Immutable Audit Trail** — `edit_history` JSONB stores old/new values + `edited_at` on every change
- **SMS Capture** — Auto-parse UPI SMS from PhonePe, GPay, Paytm (regex engine + SHA-256 dedup)
- **Smart Categorization** — Rule-based (priority-ordered) + Claude LLM fallback
- **Goals** — Set savings goals with live progress tracking; Emergency Fund goal detected by `type` field, pinned to top
- **Invoice Sidebar** — Track freelance invoices with 3 columns + FX rate / PayPal fee / FX loss chips
- **Finance Agent** — Claude-powered Q&A with tool-use (8 tools that query your actual data). Model switcher: Haiku 4.5 (default) + Sonnet 4.
- **Monthly Snapshots** — Pre-computed monthly aggregates written on first open of each new month

## Tech Stack

| Layer | Tech |
|---|---|
| Frontend | Flutter (Dart) |
| Backend / DB | Supabase (Postgres, Realtime) |
| State | Riverpod |
| Charts | fl_chart |
| LLM | Anthropic Claude API |
| SMS Parsing | Regex engine + SHA-256 dedup |

## Setup

### Prerequisites

- Flutter SDK (stable)
- Supabase account (free tier)
- Anthropic API key

### 1. Environment

Create `.env` in the project root (already done for this project):

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
CLAUDE_API_KEY=sk-ant-your-claude-key
```

### 2. Supabase (already applied for this project)

1. Create a project at [supabase.com](https://supabase.com)
2. Run `supabase/migrations/00001_init.sql` in the SQL editor (creates all 8 tables, RPCs, RLS, Realtime, seed accounts)
3. Run `supabase/migrations/00002_clear_add_transacted_at.sql` to add the `transacted_at` column and update `fn_account_balance`
4. Copy your project URL and anon key into `.env`

### 3. Run

```bash
flutter pub get
flutter run
```

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
│   ├── agent/                 # Chat UI + Claude tool-use service (8 tools), model switcher (Haiku 4.5 / Sonnet 4)
│   └── sms/                   # SMS parser + listener
└── widgets/                   # Shared UI components (EmptyState, SummaryCard)
```

## Build

```bash
# Android
flutter build appbundle

# Windows (requires `flutter create . --platforms windows` first)
flutter build windows
```

## Design Principles

- **AI never modifies money** — categorize/summarize/answer only. Edit/delete requires user confirmation.
- **Soft-delete everything** — `is_deleted` + `deleted_at` on all tables.
- **Double-entry transfers** — two rows linked by `transfer_group_id`, net worth unchanged.
- **Investments are not expenses** — `type = 'investment'`, net worth unchanged.
- **Immutable history** — `edit_history` JSONB stores every change.
- **Balances are derived** — `accounts` has `opening_balance` + `opening_date`. Current balance is `fn_account_balance()`. No `balance` column.
- **Agent uses tool-use, not context injection** — Claude decides which of the 8 tools to call per turn. No pre-fetching data.
- **No streaming** — Claude responses appear after 2–4s. SSE removed from scope permanently.
