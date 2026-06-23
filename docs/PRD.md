# PRD: Personal UPI Finance Tracker

A cross-platform (Android + Windows) personal finance system. Built solo, fast, with strict deadlines, designed to compound into resume material and a self-knowledge tool.

---

## 1. Requirements

### Features & Functionality

- UPI transaction capture via SMS (Android)
- Manual entry (both platforms)
- Cross-device real-time sync (Supabase)
- Categories: Food, Travel, Shopping, Work, Family, Health, Subscriptions, Other
- Cross-cutting tags (e.g. "startup", "freelance", "gift")
- Rule-based + LLM-fallback categorization
- Goals table: name, target_amount, allocated_amount, % funded
- Dashboard: Earned / Spent / Saved / Net + category pie + trend chart
- Finance agent (Claude-powered NL Q&A: "can I afford X?", "what did I waste money on?")
- Invoice sidebar: collapsible side panel logging freelance invoices with columns — Invoiced Amount (USD), Received in PayPal, Amount in Bank — to track outstanding vs. realized income
- Net Worth Card: Net Worth = Cash + PayPal + Investments - Debt, displayed as a historical chart
- Career Investment Tag: special tag applied to Keyboard, Claude, ChatGPT, Hosting, Domains, Courses — excluded from discretionary-spend calculations
- Invoice Metrics: derived fields for PayPal fee loss, FX conversion loss, effective INR/USD rate; enables agent questions like "How much money did PayPal cost me this year?"

### Tech Stack

- **Frontend** : Flutter (Android + Windows, single codebase)
- **Backend/DB** : Supabase (Postgres, Realtime, REST via `supabase_flutter`)
- **SMS parsing** : `another_telephony` / `flutter_sms_inbox` + regex
- **Charts** : `fl_chart`
- **Agent/LLM** : Anthropic API (Claude) — categorization fallback + NL query agent
- **State management** : Riverpod (locked, no mid-build flip-flopping)

### Concepts Touched (resume-relevant)

- Cross-platform app development (Flutter)
- Real-time data sync architecture
- SQL schema design + Postgres
- Regex-based unstructured text parsing (SMS)
- Rule engines + LLM-fallback hybrid classification
- Agentic tool-use (LLM querying a database to answer NL questions)
- Data visualization

### Time, Effort & Timeline

| Phase                                         | Effort  | Deadline |
| --------------------------------------------- | ------- | -------- |
| Planning (this doc + diagrams)                | 1–2 hrs | Day 0    |
| Phase 1 — MVP                                 | 4–6 hrs | Day 1    |
| Phase 2 — SMS capture                         | 2–3 hrs | Day 2    |
| Phase 3 — Smart categorization + goals polish | 2–3 hrs | Day 3    |
| Phase 4 — Finance agent                       | 2–3 hrs | Day 4    |

**Total: ~12–17 hrs across 4–5 days.** Each phase ships something usable — no big-bang integration risk.

### Milestones

- **M1** : Add a manual transaction on phone, see it appear on laptop within seconds
- **M2** : A real UPI SMS gets auto-parsed and shows up correctly categorized
- **M3** : Goals dashboard shows live % funded after a manual allocation
- **M4** : Ask the agent "can I afford a new keyboard?" and get a real, data-backed answer

---

## 2. Sources

Reference material to pull from when stuck — visit before reinventing:

- **Flutter + Supabase** : official `supabase_flutter` quickstart docs — auth-free table setup for single-user apps
- **SMS parsing on Android/Flutter** : `another_telephony` pub.dev docs + GitHub issues for permission handling on Android 13+
- **fl_chart** : pub.dev examples gallery — pie + line chart recipes, copy-paste starting points
- **UPI SMS format samples** : your own inbox — collect 3–5 real (masked) SMS from different transactions before writing regex, don't guess formats upfront
- **Claude API tool-use** : Anthropic docs on tool calling — same pattern as DataLens, you've done this before
- **Riverpod docs** : quickstart for basic provider pattern, skip codegen for v1

---

## 3. Goals

### Outcome Goals

- A working app on your phone and laptop that tracks every rupee, syncs live, and tells you what's going on with your money without manual spreadsheet work

### Self-Oriented / Journey-Based Goals

