# TODO: Production Checklist

## Phase 0: Project Setup

### Flutter Project Scaffold
- [x] Init Flutter project (scaffolded manually at repo root, `flutter pub get` resolves)
- [x] Set up folder structure: `lib/` with `features/`, `core/`, `models/`, `providers/`, `widgets/`
- [x] Add dependencies to `pubspec.yaml`:
  - [x] `supabase_flutter`
  - [x] `flutter_riverpod` / `riverpod`
  - [x] `fl_chart`
  - [ ] `another_telephony` / `flutter_sms_inbox` (needs real device, not added to pubspec yet)
  - [x] `intl` (INR formatting)
  - [x] `http` (Claude API calls)
  - [ ] `flutter_local_notifications` (SMS sync feedback, not added yet)
- [x] Configure `analysis_options.yaml` for strict linting
- [x] Set up `assets/` folder for icons, fonts
- [ ] Configure Android `AndroidManifest.xml` (SMS permissions, internet)
- [ ] Configure Windows app manifest

### Supabase Setup
- [ ] Create Supabase project
- [ ] Run migration SQL for all tables:
  - [x] SQL migration file created (`supabase/migrations/00001_init.sql`)
  - [ ] `transactions` (needs to be applied to live Supabase project)
  - [ ] `category_rules` (needs to be applied to live Supabase project)
  - [ ] `goals` (needs to be applied to live Supabase project)
  - [ ] `invoices` (needs to be applied to live Supabase project)
- [ ] Enable Realtime on `transactions` table
- [ ] Set RLS policies (open for v1, single anon key)
- [ ] Store anon key + project URL in `lib/core/constants.dart` (placeholder exists)
- [x] Set up Supabase client initialization in app (`lib/core/supabase.dart`)

---

## Phase 1: MVP -- Manual Entry + Cross-Device Sync (Day 1)

### Core Models & Providers
- [x] Create `Transaction` model (manual fromJson/toJson + copyWith)
- [x] Create `TransactionProvider` (Riverpod) -- CRUD via Supabase + Realtime subscription
- [x] Create `Goal` model
- [x] Create `GoalProvider` (load, add, allocate)
- [x] Create `Invoice` model (with computedStatus, outstanding, totalReceived)
- [x] Create `InvoiceProvider` (load, add)

### Transaction List Screen
- [x] Build transaction list UI (pull-to-refresh)
- [x] Real-time subscription -- new transactions appear without refresh
- [ ] Filter by date range, category, type
- [ ] Swipe-to-delete or edit action
- [x] Pagination limit (200 items, but no incremental pagination yet)

### Add Transaction Form
- [x] Build manual entry form: amount, type (debit/credit), category, VPA, merchant
- [x] Validation: amount required, positive number
- [x] Submit -> insert into Supabase -> appears via Realtime

### Dashboard Screen
- [x] Summary cards: Earned, Spent, Saved, Net (current month)
- [x] Category pie chart (`fl_chart`)
- [ ] Trend line chart (daily balance over 30 days)
- [x] Pull data from `transactions` table with aggregate queries (client-side)

### Navigation
- [x] Bottom nav bar: Transactions, Dashboard, Goals, Agent (4 tabs)
- [x] Invoice sidebar -- end drawer accessible via 5th bottom nav item
- [x] Highlight active tab

### Win Check: M1
- [ ] Add transaction on phone -> appears on Windows within 2s (needs Supabase project)

---

## Phase 2: SMS Capture (Day 2)

### SMS Listener Service
- [ ] Integrate `another_telephony` / `flutter_sms_inbox` (stub only, not wired)
- [ ] Request SMS permission on Android 13+
- [ ] Register SMS receiver / listener
- [ ] Filter messages by known bank VPA patterns (PhonePe, GPay, Paytm, etc.)

### SMS Parser (Regex Engine)
- [x] Regex patterns to extract: amount, type, VPA, merchant (4 pattern defs in `sms_parser.dart`)
- [ ] Collect 3-5 masked real UPI SMS samples per bank/app
- [ ] Handle edge cases: failed transactions, cashbacks, refunds
- [x] Parse result -> `Transaction` object
- [ ] Fallback to manual category assignment if rule match fails

