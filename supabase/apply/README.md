# Paste-ready SQL for the Supabase SQL Editor

The files in `supabase/migrations/` are the source of truth. These are the same
statements concatenated in order, with headers, so the whole Phase 2–6 upgrade
can be applied by pasting into the dashboard SQL Editor instead of running
`psql`. Regenerate them from the migrations if you change one.

Run in this order:

| # | File | What it does |
|---|---|---|
| 0 | `00_preflight.sql` | Read-only. Shows the one data condition that will stop part 2. |
| 1 | `01_owner_registry.sql` | Migration `00006`, then you insert your owner UUID by hand. |
| 2 | `02_phase2_to_phase6.sql` | Migrations `00007`–`00016`. |
| 3 | `03_verify.sql` | Read-only. Every row must read `OK`. |

## Before you start

1. **Back up.** `docs/RUNBOOK.md` §1. These migrations are forward-only — there
   is no scripted rollback. If one misbehaves, restore the backup into a fresh
   project or write a corrective forward migration.
2. **Provision the owner.** `docs/RUNBOOK.md` §2: enable the auth providers, add
   the redirect URLs, sign in once to create your `auth.users` row, and copy
   that UUID. Part 1 needs it.
3. **Have the new client ready to deploy.** Migration `00009` (inside part 2)
   replaces the permissive anon policies with owner-only RLS. The currently
   deployed anon client stops reading data the moment it commits, so ship the
   auth-capable build from this branch in the same window.

## Notes

- The SQL Editor runs each script as a single transaction, so a failure rolls
  back cleanly and leaves the database untouched.
- Part 2 stops deliberately in two cases: no active `app_owner` row, and
  transactions with a null `account_id` (migration `00011` will not guess an
  account for them). `00_preflight.sql` shows you the second one in advance.
- Every script is safe to re-run; re-running is a no-op on parts already
  applied.
- `02_phase2_to_phase6.sql` recreates `contribute_to_goal` and
  `reallocate_goal_funds` with an added `p_allow_overfunding` argument, so the
  client must match. Deploy this branch, not an older build.

## Deeper verification

`03_verify.sql` checks state. The behavioural tests write and roll back, and
need `psql` because they use `\set` and switch roles:

```bash
psql "$DB_URL" -f supabase/tests/rls_owner_scoping.sql   # anon/non-owner fail closed
psql "$DB_URL" -f supabase/tests/goal_allocation.sql     # allocation invariants
```
