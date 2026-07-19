# Architecture

Flutter web personal finance app backed by Supabase (Postgres + Realtime) with a Gemini-powered finance agent.

---

## System Overview

```mermaid
graph TB
    subgraph WebApp["Web App (flutter build web)"]
        ME["Manual Entry"]
    end

    subgraph Supabase["Supabase (Postgres + Realtime)"]
        TX[transactions]
        LB[labels]
        TL[transaction_labels]
        CR[category_rules]
        GL[goals]
        IV[invoices]
        AC[accounts]
        RE[recurring_expenses]
        RI[recurring_income]
        MS[monthly_snapshots]
        CS[chat_sessions]
    end

    subgraph Gemini["Gemini API (2.5 Flash)"]
        CAT[categorization fallback]
        AGT[agent Q&A]
    end

    WebApp -->|insert / select / subscribe| Supabase
    Supabase -->|realtime push| WebApp

    WebApp -.->|unmatched tx / question| Gemini
    Gemini -.->|category + tags / answer| WebApp
```

---

## Navigation Structure

```mermaid
graph TD
    AppShell["AppShell (Scaffold + endDrawer)"] --> AppTabs["AppTabs (IndexedStack)"]
    AppShell --> InvoiceSidebar["InvoiceSidebar (endDrawer)"]

    AppTabs --> Tab0["0: TransactionListScreen (Ledger)"]
    AppTabs --> Tab1["1: DashboardScreen (Briefing)"]
    AppTabs --> Tab2["2: GoalsScreen (Targets)"]
    AppTabs --> Tab3["3: AgentChatScreen (Agent Desk)"]

    Tab0 --> FAB["FAB"] --> AddTx["AddTransactionScreen (push, also edit mode)"]
    Tab2 --> AddGoal["Add Goal Dialog"]
    Tab2 --> Allocate["Allocate Dialog"]
    Tab1 --> PieChart["Category Pie Chart"]

    BottomNav["BottomNavigationBar (5 items)"] -->|index 0-3| AppTabs
    BottomNav -->|index 4| InvoiceSidebar
```

5 bottom nav items (labels as shipped):
- Ledger (index 0, FAB visible; card edit button pushes `AddTransactionScreen` in edit mode)
- Briefing (index 1)
- Targets (index 2)
- Agent Desk (index 3)
- Invoices (index 4 — opens end drawer instead of switching tab)

**Planned (Phase 8):** Analytics becomes the fifth primary destination; invoice
access moves to an app-bar/drawer action so the bar stays at five items.

---

## State Management

All state managed by Riverpod `StateNotifierProvider`.

```mermaid
graph LR
    subgraph Providers["StateNotifierProviders"]
        TN["TransactionNotifier<br/>List<Transaction>"]
        GN["GoalNotifier<br/>List<Goal>"]
        IN["InvoiceNotifier<br/>List<Invoice>"]
    end

    subgraph Derived["Derived Providers (FutureProvider)"]
        AB["accountBalancesProvider<br/>Map account_id -> balance"]
        NW["netWorthProvider<br/>double"]
        DA["DashboardAnalytics<br/>(pure computation class)"]
    end

    subgraph Supabase["Supabase"]
        TXT[transactions]
        GLT[goals]
        IVT[invoices]
    end

    subgraph Screens["Screens"]
        TLS["TransactionListScreen<br/>AddTransactionScreen"]
        DS["DashboardScreen"]
        GS["GoalsScreen"]
        IS["InvoiceSidebar"]
    end

    TN <-->|select/insert/update/delete + subscribe| TXT
    GN <-->|select/insert + subscribe| GLT
    IN <-->|select/insert + subscribe| IVT

    AB -->|calls RPC per account| TXT
    NW -->|calls fn_net_worth| TXT
    DA -->|computes from| TN

    TLS -->|watch| TN
    DS -->|watch| TN
    DS -->|watch| AB
    DS -->|watch| NW
    GS -->|watch| GN
    IS -->|watch| IN
```

Each provider:
1. Calls `load()` on creation (SELECT with order, no limit — all non-deleted rows)
2. Subscribes to Realtime channel (pushes trigger `load()` on change)
3. Exposes `add()`, `update()`, `delete()` that call Supabase then refresh local state

The `DashboardScreen` uses a `WidgetsBindingObserver` to call `_refresh()` on mount and app resume — invalidating all account/balance providers and reloading the transaction provider so metrics are always fresh.

---

## Data Flow: Transaction Lifecycle

```mermaid
sequenceDiagram
    actor User
    participant App
    participant Provider as TransactionNotifier
    participant Supabase

    alt Manual Entry
        User->>App: Fill form + tap Save
        App->>Provider: add(tx)
        Provider->>Supabase: INSERT ... RETURNING *
        Provider->>Supabase: replace transaction_labels rows
        Supabase-->>Provider: inserted row
        Provider->>App: reload list
        App-->>User: success
    else Realtime Sync
        Note over App: Other device/tab
        Supabase-->>Provider: PostgresChanges event
        Provider->>Supabase: SELECT (full reload — Phase 7 replaces with patching)
        Provider->>App: rebuild UI
    else Edit / Delete
        User->>App: tap edit / long-press delete
        App->>Provider: update(tx) or delete(id)
        Provider->>Supabase: UPDATE (+ edit_history) or soft DELETE
        Provider->>App: refresh list
    end
```

Transfers and investments insert **two linked legs** (`transfer_group_id`,
explicit `direction` per leg) via `addTransfer`/`addInvestment`.