### Auto-Categorization
- [x] `CategoryRule` model exists (match_pattern, category, tags, priority)
- [ ] Build rule engine: match VPA/merchant substring -> category + tags
- [ ] UI to manage rules (add/edit/delete)
- [ ] LLM fallback: if no rule matches, send transaction data to Claude
- [ ] Parse Claude response -> category + tags -> update transaction

### SMS-to-Transaction Pipeline
- [x] `SmsListener` class exists (stub -- emits `Transaction` via stream)
- [ ] New SMS detected -> parse -> insert into Supabase
- [ ] Show toast/notification: "Transaction added: Rs 500 at Swiggy"
- [ ] Handle duplicate detection (same raw_sms text already exists)

### Win Check: M2
- [ ] Real UPI SMS arrives -> auto-parsed -> appears correctly categorized

---

## Phase 3: Goals + Polish (Day 3)

### Goals Screen
- [x] List all goals with progress bars (% funded)
- [x] Add goal form: name, target amount
- [x] Allocate funds to goals (manual input)
- [x] Real-time updates -- % changes as new transactions come in
- [ ] Goal completion celebration (confetti / notification)

### Invoice Sidebar
- [x] Slide-in panel from right edge (end drawer)
- [x] Form: client, description, invoiced_usd, received_paypal, received_bank, invoice_date
- [x] Auto-calculate status: if received matches invoiced -> paid; partial -> partial
- [x] List all invoices with outstanding balance per row
- [x] Summary header: total invoiced vs total received
- [ ] Edit / delete invoice

### Polish & UX
- [x] Pull-to-refresh on all list screens
- [x] Empty state for each tab (EmptyState widget used)
- [x] Loading states (CircularProgressIndicator)
- [x] Error state with retry on Supabase failures
- [ ] Offline indicator when no network
- [ ] Dark mode toggle (follow system by default) -- dark only currently

### Win Check: M3
- [ ] Create goal -> allocate money -> % funded updates live across devices (needs Supabase project)

---

## Phase 4: Finance Agent (Day 4)

### Claude API Integration
- [x] HTTP client for Claude API (`http` package)
- [x] API key management (placeholder in constants, never hardcoded with real key)
- [ ] Build proper tool definitions for Claude (currently uses data-gathering + context injection):
  - [ ] `get_transactions(filters)` -- query Supabase
  - [ ] `get_category_breakdown(period)` -- aggregate by category
  - [ ] `get_goals()` -- current goals with progress
  - [x] `get_balance()` -- earned - spent (via `fn_current_balance` RPC)
  - [x] `get_invoice_summary()` -- invoiced vs received
- [x] Data gathering before sending to Claude (balance, tx summary, invoices, goals)

### Agent Chat UI
- [x] Chat-style interface (list of bubbles)
- [x] User input -> send to Claude with financial data context
- [ ] Claude decides which tools to call -> execute locally -> return result (tool-use pattern)
- [ ] Render tool calls as collapsible "thought" steps
- [ ] Streaming response (if Claude supports SSE)
- [x] Suggested questions chip row

### Categorization Fallback (Refine)
- [ ] Route unmatched transactions through agent for batch categorization
- [ ] Manual override: user can re-categorize any transaction
- [ ] Learn from manual overrides -- suggest rule creation

### Win Check: M4
- [ ] "Can I afford a new keyboard?" -> agent checks balance, goals, recent spend -> answers with reasoning
- [ ] "What did I waste money on?" -> agent returns top category with trend
- [ ] Follow-up questions maintain context

---

## Phase 5: Production Hardening

### Error Handling & Resilience
- [ ] Graceful degradation when Supabase is down (local cache)
- [ ] Retry logic for Claude API failures
- [x] SMS parsing validation -- reject malformed SMS (returns null on no match)
- [ ] Duplicate transaction prevention (idempotency key on raw_sms hash)

