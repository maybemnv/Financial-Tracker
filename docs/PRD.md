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

### Resume Pointers

- "Built a cross-platform personal finance tracker (Flutter, Android + Windows) with real-time sync via Supabase/Postgres"
- "Designed a hybrid rule-based + LLM categorization engine for unstructured transaction data"
- "Implemented an agentic financial Q&A assistant using Claude tool-use over live SQL data"
- "Built SMS-based transaction ingestion pipeline with regex parsing across multiple bank formats"

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
    └── Claude tool-use → query Supabase → aggregate → answer NL question
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
| type       | text        | debit / credit             |
| vpa        | text        | nullable                   |
| merchant   | text        | nullable                   |
| bank       | text        | nullable                   |
| category   | text        | nullable until categorized |
| tags       | text[]      | default '{}'               |
| raw_sms    | text        | nullable                   |
| source     | text        | sms / manual               |
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