- Prove you can take a personal itch (no-tooling money tracking) and ship a real tool for yourself, end to end, without external pressure
- Practice scoping discipline — Phase 1 in one sitting, resist scope creep mid-build (log ideas to backlog instead of derailing)
- Build something that directly visualizes progress toward Phone/Keyboard/Monitor — turning first-paycheck energy into a visible, growing number
- Use this as low-stakes repetition of the Analytics Depot stack (Supabase, agent tool-use) to deepen those skills outside contractor pressure

---

## 4. Planning — Before You Touch Code

### Mind Map

```
Finance Tracker
├── Data Capture
│   ├── SMS listener (Android) → regex parser → transactions table
│   ├── Manual entry form (both platforms)
│   └── Invoice entry (manual) → invoices table
├── Storage (Supabase)
│   ├── transactions
│   ├── category_rules
│   ├── goals
│   └── invoices
├── Categorization
│   ├── Rule match (VPA/keyword → category + tags)
│   └── LLM fallback (Claude) for unmatched
├── Sync
│   └── Supabase Realtime → both devices reflect changes <2s
├── Visualization
│   ├── Summary cards (Earned/Spent/Saved/Net)
│   ├── Category pie chart
│   ├── Trend chart
│   └── Goals progress bars
└── Agent
    ├── Claude tool-use → query Supabase → aggregate → answer NL question
    └── Context injected per query: current balance, monthly burn, goal progress, committed recurring spend
```

### System Architecture

```
┌─────────────────┐         ┌─────────────────┐
│   Android App   │         │   Windows App   │
│  (Flutter)      │         │  (Flutter)      │
│                 │         │                 │
│ SMS Listener ───┼──┐      │                 │
│ Manual Entry    │  │      │ Manual Entry    │
│ Dashboard/Charts│  │      │ Dashboard/Charts│
│ Goals UI        │  │      │ Goals UI        │
│ Agent Chat      │  │      │ Agent Chat      │
│ Invoice Sidebar │  │      │ Invoice Sidebar │
└────────┬────────┘  │      └────────┬────────┘
         │           │               │
         │      ┌────▼───────────────▼─────┐
         └─────►│   Supabase (Postgres)     │
                │   - transactions           │
                │   - category_rules         │
                │   - goals                  │
                │   - invoices               │
                │   Realtime subscriptions   │
                └─────────────┬──────────────┘
                              │
                      ┌───────▼────────┐
                      │  Claude API    │
                      │  - categorize  │
                      │  - agent Q&A   │
                      └────────────────┘
```

### Database Schema (final — lock before coding)

**transactions**

| Column     | Type        | Notes                      |
| ---------- | ----------- | -------------------------- |
| id         | uuid PK     | default gen_random_uuid()  |
| amount     | numeric     |                            |
| type       | text        | debit / credit / transfer / investment |
| vpa        | text        | nullable                   |
| merchant   | text        | nullable                   |
| bank       | text        | nullable                   |
| category   | text        | nullable until categorized |
| tags       | text[]      | default '{}'               |
| raw_sms    | text        | nullable                   |
| raw_sms_hash | text      | nullable — sha256 for dedup |
| source     | text        | sms / manual               |
| note       | text        | nullable — user memo       |
| usd_amount | numeric     | nullable — for forex txns  |
| linked_invoice_id | uuid | nullable — connects PayPal/bank receipt to the invoice it pays |
| created_at | timestamptz | default now()              |
| updated_at | timestamptz | default now()              |

**category_rules**

| Column        | Type    | Notes                           |
| ------------- | ------- | ------------------------------- |
| id            | uuid PK |                                 |
| match_pattern | text    | substring match on vpa/merchant |
| category      | text    |                                 |
| tags          | text[]  | default '{}'                    |
| priority      | int     | lower = checked first           |

**goals**

| Column           | Type        | Notes         |
| ---------------- | ----------- | ------------- |
| id               | uuid PK     |               |
| name             | text        |               |
| type             | text        | emergency_fund / custom |
| target_amount    | numeric     |               |
| allocated_amount | numeric     | default 0     |
| created_at       | timestamptz | default now() |

**invoices**

| Column         | Type        | Notes                    |
| -------------- | ----------- | ------------------------ |
| id             | uuid PK     |                          |
| client         | text        |                          |
| description    | text        | nullable                 |
| invoiced_usd   | numeric     | amount invoiced in USD   |
| received_paypal| numeric     | amount received via PayPal|
| received_bank  | numeric     | amount received in bank  |
| status         | text        | pending / paid / partial |
| invoice_date   | date        |                          |
| created_at     | timestamptz | default now()            |
| updated_at     | timestamptz | default now()            |