### Performance
- [ ] Pagination on transaction list (20 items per page, incremental loading)
- [ ] Debounce real-time updates if too frequent
- [ ] Lazy load chart data -- only render when tab is visible
- [ ] Profile Windows build startup time -> optimize
- [ ] Profile Android APK size -> remove unused assets/dependencies

### Security
- [ ] Move Supabase anon key to build config (not in version control)
- [ ] Move Claude API key to runtime config / env
- [ ] Verify no keys in crash logs or error stack traces
- [ ] RLS review before any public exposure
- [x] Sanitize inputs on manual entry forms (Form validation exists)

### Testing
- [ ] Unit tests for SMS regex parsers (with sample SMS strings)
- [ ] Unit tests for model serialization (fromJson/toJson roundtrip)
- [ ] Widget tests for each screen (empty state, populated state, error state)
- [ ] Integration test: add transaction -> appears on another device
- [ ] Integration test: SMS -> parse -> insert -> verify in DB
- [ ] Claude tool contract tests (mock API, verify tool selection)

### Build & Release
- [ ] Android:
  - [ ] Generate keystore
  - [ ] Configure `key.properties`
  - [ ] Build release APK / App Bundle (`flutter build appbundle`)
  - [ ] Test on physical device (Android 13+)
  - [ ] Deploy to Play Store internal test track (optional)
- [ ] Windows:
  - [ ] Build release MSIX / EXE (`flutter build windows`)
  - [ ] Test on clean Windows machine
  - [ ] Create installer (Inno Setup or MSIX)
- [ ] Version bump & changelog

---

## Phase 6: Boss Battle -- "Survive a Week"

- [ ] Run app for 7 consecutive days capturing all transactions
- [ ] Day 7: ask agent 3 questions:
  - [ ] "How much did I earn this week?" -> verify manually
  - [ ] "What category did I overspend in?" -> verify manually
  - [ ] "Am I closer to funding [a goal]?" -> verify manually
- [ ] Log any mismatches as bugs
- [ ] Fix bugs -> retest same 3 questions
- [ ] All 3 answers pass manual verification = **production ready**

---

## Backlog (Features for v2)

- [ ] Multi-currency support (auto-conversion rates)
- [ ] Recurring transaction detection & reminders
- [ ] Budgets per category with monthly rollover
- [ ] Export to CSV / PDF
- [ ] Bank statement import (PDF/CSV parsing)
- [ ] Auth (Supabase magic link) for multi-user expansion
- [ ] Push notifications for large transactions
- [ ] Receipt photo attachment to transactions
- [ ] Invoice PDF generation & email to client
- [ ] Tax report (annual summary for filing)
- [ ] Stock/investment portfolio tracking
- [ ] Bill splitting with friends

---

## Gaps Identified (code vs docs)

These items exist in PRD/TODO but are not yet implemented:

1. **Trend line chart** (Dashboard) -- PRD mentions daily balance over 30 days, only pie chart exists
2. **Transaction filters** -- No date range, category, or type filter on TransactionListScreen
3. **Swipe-to-delete / edit** -- No Dismissible or edit action on transaction cards
4. **Edit/delete invoices** -- No UI for editing or deleting invoices
5. **Category rules UI** -- No screen to manage rules (add/edit/delete)
6. **Auto-categorization engine** -- CategoryRule model exists but no code matches VPA/merchant to rules
7. **SMS integration** -- Stub only, `another_telephony` not in pubspec, no Android permissions
8. **Agent tool-use** -- Uses context injection instead of proper Claude tool calling
9. **Agent conversation history** -- No multi-turn context maintained
10. **Agent streaming** -- No SSE/streaming, waits for full response
11. **Android manifest** -- SMS + internet permissions not configured
12. **Windows manifest** -- Not configured
13. **Offline indicator** -- No network state detection
14. **Duplicate SMS detection** -- No hash-based idempotency
15. **Tests** -- No test files exist yet
