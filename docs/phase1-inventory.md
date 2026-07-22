# Phase 1 — Protected Data & Interface Inventory

Produced as the Phase 1 deliverable "Inventory protected data and interfaces"
before any ownership/RLS migration (Phase 2). Derived from
`supabase/migrations/00001`–`00005` and the Flutter client. Every item below
needs an owner-scoping task in Phase 2.

## Owner-controlled tables

| Table | Soft-delete | Realtime | Notes for Phase 2 |
|---|---|---|---|
| `accounts` | `is_deleted` | yes | Seeded rows (SBI/Kotak/PayPal/Cash) must be backfilled to owner. |
| `transactions` | `is_deleted` | yes | Core ledger; FKs `account_id`, `linked_invoice_id`, `transfer_group_id`. |
| `transaction_labels` | — (join) | yes | PK `(transaction_id, label_id)`; cascade deletes. |
| `labels` | — | yes | Unique on `lower(name)` — must become `(user_id, lower(name))`. |
| `invoices` | `is_deleted` | yes | Referenced by `transactions.linked_invoice_id`. |
| `goals` | `is_deleted` | yes | `allocated_amount` mutated in place today (D6). |
| `recurring_expenses` | `is_deleted` | no | Agent context only; UI in Phase 9. |
| `recurring_income` | `is_deleted` | no | Agent context only; UI in Phase 9. |
| `category_rules` | — | no | Legacy rule engine; check references before label merge (Phase 5). |
| `monthly_snapshots` | — | no | Unique `(month, year)` — must become `(user_id, year, month)`. |
| `chat_sessions` | — | no | Agent history; migration 00003 explicitly notes no `user_id` yet. |

## Functions / triggers

- `fn_account_balance(uuid)` — SECURITY INVOKER (default), plpgsql. Derives one
  account balance from `direction` legs. Phase 2 must derive owner from
  `auth.uid()` and never accept a trusted `user_id`.
- `fn_net_worth()` — SECURITY INVOKER, sums `fn_account_balance` over
  non-deleted accounts. **Unbounded in time** — Phase 8 must add an as-of
  parameter for correct month-end snapshots (see D8/snapshot note).
- `update_updated_at()` — trigger fn; used by `set_transactions_updated_at`,
  `set_invoices_updated_at`, `set_chat_sessions_updated_at`.
- **No `SECURITY DEFINER` functions exist yet.** Every privileged RPC added in
  Phases 2–7 must set a fixed `search_path`, least-privilege grants, and derive
  the owner from `auth.uid()`.

## Policies (all open — the D5 hole)

`CREATE POLICY "anon_all" ON <t> FOR ALL USING (true)` exists on **every** table
above. Phase 2 removes each `anon_all` in the same release that adds the
owner-only replacement.

## Realtime publication `supabase_realtime`

Members: `transactions`, `goals`, `invoices`, `accounts`, `labels`,
`transaction_labels`. Phase 2 must re-verify non-owner subscribers receive no
rows.

## Keys that must gain `user_id`

- `monthly_snapshots` UNIQUE `(month, year)` → `(user_id, year, month)`.
- `labels` UNIQUE `lower(name)` → `(user_id, lower(name))`.
- `transactions.raw_sms_hash` partial index (dedupe) → owner-scoped.
- FKs to make owner-aware: `transactions.account_id`, `transactions.linked_invoice_id`,
  `transaction_labels.(transaction_id,label_id)`.

## Storage buckets

None. No attachment/storage objects exist; §2.4 storage task is a no-op until a
future attachment feature is approved.

## Client interfaces that expose/mutate owner data

Riverpod providers hitting Supabase directly (all under `lib/providers/` +
`lib/core/`): `transaction_provider`, `account_provider`, `goal_provider`,
`invoice_provider`, `label_provider`, `recurring_expense_provider`,
`recurring_income_provider`, plus `core/monthly_snapshot.dart` and the
browser-side `features/agent/llm_service.dart` (Gemini key exposure — D5,
Phase 3).

## Baseline load profile (pre-pagination, D4)

Client fetches the **entire** ledger with a single unbounded `SELECT` and
recomputes all Briefing/analytics in memory; every Realtime event triggers a
full reload. Phase 7 replaces this with 50-row cursor pages + aggregate RPCs.
Exact production query counts/payload sizes require live project access and are
recorded in the ops runbook (Phase 11.7), not source control.
