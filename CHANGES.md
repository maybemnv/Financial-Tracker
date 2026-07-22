# Changes — `Feat/prd-v2-security-correctness`

Working log for the PRD v2 security + correctness roadmap (`docs/TODO.md`).
13 commits ahead of `master`; 58 files changed, ~8,500 insertions.
Gate status: `flutter analyze` clean, `flutter test` 52 passing.

---

## 1. This session

**Phase 6 completed** (`2042d38`) — picked up from the schema-only commit and
finished 6.2–6.5.

- `supabase/migrations/00015_goal_editing_and_states.sql` — `update_goal`,
  `set_goal_status`, `delete_goal` as owner-scoped `SECURITY DEFINER` RPCs.
  Overfunding and target-below-allocated now require explicit confirmation
  (`p_allow_overfunding`, `p_allow_target_below_allocated`); safe-delete refuses
  any goal that has contribution history and points at Archive instead.
- **Defect found and fixed in `00014`:** auto-completion was one-way. A negative
  correction left a goal permanently flagged `completed` while underfunded. The
  trigger now demotes `completed → active` as well, and fires on `target_amount`
  changes. `completed` is trigger-owned and rejected as a manual status, so a
  goal can never claim completion it hasn't earned.
- `lib/core/goal_rules.dart` — the same rules as pure, Supabase-free logic:
  transitions, guards, Emergency-Fund pinning, and completion projection gated
  at ≥3 contributions across ≥2 distinct months (otherwise "not enough history"
  rather than a date extrapolated from one point).
- Savings board rebuilt: goal-detail view, edit dialog with target date,
  add-funds / correct / reallocate dialogs (each stating that allocation
  earmarks existing money and moves no account balance), pause / archive /
  restore, sized for 360 px.
- The goal provider now routes every write through the RPCs. The old
  non-atomic read-then-write `allocate()` is gone.
- Agent Desk `get_goals` gained status, target date, and gated contribution
  pace, and states the earmarking rule. Still no allocation-modifying tool.
- `supabase/tests/goal_allocation.sql` — DB-level invariants inside a
  rolled-back transaction. **Authored, not yet run** (needs a live database).

**Dashboard-applied migration scripts** (`f1d8bf4`) — `supabase/apply/`
concatenates the migrations into paste-ready SQL Editor scripts
(`00_preflight` → `01_owner_registry` → `02_phase2_to_phase6` → `03_verify`),
because applying via `psql` wasn't wanted. Five statements across `00009`,
`00012`, and `00014` were not re-runnable and would have errored on a second
pass; each now drops before creating, which is what makes a single concatenated
paste safe to retry.

**Auth removal — considered and rejected.** Removing auth was raised, on the
reasoning that there is only one user. That holds for *usage* but not for
*access*: this is a public Vercel deployment, and the Supabase anon key ships in
the JS bundle every visitor downloads, so "no auth" would mean the ledger is
readable and writable by anyone who finds the site. Decision: leave auth in
place. If the login step becomes annoying, the fix is a persistent session (sign
in once per browser), not open RLS.

---

## 2. Branch rundown

| Commit | Phase | Delivered |
|---|---|---|
| `b2a1216` | 1 | Repaired the test gate (D7 — `find.byDisplayValue` replaced with an `EditableText` predicate finder), boot/async tests, `docs/phase1-inventory.md`. |
| `7149e03` | 2 | `00006`–`00010`: owner registry, row ownership + backfill, `NOT NULL` + owner-scoped keys, owner-only RLS replacing `anon_all`, owner-scoped balance/net-worth functions. Flutter auth gate, sign-in screen, auth controller. |
| `8b511bf` | 3 | Agent Desk moved behind an authenticated Edge Function (`supabase/functions/agent/index.ts`, 515 lines). `llm_service.dart` shrank from ~950 lines to a thin client. Gemini key out of the browser bundle. |
| `dc4d67d` | 4 | `lib/core/finance_metrics.dart` — canonical PRD §4 metrics with `totalOutflow == personalSpend + familySupport` true by construction. `00011`: `account_id NOT NULL` (D1), identity-preserving `TRANSFER TO OTHER → FAMILY` (D2), `exclude_from_personal_spend` with a single-exclusion guard. Even-split attribution removed (D3). |
| `0e56049` | 5 | `00012`: primary-label column, label lifecycle states, `label_audit`, legacy backfill. |
| `0d331cc` | 5 | `00013`: `save_transaction_with_labels`, `rename_label`, `set_label_status`, `merge_labels`, `delete_label` — one audit entry per logical change. |
| `f30e8b8` | 6 | `00014`: goal status/target date, `goal_contributions`, atomic `contribute_to_goal` / `reallocate_goal_funds`, drift assertion. |
| `2042d38` | 6 | Goal editing, lifecycle states, allocation UI, agent context, tests. |
| `f1d8bf4` | — | `supabase/apply/` scripts + migration idempotency fixes. |

