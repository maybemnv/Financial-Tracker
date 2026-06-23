# TODO: Production Checklist

## Phase 0: Project Setup

### Flutter Project Scaffold
- [x] Project scaffolded at repo root, `flutter pub get` resolves
- [x] Folder structure: `features/`, `core/`, `models/`, `providers/`, `widgets/`
- [x] Dependencies: supabase_flutter, flutter_riverpod, fl_chart, intl, http, flutter_dotenv
- [x] `analysis_options.yaml` with strict linting (prefer_const_constructors+declarations)
- [x] `assets/` folder created
- [x] `dart analyze` passes with 0 issues
- [ ] Configure Android `AndroidManifest.xml` (SMS permissions — RECEIVE_SMS + READ_SMS, internet)
- [ ] Configure Windows app manifest

### Supabase Setup
- [x] Migration SQL written (`supabase/migrations/00001_init.sql`) — 4 tables + RLS + triggers + RPC
- [ ] Create Supabase project and apply migration
- [ ] Update migration to match current schema (do this while project is still empty — schema changes after data exists require migrations):
  - [ ] Add `note`, `usd_amount`, `is_deleted`, `deleted_at`, `account_id`, `linked_invoice_id`, `transfer_group_id`, `raw_sms_hash`, `edit_history` (JSONB) to `transactions`
  - [ ] Allow `type` = `'transfer'` and `'investment'` in `transactions` — SIP/index fund moves are not expenses
  - [ ] Create `accounts` table (id, name, type, opening_balance, opening_date) — no `balance` column, derived from transactions via `fn_account_balance()`
  - [ ] Create `recurring_expenses` table (name, amount, frequency, category, next_due)
  - [ ] Create `recurring_income` table (name, amount, frequency, source, next_expected) — enables "Expected July Income"
  - [ ] Create `monthly_snapshots` table (month, year, income, expenses, savings, net_worth, recorded_at) — cheaper than recalculating forever
  - [ ] Add `type` column to `goals` (`emergency_fund`, `custom`) — dashboard detects emergency fund by type, not by name
  - [ ] Add `paypal_fee`, `fx_loss`, `fx_rate` columns to `invoices`
  - [ ] Remove `net_worth_history` table — replaced by `monthly_snapshots`
  - [ ] Create `fn_account_balance(account_id)` RPC — opens with opening_balance + SUM(credits) - SUM(debits)
  - [ ] Create `fn_net_worth()` RPC — SUM of fn_account_balance across all accounts
- [ ] Enable Realtime on required tables
- [ ] Verify RLS policies (open for v1, single anon key)

---

## Phase 1: MVP — Manual Entry + Cross-Device Sync

### Core Models & Providers
- [x] `Transaction` model (fromJson/toJson/copyWith)
- [x] `TransactionNotifier` — CRUD + Realtime subscription + pagination (200 limit)
- [x] `Goal` model + `GoalNotifier` (load, add, allocate)
- [ ] Update `Goal` model: add `type` field (`emergency_fund`, `custom`)
- [ ] Update `Transaction` model: add `transferGroupId`, `linkedInvoiceId`, `accountId`
- [x] `Invoice` model (computedStatus, outstanding, totalReceived) + `InvoiceNotifier`
- [ ] Update `Invoice` model: add `paypalFee`, `fxLoss`, `fxRate` fields
- [ ] Update `InvoiceProvider`: add `update`, `delete` methods
- [x] `CategoryRule` model (match_pattern, category, tags, priority)
- [ ] `Account` model + `AccountNotifier` (load, balance per account)
- [ ] `RecurringIncome` model + provider (load, project next expected)

### Transaction List Screen
- [x] Transaction list with pull-to-refresh
- [x] Realtime subscription (new transactions appear without refresh)
- [x] Pagination limit (200 items, no incremental loading)
- [ ] Filter by account (dropdown or chip row)

### Add Transaction Form
- [x] Manual entry: amount, type (debit/credit), category, VPA, merchant
- [x] Validation + loading state + error toast
- [ ] Add account selector (which account is this from/to)
- [ ] Add `investment` as a type option — with destination account field (e.g. "Nifty 50 fund")
- [ ] Add `transfer` type — creates two linked rows with matching `transfer_group_id`

### Dashboard Screen
- [x] Summary cards: Earned, Spent, Saved, Net (current month)
- [x] Category pie chart (fl_chart)
- [x] Data from transactions table (client-side aggregation)
- [ ] **Emergency Fund card — hero element, top of dashboard**
  - Progress bar: ₹X / ₹3,00,000 with % complete
  - Pulls from Goals table by `type = 'emergency_fund'` — not by name
  - This is the number that matters most right now
- [ ] Savings Rate card: `(income − spend) / income × 100` — single %, target 20%+
- [ ] Per-account balance breakdown (SBI / Kotak / PayPal / Cash)

### Invoice Sidebar
- [x] End drawer with 3-column layout (Invoiced USD, PayPal, Bank)
- [x] Add invoice form with date picker
- [x] Auto status (paid/partial/pending) + summary header
- [ ] Show FX rate + PayPal fee fields (display only, computed from received amounts)

### Navigation
- [x] Bottom nav: Transactions, Dashboard, Goals, Agent + 5th tab opens invoice drawer
- [x] FAB on Transactions tab only

### Win Check: M1
- [ ] Add transaction on phone — appears on Windows within 2s (needs live Supabase project)

---

## Phase 2: SMS Capture

### SMS Listener Service
- [x] `SmsListener` stub class (singleton with StreamController)
- [ ] Integrate `another_telephony` / `flutter_sms_inbox`
- [ ] Request SMS permission on Android 13+ (runtime prompt, not just manifest)
- [ ] Register SMS receiver and wire to SmsListener

