# Architecture

Cross-platform Flutter app backed by Supabase (Postgres + Realtime) with a Claude-powered finance agent.

---

## System Overview

```mermaid
graph TB
    subgraph Android["Android App"]
        SMS["SMS Listener"]
        ME["Manual Entry"]
    end

    subgraph Windows["Windows App"]
        MEW["Manual Entry"]
    end

    subgraph Supabase["Supabase (Postgres + Realtime)"]
        TX[transactions]
        CR[category_rules]
        GL[goals]
        IV[invoices]
        AC[accounts]
        RE[recurring_expenses]
        RI[recurring_income]
        MS[monthly_snapshots]
    end

    subgraph Claude["Anthropic Claude API"]
        CAT[categorization fallback]
        AGT[agent Q&A]
    end

    Android -->|insert / select / subscribe| Supabase
    Windows -->|insert / select / subscribe| Supabase
    Supabase -->|realtime push| Android
    Supabase -->|realtime push| Windows

    Android -.->|unmatched tx| Claude
    Claude -.->|category + tags| Android
    Android -.->|question + context| Claude
    Claude -.->|answer| Android
    Windows -.->|question + context| Claude
    Claude -.->|answer| Windows
```

---

## Navigation Structure

```mermaid
graph TD
    AppShell["AppShell (Scaffold + endDrawer)"] --> AppTabs["AppTabs (IndexedStack)"]
    AppShell --> InvoiceSidebar["InvoiceSidebar (endDrawer)"]

    AppTabs --> Tab0["0: TransactionListScreen"]
    AppTabs --> Tab1["1: DashboardScreen"]
    AppTabs --> Tab2["2: GoalsScreen"]
    AppTabs --> Tab3["3: AgentChatScreen"]

    Tab0 --> FAB["FAB"] --> AddTx["AddTransactionScreen (push)"]
    Tab2 --> AddGoal["Add Goal Dialog"]
    Tab2 --> Allocate["Allocate Dialog"]
    Tab1 --> PieChart["Category Pie Chart"]

    BottomNav["BottomNavigationBar (5 items)"] -->|index 0-3| AppTabs
    BottomNav -->|index 4| InvoiceSidebar
```

5 bottom nav items:
- Transactions (index 0, FAB visible)
- Dashboard (index 1)
- Goals (index 2)
- Agent (index 3)
- Invoices (index 4 — opens end drawer instead of switching tab)

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

    TLS -->|watch| TN
    DS -->|watch| TN
    GS -->|watch| GN
    IS -->|watch| IN
```

Each provider:
1. Calls `load()` on creation (SELECT with order + limit)
2. Subscribes to Realtime channel (pushes trigger `load()` on change)
3. Exposes `add()`, `update()`, `delete()` that call Supabase then refresh local state

---

## Data Flow: Transaction Lifecycle

```mermaid
sequenceDiagram
    actor User
    participant App
    participant Provider as TransactionNotifier
    participant Supabase
    participant Claude

    alt Manual Entry
        User->>App: Fill form + tap Save
        App->>Provider: add(tx)
        Provider->>Supabase: INSERT ... RETURNING *
        Supabase-->>Provider: inserted row
        Provider->>App: prepend to list
        App-->>User: success toast
    else SMS Auto-Capture
        Note over App: Android only
        SMS->>App: onSmsReceived
        App->>App: SmsParser.parse(raw)
        alt parse succeeded
            App->>Provider: add(tx)
            Provider->>Supabase: INSERT
            App-->>User: toast "₹500 at Swiggy"
        else no match
            App-->>User: toast "Unrecognised SMS"
        end
    else Realtime Sync
        Note over App: Other device
        Supabase-->>Provider: PostgresChanges event
        Provider->>Supabase: SELECT (reload)
        Provider->>App: rebuild UI
    else Edit / Delete
        User->>App: swipe or tap edit
        App->>Provider: update(tx) or delete(id)
        Provider->>Supabase: UPDATE or soft DELETE
        Provider->>App: refresh list
    end
```

---

## Data Flow: Agent Q&A

```mermaid
sequenceDiagram
    actor User
    participant App as AgentChatScreen
    participant Supabase
    participant Claude

    User->>App: "Can I afford a new keyboard?"
    App->>App: Gather financial data
    App->>Supabase: fn_current_balance(accountId)
    App->>Supabase: SELECT transactions (30d sum)
    App->>Supabase: SELECT invoices (totals)
    App->>Supabase: SELECT goals (progress)
    App->>Supabase: SELECT recurring_expenses (committed)
    Supabase-->>App: all data

    App->>Claude: POST /v1/messages
    Note over App,Claude: system: "Answer using only this data"<br/>context: balance, tx summary, goals, invoices<br/>question: user question
    Claude-->>App: text response
    App-->>User: render answer bubble
```

Current implementation uses **context injection** — data is gathered client-side and sent as context. Future upgrade to **tool-use pattern** where Claude decides which queries to run.

---

## SMS Pipeline

```mermaid
graph LR
    subgraph Android["Android"]
        SM["Telephony<br/>SMS Receiver"] -->|raw text| SP["SmsParser<br/>(regex engine)"]
        SP -->|match| TX[Transaction object]
        SP -->|no match| NULL["null (skip)"]
    end

    subgraph Parse["Regex Patterns"]
        P1["Pattern 1: ₹XX debited/credited to YY"]
        P2["Pattern 2: Rs.XX spent at YY"]
        P3["Pattern 3: Trf to YY ₹XX"]
        P4["Pattern 4: INR XX is debited from YY"]
    end

    SP --> P1
    SP --> P2
    SP --> P3
    SP --> P4

    TX --> TN["TransactionNotifier<br/>.add()"]
    TN --> SUP["Supabase INSERT"]

    TN --> TOAST["Toast: added"]
```

---

## Categorization Pipeline

```mermaid
flowchart LR
    TX["New Transaction<br/>(no category)"] --> RULES{"Match<br/>category_rules<br/>by priority?"}

    RULES -->|yes| ASSIGN["Assign category + tags"]
    RULES -->|no| CLAUDE["Send to Claude API<br/>for categorization"]

    CLAUDE --> CLAUDE_RESP{"Claude returned<br/>category?"}
    CLAUDE_RESP -->|yes| ASSIGN
    CLAUDE_RESP -->|no| MANUAL["Leave uncategorized<br/>User categorises manually"]

    ASSIGN --> UPDATE["TransactionNotifier.update()"]
    UPDATE --> DONE["Transaction categorised"]
```

---

## Key Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| State management | Riverpod (StateNotifier) | Simple, no codegen, testable |
| Navigation | IndexedStack + bottom nav | Preserves tab state, fast switching |
| Invoice access | End drawer via 5th nav item | No dedicated screen needed |
| Data sync | Supabase Realtime (PostgresChanges) | Sub-second cross-device, no polling |
| SMS integration | Stub + plugin | Real device needed, deferred |
| Agent approach | Context injection (v1) | Simpler than tool-use, ships faster |
| No auth | Single anon key | Personal tool, 2 devices max |
| Charts | fl_chart | Pie + line, battle-tested Flutter lib |
