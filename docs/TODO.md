# TODO: Production Checklist

## Phase 0: Project Setup

### Flutter Project Scaffold
- [ ] Init Flutter project (`flutter create --org com.finance finance_tracker`)
- [ ] Set up folder structure: `lib/` with `features/`, `core/`, `models/`, `providers/`, `widgets/`
- [ ] Add dependencies to `pubspec.yaml`:
  - [ ] `supabase_flutter`
  - [ ] `flutter_riverpod` / `riverpod`
  - [ ] `fl_chart`
  - [ ] `another_telephony` / `flutter_sms_inbox`
  - [ ] `intl` (INR formatting)
  - [ ] `http` / `dio` (Claude API calls)
  - [ ] `flutter_local_notifications` (SMS sync feedback)
- [ ] Configure `analysis_options.yaml` for strict linting
- [ ] Set up `assets/` folder for icons, fonts
- [ ] Configure Android `AndroidManifest.xml` (SMS permissions, internet)
- [ ] Configure Windows app manifest

### Supabase Setup
- [ ] Create Supabase project
- [ ] Run migration SQL for all tables:
  - [ ] `transactions`
  - [ ] `category_rules`
  - [ ] `goals`
  - [ ] `invoices`
- [ ] Enable Realtime on `transactions` table
- [ ] Set RLS policies (open for v1, single anon key)
- [ ] Store anon key + project URL in `.env` / flutter config
- [ ] Set up Supabase client initialization in app

---

## Phase 1: MVP — Manual Entry + Cross-Device Sync (Day 1)

### Core Models & Providers
- [ ] Create `Transaction` model (freezed or manual fromJson/toJson)
- [ ] Create `TransactionProvider` (Riverpod) — CRUD via Supabase
- [ ] Create `Goal` model
- [ ] Create `GoalProvider`
- [ ] Create `Invoice` model
- [ ] Create `InvoiceProvider`

### Transaction List Screen
- [ ] Build transaction list UI (pull-to-refresh, infinite scroll or paginated)
- [ ] Real-time subscription — new transactions appear without refresh
- [ ] Filter by date range, category, type
- [ ] Swipe-to-delete or edit action

### Add Transaction Form
- [ ] Build manual entry form: amount, type (debit/credit), category, tags, notes
- [ ] Validation: amount required, positive number
- [ ] Submit → insert into Supabase → confirm on other device within 2s

### Dashboard Screen
- [ ] Summary cards: Earned, Spent, Saved, Net (current month)
- [ ] Category pie chart (`fl_chart`)
- [ ] Trend line chart (daily balance over 30 days)
- [ ] Pull data from `transactions` table with aggregate queries

### Navigation
- [ ] Bottom nav bar: Transactions, Dashboard, Goals, Agent
- [ ] Invoice sidebar — slide-in panel from edge
- [ ] Highlight active tab

### Win Check: M1
- [ ] Add transaction on phone → appears on Windows within 2s
- [ ] Add transaction on Windows → appears on phone within 2s

---

## Phase 2: SMS Capture (Day 2)

### SMS Listener Service
- [ ] Integrate `another_telephony` / `flutter_sms_inbox`
- [ ] Request SMS permission on Android 13+
- [ ] Register SMS receiver / listener
- [ ] Filter messages by known bank VPA patterns (PhonePe, GPay, Paytm, etc.)

### SMS Parser (Regex Engine)
- [ ] Collect 3–5 masked real UPI SMS samples per bank/app
- [ ] Write regex patterns to extract: amount, type, VPA, merchant, bank
- [ ] Handle edge cases: failed transactions, cashbacks, refunds
- [ ] Parse result → `Transaction` object
- [ ] Fallback to manual category assignment if rule match fails

### Auto-Categorization
- [ ] Build rule engine: match VPA/merchant substring → category + tags
- [ ] Store rules in `category_rules` table
- [ ] UI to manage rules (add/edit/delete)
- [ ] LLM fallback: if no rule matches, send transaction data to Claude
- [ ] Parse Claude response → category + tags → update transaction

### SMS-to-Transaction Pipeline
- [ ] New SMS detected → parse → insert into Supabase
- [ ] Show toast/notification: "Transaction added: ₹500 at Swiggy"
- [ ] Handle duplicate detection (same raw_sms text already exists)

### Win Check: M2
- [ ] Real UPI SMS arrives → auto-parsed → appears correctly categorized
- [ ] Unrecognized merchant → LLM fallback assigns reasonable category