Four earlier commits (`9873a3f`, `58ae580`, `b63aba2`, `ffac624`, 17–19 Jul)
predate the roadmap work and are also not yet on `master`.

---

## 3. Where the work actually stands

The distinction that matters: **everything below is authored and gated, and
almost none of it is live.** No migration on this branch has been applied to the
production database, and the Edge Function has not been deployed. The running
app is still the pre-roadmap build.

| Area | Code | Live |
|---|---|---|
| Phase 1 — test gate, inventory | done | n/a |
| Phase 2 — auth + RLS | done | **not applied** |
| Phase 3 — Agent Edge Function | done | **not deployed** |
| Phase 4 — metrics, D1/D2/D3 | done | **not applied** |
| Phase 5 — schema + RPCs | done | **not applied** |
| Phase 5 — UI | **not started** | — |
| Phase 6 — goals | done | **not applied** |
| Phases 7–11 | not started | — |

---

## 4. What's left

### 4.1 The live-database sequence (blocks everything else)

Nothing on this branch is real until this runs. `supabase/apply/README.md` has
the procedure; the short version:

1. Back up (`docs/RUNBOOK.md` §1). These migrations are forward-only.
2. Provision the owner: enable auth providers, add redirect URLs, sign in once,
   copy the UUID (§2).
3. `00_preflight.sql` → fix any null-`account_id` transactions it lists.
4. `01_owner_registry.sql` → the owner `INSERT` → `02_phase2_to_phase6.sql`.
5. **Deploy this branch's client in the same window.** `00009` swaps `anon_all`
   for owner-only RLS; the currently deployed anon build stops reading data the
   moment it commits.
6. `supabase functions deploy agent` + set the `GEMINI_API_KEY` secret, then
   rotate the old key (RUNBOOK §4).
7. `03_verify.sql`, then the two behavioural suites via `psql`:
   `supabase/tests/rls_owner_scoping.sql`, `supabase/tests/goal_allocation.sql`.

### 4.2 Phase 5 UI — the largest code gap

The Phase 5 RPCs have **zero call sites in `lib/`**. The transaction form still
writes directly to the table, so `save_transaction_with_labels` and its
"exactly one primary label per expense" rule are bypassed entirely. Consequence
today: `Transaction.primaryLabel` falls back to the sole attached label, so
single-label expenses attribute correctly, but every multi-label expense lands
in `Needs primary label` and there is no way to resolve it.

Outstanding: 5.5 (primary picker + review queue), 5.11 (label management
screen), and routing form writes through the RPC. Phase 5 exit criteria cannot
be met without these.

### 4.3 Phases 7–11 (not started)

- **7 — Data and rendering performance.** Server-side pagination, provider
  replacement, incremental Realtime patching, owner-scoped aggregate RPCs,
  snapshot strategy, startup work. Fixes **D4**.
- **8 — Briefing slim-down + four-chart Analytics tab.** Monthly cash flow,
  spending by primary label, daily cumulative personal spend, net worth history.
- **9 — Upcoming obligations + deterministic cash-flow forecast.**
- **10 — Quick capture + merchant normalization.**
- **11 — Installed-PWA resume resilience, release, production acceptance.**
  Fixes **D8** (mobile Brave blank-screen on resume). Includes 11.7, the
  documentation sweep: `ARCHITECTURE.md`, `DATABASE.md`, `API.md`, `PRD.md`
  status, `README.md`, `.env.example`.

### 4.4 Defect ledger (PRD §1)

| | Defect | Status |
|---|---|---|
| D1 | Cash expenses on bank accounts | Code done; **historical reassignment is a live owner step** |
| D2 | `TRANSFER TO OTHER` conflation | Done |
| D3 | Even-split multi-label reports | Attribution fixed; **needs 4.2 to be resolvable in the UI** |
| D4 | Full-ledger loads, full Realtime reloads | Open — Phase 7 |
| D5 | `anon_all` RLS + browser Gemini key | Code done; **not applied/deployed** |
| D6 | Goal allocation without history | Done |
| D7 | Broken test gate | Done |
| D8 | Installed-PWA resume blank screen | Open — Phase 11 |

---

## 5. Suggested order from here

1. **Run the live-DB sequence (4.1).** Nine commits of security and correctness
   work are inert until it happens, and the risk of a stale branch grows.
2. **Close the Phase 5 UI gap (4.2).** It is the one place where authored
   backend guarantees are not reachable from the app.
3. **Then Phase 7**, which is the last item blocking the Analytics work in
   Phase 8.