**Planned (Phase 5):** the update path (separate field UPDATE + label
replacement) is replaced by one `save_transaction_with_labels` RPC that writes
fields, labels, and primary label atomically with a single audit entry.

---

## Data Flow: Agent Q&A

```mermaid
sequenceDiagram
    actor User
    participant App as AgentChatScreen
    participant LS as LlmService
    participant Supabase
    participant Gemini

    User->>App: "Can I afford a new keyboard?"
    App->>LS: sendMessage(question)
    LS->>Gemini: POST /chat/completions (10 tool definitions, tool_choice auto)

    loop Tool-call loop (up to 10 rounds)
        Gemini-->>LS: tool_calls: get_net_worth
        LS->>Supabase: fn_net_worth() RPC
        Supabase-->>LS: 45000
        LS->>Gemini: role:tool result 45000

        opt More tools needed
            Gemini-->>LS: tool_calls: get_transactions / get_goals / ...
            LS->>Supabase: SELECT from relevant table
            Supabase-->>LS: data
            LS->>Gemini: role:tool result
        end
    end

    Gemini-->>LS: text response
    LS->>Supabase: persist chat_sessions (best-effort)
    LS-->>App: render answer bubble
    App-->>User: answer with data citations
```

Agent uses the **tool-call pattern** — Gemini decides which of the 10 read-only
tools to call each turn (`gemini-2.5-flash` via the OpenAI-compatible
endpoint). No tool can modify data.

**Planned (Phase 3):** this entire loop moves into an authenticated Supabase
Edge Function; the browser sends only the conversation and receives the answer
plus privacy-safe tool-activity metadata. `GEMINI_API_KEY` leaves the client
bundle and is rotated.

---

## Parsing and Classification (dormant)

Native SMS capture was **removed** with the Android runner; the app is
web-only. Two building blocks are retained for the Phase 10 quick-capture
feature and remain unused at runtime today:

- `lib/features/sms/sms_parser.dart` — pure Dart regex parser for UPI-style
  bank messages (future paste/import parsing).
- `category_rules` table + `CategoryRule` model — priority-ordered matching
  engine, dormant since labels replaced categories/tags (migration `00005`).

**Planned (Phase 10):** quick capture parses one-field input (`250 biryani
cash`) deterministically first (amount token, account-name match, label
keywords), with Gemini as fallback — always producing a reviewable draft,
never a silent save.

---

## Key Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| State management | Riverpod (StateNotifier) | Simple, no codegen, testable. Locked — no second state system. |
| Navigation | IndexedStack + bottom nav | Preserves tab state, fast switching |
| Invoice access | End drawer via 5th nav item | No dedicated screen needed (moves to app-bar action when Analytics takes the slot, Phase 8) |
| Data sync | Supabase Realtime (PostgresChanges) | Sub-second cross-device, no polling. Full-reload handler is defect D4; row patching planned (Phase 7). |
| SMS integration | Removed (web-only); pure Dart parser retained | Feeds future quick-capture/paste parsing, not runtime capture |
| Agent approach | Gemini tool-calls (10 read-only tools) | Model decides which queries to run per turn — no pre-fetching. Browser-direct today; Edge Function planned (Phase 3). |
| Agent model | `gemini-2.5-flash` via OpenAI-compatible endpoint | Single model; no switcher |
| Transaction dates | `transacted_at` (user-set) + `created_at` (server) | `transacted_at` is the actual money-move date; falls back to `created_at` for display/balance calculation |
| Ledger direction | `direction` column (`inflow`/`outflow`) | Independent of `type` — the RPC uses `direction` directly so transfer/investment legs balance correctly. Model helpers `isInflow`/`isOutflow` fall back to `type` for backward compatibility. |
| Account selection | Explicit, required, always visible in forms | Cash spends must hit Cash, bank spends the selected bank; never a silent default (PRD §5.1) |
| Dashboard refresh | `WidgetsBindingObserver` + `ref.invalidate()` | On mount and app resume, all providers are invalidated so metrics reflect the latest DB state. Pull-to-refresh also reloads the transaction provider. |
| Dashboard analytics | `DashboardAnalytics.fromTransactions()` | Pure computation over the full ledger — replaced by aggregate RPCs + canonical metrics in Phases 7–8 (its even multi-label split is defect D3) |
| Auth | None today (single anon key) — **being replaced** | Single-owner Supabase Auth + owner-only RLS is Phase 2; open policies are defect D5, not an accepted end state |
| Charts | fl_chart | Locked — no second chart library. Analytics is capped at four primary charts (PRD §8). |

---

## Planned Architecture Changes (summary)

In dependency order (details in `docs/enhancement.md` / `docs/TODO.md`):

1. **Auth gate** wrapping the app shell: session restore → owner check →
   finance providers. Fail-closed for non-owners.
2. **Supabase Edge Function** for Agent Desk (the only new infrastructure).
3. **Correctness layer:** explicit-account enforcement + Family Support flag,
   primary labels with one transactional save RPC, goal contributions.
4. **Data layer:** cursor-paginated ledger, row-level Realtime patching,
   aggregate RPCs (`get_briefing_summary`, `get_analytics`,
   `get_account_balances`), monthly + account-balance snapshots.
5. **Presentation:** numbers-only Briefing; separate Analytics tab with exactly
   four charts; lazy tab initialization.
 6. **Web platform:** `flutter_bootstrap.js` startup surface, browser-agnostic
    JS/Dart resume handshake with bounded WebGL-context-loss recovery, 24-hour
    local drafts (installed-PWA resume reliability for the mobile Brave
    shortcut; Brave on desktop + Helium/Zen possible future browsers — no
    native app).
