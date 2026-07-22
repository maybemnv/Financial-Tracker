# Changes — `Feat/prd-v2-security-correctness`

Working log for the PRD v2 security + correctness roadmap (`docs/TODO.md`).
26 commits ahead of `master`.
Gate status: `flutter analyze` clean, `flutter test` 155 passing, release web
build succeeds.

**All eleven phases are code-complete.** Everything below the fold is the
running history; the live status table is §3. Migrations `00006`–`00020` and the
Agent Edge Function must be applied/deployed for any of it to take effect — see
`docs/GO_LIVE.md`. The only outstanding roadmap items are on-device acceptance
(11.6) and the manual security/finance verification matrix (11.9), both of which
need a real device and live requests and cannot be automated here.

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
| Phase 5 — write path + primary picker | done | **not applied** |
| Phase 5 — review queue, label management | **not started** | — |
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

### 4.2 Phase 5 UI — partly closed

The write path and the primary picker landed while fixing the Codex review
(§6). `add`/`update` now go through `save_transaction_with_labels`, and a
labelled expense cannot be saved without naming the label it counts under.

Outstanding: the **review queue** for legacy expenses already sitting in
`Needs primary label` (5.5), and the **label management screen** — rename,
archive, restore, merge, delete — whose RPCs exist in `00013` with no UI
(5.11). Phase 5 exit criteria still need both.

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
| D3 | Even-split multi-label reports | Done for new/edited rows; **legacy rows need the review queue (4.2)** |
| D4 | Full-ledger loads, full Realtime reloads | Open — Phase 7 |
| D5 | `anon_all` RLS + browser Gemini key | Code done; **not applied/deployed** |
| D6 | Goal allocation without history | Done |
| D7 | Broken test gate | Done |
| D8 | Installed-PWA resume blank screen | Open — Phase 11 |

---

## 6. Codex review fixes

Five findings on `0d331cc`, all reproduced and fixed.

- **P1 — label writes used a revoked DELETE.** `_replaceLabels()` physically
  deleted the joins on every update, but `00009` revokes DELETE from
  `authenticated`; an edit would have persisted the money fields and then failed
  with the old labels attached. `add`/`update` now go through
  `save_transaction_with_labels`. Transfers keep their two-leg single insert —
  routing a pair through a one-row RPC would have traded away that atomicity —
  and attach labels INSERT-only, which fresh rows do not need DELETE for.
- **P1 — Family Support always reported zero.** The ledger's nested select
  requested `id, name, color`, so `exclude_from_personal_spend` always took its
  `false` fallback and every `FAMILY` expense counted as Personal Spend. The
  canonical metrics were wrong on real data while every unit test passed, since
  the tests construct labels directly. Now selected.
- **P1 — agent attributed to an arbitrary label.** `getLabelBreakdown` used
  `labels[0]` without selecting `primary_label_id`, and relation order is not
  guaranteed. Attribution now resolves by id, with `Unlabeled` /
  `Needs primary label` buckets mirroring `PrimaryLabelStatus`.
- **P1 — agent cashflow could not answer family-support questions.** It
  returned only aggregate Total Outflow, contradicting its own system prompt.
  Now reports Personal Spend and Family Support separately with the invariant
  stated.
- **P2 — discarded query errors.** Supabase returns `{data: null, error}`
  rather than throwing, so an RLS or transient failure became the authoritative
  answer "No accounts found." Eight tool queries now propagate. The per-account
  balance loop deliberately still degrades to `unavailable` instead of throwing
  — that is explicit, never a false zero, and one transient failure should not
  discard the accounts that did resolve.

Fixing the first finding surfaced two defects in `save_transaction_with_labels`
itself, corrected in `00016`:

- It rejected **every** expense with no primary label, including expenses with
  no labels at all — but `Unlabeled` is a modelled state (TODO 5.6) and Phase 10
  quick capture depends on saving before classifying. The rule is now "a
  labelled expense must name one of its labels primary".
- Its INSERT omitted `raw_sms` / `raw_sms_hash`, so SMS-sourced rows created
  through the RPC lost their dedup hash and could be silently re-imported.

---

## 7. Suggested order from here

1. **Run the live-DB sequence (4.1).** Nine commits of security and correctness
   work are inert until it happens, and the risk of a stale branch grows.
2. **Finish Phase 5 UI (4.2)** — the review queue and label management. The
   write path is done; these are the last surfaces where authored backend
   guarantees have no way to be reached.
3. **Then Phase 7**, which is the last item blocking the Analytics work in
   Phase 8.