---

## Phase 3: Goals + Polish (Day 3)

### Goals Screen
- [ ] List all goals with progress bars (% funded)
- [ ] Add goal form: name, target amount
- [ ] Allocate funds to goals (manual input)
- [ ] Real-time updates — % changes as new transactions come in
- [ ] Goal completion celebration (confetti / notification)

### Invoice Sidebar
- [ ] Slide-in panel from right edge
- [ ] Form: client, description, invoiced_usd, received_paypal, received_bank, invoice_date
- [ ] Auto-calculate status: if received matches invoiced → paid; partial → partial
- [ ] List all invoices with outstanding balance per row
- [ ] Summary header: total invoiced vs total received
- [ ] Edit / delete invoice

### Polish & UX
- [ ] Pull-to-refresh on all list screens
- [ ] Empty state illustrations for each tab
- [ ] Loading skeletons for dashboard aggregates
- [ ] Error toast on Supabase failures
- [ ] Offline indicator when no network
- [ ] Dark mode toggle (follow system by default)

### Win Check: M3
- [ ] Create goal → allocate money → % funded updates live across devices
- [ ] Invoice added in sidebar → reflects in dashboard aggregates if desired

---

## Phase 4: Finance Agent (Day 4)

### Claude API Integration
- [ ] Set up Anthropic SDK / HTTP client
- [ ] API key management (env var, never hardcoded)
- [ ] Build tool definitions for Claude:
  - [ ] `get_transactions(filters)` — query Supabase
  - [ ] `get_category_breakdown(period)` — aggregate by category
  - [ ] `get_goals()` — current goals with progress
  - [ ] `get_balance()` — earned - spent
  - [ ] `get_invoice_summary()` — invoiced vs received

### Agent Chat UI
- [ ] Chat-style interface (list of bubbles)
- [ ] User input → send to Claude with tool definitions + conversation history
- [ ] Claude decides which tools to call → execute locally → return result
- [ ] Render tool calls as collapsible "thought" steps
- [ ] Streaming response (if Claude supports SSE)
- [ ] Suggested questions chip row: "Can I afford X?", "What did I spend most on?", "Am I on track for [goal]?"

### Categorization Fallback (Refine)
- [ ] Route unmatched transactions through agent for batch categorization
- [ ] Manual override: user can re-categorize any transaction
- [ ] Learn from manual overrides — suggest rule creation

### Win Check: M4
- [ ] "Can I afford a new keyboard?" → agent checks balance, goals, recent spend → answers with reasoning
- [ ] "What did I waste money on?" → agent returns top category with trend
- [ ] Follow-up questions maintain context

---

## Phase 5: Production Hardening

### Error Handling & Resilience
- [ ] Graceful degradation when Supabase is down (local cache)
- [ ] Retry logic for Claude API failures
- [ ] SMS parsing validation — reject malformed SMS, log for review
- [ ] Duplicate transaction prevention (idempotency key on raw_sms hash)

### Performance
- [ ] Pagination on transaction list (20 items per page)
- [ ] Debounce real-time updates if too frequent
- [ ] Lazy load chart data — only render when tab is visible
- [ ] Profile Windows build startup time → optimize
- [ ] Profile Android APK size → remove unused assets/dependencies

### Security
- [ ] Move Supabase anon key to build config (not in version control)
- [ ] Move Claude API key to runtime config / env
- [ ] Verify no keys in crash logs or error stack traces
- [ ] RLS review before any public exposure
- [ ] Sanitize inputs on manual entry forms

### Testing
- [ ] Unit tests for SMS regex parsers (with sample SMS strings)
- [ ] Unit tests for model serialization (fromJson/toJson roundtrip)
- [ ] Widget tests for each screen (empty state, populated state, error state)
- [ ] Integration test: add transaction → appears on another device
- [ ] Integration test: SMS → parse → insert → verify in DB
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

## Phase 6: Boss Battle — "Survive a Week"

- [ ] Run app for 7 consecutive days capturing all transactions
- [ ] Day 7: ask agent 3 questions:
  - [ ] "How much did I earn this week?" → verify manually
  - [ ] "What category did I overspend in?" → verify manually
  - [ ] "Am I closer to funding [a goal]?" → verify manually
- [ ] Log any mismatches as bugs
- [ ] Fix bugs → retest same 3 questions
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