### SMS Parser (Regex Engine)
- [x] 4 pattern defs extracting amount, type, merchant from UPI SMS
- [x] Parse result → `Transaction` object (returns null on no match)
- [ ] Collect 5 real SMS samples from PSB + Kotak inbox before finalising regex — don't guess formats

### SMS-to-Transaction Pipeline
- [ ] Wire SmsListener → SmsParser.parse → TransactionNotifier.add
- [ ] Show toast: "Transaction added: ₹X at Merchant"
- [ ] Duplicate detection (hash raw_sms before insert)

### Win Check: M2
- [ ] Real PSB or Kotak UPI SMS auto-parsed and appears correctly categorised

---

## Phase 3: Goals + Polish

### Goals Screen
- [x] Goal list with progress bars (% funded, LinearProgressIndicator)
- [x] Add goal dialog (name, target amount)
- [x] Allocate funds dialog (manual amount input)
- [x] Loading, empty, error states
- [ ] Pin "Emergency Fund" goal to top always

### Polish & UX
- [x] Pull-to-refresh on all list screens
- [x] Empty state widget (icon + title + subtitle)
- [x] Loading indicators + error state with retry
- [ ] Offline indicator (network state detection)

---

## Phase 4: Finance Agent

### Claude API Integration
- [x] HTTP client configured (`http` package)
- [x] API key loaded from `.env` via flutter_dotenv
- [x] Data gathering before sending: accounts (fn_account_balance), tx summary, invoices, goals
- [ ] Proper Claude tool-use (tool definitions, tool call execution loop)
- [ ] Conversation history maintenance (multi-turn context)
- [ ] Structured context injected per query: balance per account via `fn_account_balance`, monthly burn, goal progress, committed recurring spend, expected income

### Agent Chat UI
- [x] Chat bubble UI (user left, agent right)
- [x] Suggested questions chip row
- [ ] Collapsible "thought" step rendering for tool calls
- [ ] ~~Streaming response (SSE)~~ — **removed**: 80% complexity, 5% value for a personal tool. 2–4s wait is fine.

### Win Check: M4
- [ ] "Can I afford X?" → agent returns data-backed answer citing actual balance + committed spend

---

## Phase 5: Production Hardening

### Soft Deletion
- [ ] `is_deleted` / `deleted_at` handling in all providers (filter in queries, skip in UI)
- [ ] Confirm delete dialog — AI never deletes, user must confirm

### Immutable Audit Trail
- [ ] Store edit history (old_value, new_value, edited_at) on transaction updates via `edit_history` JSONB

### Monthly Snapshot Job
- [ ] On first open of a new month, write a row to `monthly_snapshots` with prior month totals
- [ ] Use snapshots for trend chart instead of recalculating from raw transactions

### Error Handling & Resilience
- [ ] Graceful degradation when Supabase is down (local cache or offline state)
- [ ] Retry logic for Claude API failures (no streaming to manage)
- [ ] Duplicate transaction prevention (raw_sms hash)

### Performance
- [ ] Incremental pagination (20 items per page, load more on scroll)
- [ ] Lazy load charts — only render when tab is visible

### Security
- [x] Keys loaded from `.env` (gitignored), not hardcoded
- [ ] Fix soft delete: pass `DateTime.now().toIso8601String()` not `'now()'` string literal in all providers
- [ ] Add `raw_sms_hash` to SMS pipeline: compute SHA-256 on insert, check hash for duplicates
- [ ] Verify no keys in crash logs or error stack traces
- [ ] RLS review before any public exposure

### Testing
- [ ] Unit tests for SMS regex parsers (use real masked SMS strings from your inbox)
- [ ] Unit tests for model serialization (fromJson/toJson roundtrip)
- [ ] Widget tests for each screen (empty, populated, error states)

### Build & Release
- [ ] Android: generate keystore, configure key.properties, build APK
- [ ] Windows: build release EXE (`flutter build windows`)

---

## Phase 6: Boss Battle — "Survive a Week"

- [ ] 7 days capturing all transactions (auto SMS + manual for cash)
- [ ] Day 7: ask agent 3 questions cold — verify answers manually against raw data
- [ ] All 3 match = production ready

Questions to ask:
- "How much did I earn this week?"
- "What category did I overspend in?"
- "Am I closer to funding my Emergency Fund?"

---

## Design Constraints (locked — no code changes, document only)

- **AI never modifies money** — categorise/summarise/answer only. Edit/delete/move requires explicit user confirmation.
- **Soft-delete everything** — `is_deleted` + `deleted_at` on all tables. Nothing is ever hard-deleted.
- **Double-entry transfers** — transfer out + transfer in as two rows linked by `transfer_group_id`. Never a single expense.
- **Investments are not expenses** — `type = 'investment'` moves money from cash account to investment account. Net worth unchanged.
- **Immutable history** — store old/new values and edited_at on every change.
- **Boring dashboard first** — Emergency Fund progress, Savings Rate, Monthly Spend, Per-Account Balance before any fancy charts.
- **Balances are derived, not stored** — `accounts` has `opening_balance` + `opening_date`. Current balance is `fn_account_balance()`. No `balance` column to drift.
- **Career Investment tag** — Keyboard, domains, hosting, Claude API costs, courses = tagged separately, excluded from discretionary spend reports.
- **Invoice FX fields** — PayPal fee, FX loss, FX rate are derived display fields from received amounts. No manual entry needed.
- **No streaming** — Claude responses appear after 2–4s. SSE removed from scope permanently.
- **Transaction attachments** (backlog) — Invoice PDFs, receipts, and screenshots attached to transactions. Not in v1 scope. Noted here so future schema changes leave room.