### accounts

| Column      | Type        | Notes                              |
| ----------- | ----------- | ---------------------------------- |
| id          | uuid PK     |                                    |
| name        | text        | SBI, Kotak, PayPal, Cash           |
| type        | text        | bank / wallet / paypal / cash      |
| opening_balance | numeric | balance at opening_date |
| opening_date | date       | when tracking started |
| created_at  | timestamptz | default now()                      |

> Every transaction belongs to an account.
**recurring_expenses**

| Column      | Type        | Notes                              |
| ----------- | ----------- | ---------------------------------- |
| id          | uuid PK     |                                    |
| name        | text        | e.g. "Spotify", "SBI SIP"         |
| amount      | numeric     |                                    |
| frequency   | text        | monthly / weekly / yearly          |
| category    | text        |                                    |
| next_due    | date        | nullable                           |
| created_at  | timestamptz | default now()                      |

> Used by the agent to compute "committed money" — what's already spoken for before the month begins.

### Endpoints / Interactions (all via Supabase client SDK — no custom backend needed)

| Action                            | Table          | Operation                                                |
| --------------------------------- | -------------- | -------------------------------------------------------- |
| Insert parsed/manual transaction  | transactions   | insert                                                   |
| Fetch transaction list (filtered) | transactions   | select + filters                                         |
| Update category/tags on edit      | transactions   | update                                                   |
| Subscribe to live changes         | transactions   | realtime channel                                         |
| Fetch/create rules                | category_rules | select/insert                                            |
| Fetch/update goals                | goals          | select/update                                            |
| Categorize via LLM                | —              | Claude API call (not Supabase)                           |
| Agent query                       | —              | Claude API call w/ Supabase aggregate results as context |

### Pre-Build Decisions (lock now, no mid-build flip-flopping)

- State management: **Riverpod**
- Navigation: bottom nav bar -- 4 screen tabs (Transactions, Dashboard, Goals, Agent) + 5th Invoices tab that opens end drawer
- No auth for v1 — single anon Supabase key, RLS open (acceptable for personal single-device-pair use)
- Currency formatting: ₹, 2 decimals, locale en_IN

---

### Best Practices (lock now, no mid-build flip-flopping)

1. **Never let AI modify money** — AI can categorize, summarize, answer questions. It should NEVER edit transactions, delete transactions, or move money. Those actions require explicit user confirmation.

2. **Soft-delete everything** — Instead of deleting, use `is_deleted` boolean + `deleted_at` timestamp. One accidental swipe shouldn't erase six months of data.

3. **Double-entry style transfers** — When money moves between accounts (SBI → Kotak), don't create an expense. Create a transfer out + transfer in. Otherwise spending reports become nonsense.

4. **Immutable transaction history** — When a transaction changes, store old value, new value, and `edited_at`. Audit trail matters in compliance-heavy environments.

5. **Make dashboards boring** — The metrics you'll actually check: Current Cash, Net Worth, Savings Rate, Monthly Spend, Emergency Fund Progress. Everything else (17 charts, AI insights, pie charts everywhere) is secondary.

---

## 5. Execution — Strict Deadlines, Dopamine-Driven

Rules of engagement:

- Each phase = one sitting, timeboxed. If it runs over, ship what works and move the rest to `BACKLOG.md` — don't let scope rot the deadline.
- End of each phase = visible win (M1–M4). Demo it to yourself before moving on.
- No new feature ideas mid-phase — write them down, keep moving.

| Day   | Phase                                  | Deadline | Win Condition                                 |
| ----- | -------------------------------------- | -------- | --------------------------------------------- |
| Day 0 | Planning (this doc, schema lock)       | 1–2 hrs  | Schema finalized, no design decisions left    |
| Day 1 | Phase 1 — MVP                          | 4–6 hrs  | M1: cross-device manual entry sync works      |
| Day 2 | Phase 2 — SMS capture                  | 2–3 hrs  | M2: real SMS auto-categorized correctly       |
| Day 3 | Phase 3 — Goals + smart categorization | 2–3 hrs  | M3: goal % funded updates live                |
| Day 4 | Phase 4 — Finance agent                | 2–3 hrs  | M4: agent answers "can I afford X?" correctly |

Each milestone hit = proof the planning phase paid off — decisions made once, not re-litigated per phase.

---

## 6. Boss Battle — Trial & Error Challenge

A standalone mini-challenge to stress-test the system end to end, run **after Phase 4** .

**The Challenge: "Survive a Week"**

1. For 7 days, log every transaction (auto via SMS + manual for cash/edge cases)
2. On day 7, ask the agent three questions cold:
   - "How much did I earn this week?"
   - "What category did I overspend in?"
   - "Am I closer to funding [a goal]?"
3. Manually verify each answer against raw transaction data
4. Any mismatch = bug — log it, fix it, re-run the same three questions

**Failure modes to expect (and learn from):**

- SMS parser misses a bank format → add regex pattern, re-test
- LLM miscategorizes a merchant → add explicit rule, re-test
- Agent aggregates wrong date range → fix query, re-test
- Realtime sync lag/missed update → check subscription setup

  **Win condition** : all three answers match manual verification, with zero manual fixes needed during the week (only logged + fixed _after_ ).

This is the actual proof the system works — not the build, but a week of real use surviving contact with messy reality.

---

## 7. Future Features (Backlog — Do Not Touch Until Boss Battle Passes)

Ordered roughly by value vs. effort. Everything here is post-v1.

### Tier 1 — High value, low lift (ship these next)

**Monthly Budget Envelopes**
Set a per-category budget (e.g. Food = ₹8,000/month). Dashboard shows remaining per envelope in real time. A red indicator triggers when >80% spent. This directly fixes the "spent without tracking" problem.

**Committed Money View**
Uses the `recurring_expenses` table. Before the month begins, shows: income expected − committed spend (SIPs, subscriptions, recurring) = actually free money. Prevents the illusion of a healthy balance when SIPs haven't hit yet.

**Weekly Digest Notification (Android)**
Every Sunday, a local notification summarises: spent this week, top category, how far from nearest goal. No server needed — scheduled local notification on Android.

**USD ↔ INR Forex Layer**
Auto-fetch live exchange rate (free tier: exchangerate-api.com) when logging invoice receipts. Store `usd_amount` + `inr_equivalent` + `rate_at_time`. Lets the agent answer "how much did Vineet's payment actually land as in rupees."

---

### Tier 2 — High value, more effort

**Investment Tracker (Manual)**
A new `investments` table: SIP name, fund name, amount per month, start date, current NAV (manual update). Dashboard shows: total invested vs. current value, XIRR (computed client-side). No API needed in v1 — manual NAV entry is fine. This turns the app into your full money picture.

**Savings Rate Card**
One number on the dashboard: `(income − total spend) / income × 100`. Just a percentage. Turns abstract goals into a single metric you can move week over week. Target: 20%+.

**Cash Transaction Support**
Manual entry already exists but cash has no VPA/merchant. Add a "Cash" source type with optional location tag. Lets you log the Hauz Khas chai without it showing as uncategorized noise.

**Export to CSV / PDF**
One-tap monthly export. Useful for ITR filing as a contractor — all freelance income + categorized expenses in one file.

---

### Tier 3 — Future Manav problems

**Liquid Fund Tracker**
Once you start investing in liquid funds (post emergency fund), track units held + current NAV + redemption value. Needs manual NAV entry or a free MF API (mfapi.in — free, no auth).

**SGB / Gold ETF Tracker**
Log SGB units + purchase price. Auto-fetch current gold price and show P&L. Simple but satisfying once you hold any.

**NPS Contribution Log**
Track monthly NPS Tier 1 contributions + cumulative corpus. Simple table, no API. Mostly for tax clarity at year end — 80CCD(1B) ₹50,000 deduction is easy to forget.

**Tax Summary View**
End of financial year: total freelance income received (from invoices table), total 80C-eligible investments, estimated tax liability. Not financial advice — just a number to take to a CA or use for advance tax filing.

**Agent Memory**
Right now the agent has no memory between sessions. Future: store agent Q&A history in Supabase, inject last 5 exchanges as context. Makes "what did I ask last week" answerable and the agent feel genuinely persistent.

**Multi-currency Invoice Support**
If you ever take on non-INR clients beyond AD — GBP, EUR, etc. Extend `invoices` table with `currency` column, store raw foreign amount + INR equivalent at receipt date.

---

### Won't Do (log here so you stop reconsidering)

- Auth / multi-user — this is a personal tool, single anon key is fine forever
- Automated NAV/stock price fetch with paid APIs — free manual entry is good enough
- Bank statement PDF import — too much regex hell for too little gain when SMS works
- Notifications for every transaction — noise, not signal
