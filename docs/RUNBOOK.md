# Operations Runbook

Manual, credentialed procedures that live *outside* the app. Referenced by
`docs/TODO.md` Phases 1, 2, and 11.7. Nothing here runs automatically; each step
is executed by the owner against the live Supabase project during a maintenance
window.

> **Secrets never go in this file or in git.** Record the production owner UUID,
> project ref, and callback URLs in your password manager.

---

## 1. Backup & restore (Phase 1)

Run immediately before any migration in Phases 2+.

```bash
# Schema + data dump of the production project.
supabase db dump --db-url "$PROD_DB_URL" -f backup_$(date +%F).sql --data-only=false

# Verify the restore into a disposable project before trusting the backup.
supabase db reset --db-url "$STAGING_DB_URL"
psql "$STAGING_DB_URL" -f backup_YYYY-MM-DD.sql

# Spot-check representative row counts match production:
psql "$STAGING_DB_URL" -c "SELECT
  (SELECT count(*) FROM transactions)        AS txns,
  (SELECT count(*) FROM accounts)            AS accts,
  (SELECT count(*) FROM labels)              AS labels,
  (SELECT count(*) FROM transaction_labels)  AS txn_labels,
  (SELECT count(*) FROM invoices)            AS invoices,
  (SELECT count(*) FROM goals)               AS goals,
  (SELECT count(*) FROM monthly_snapshots)   AS snapshots;"
```

Keep the verified backup until the secure release + snapshot-rebuild behaviour
has been stable for at least seven days (Phase 11.10).

**Rollback stance:** migrations are *forward-only*. Do not plan a destructive
rollback that drops populated ownership or primary-label columns. If a migration
misbehaves, restore the pre-migration backup into a fresh project and re-point
the client, or write a new corrective forward migration.

---

## 2. Owner provisioning (Phase 2.1–2.2)

1. Enable **Google OAuth** and **email magic link** providers in Supabase Auth.
2. Add callback/redirect URLs (allowlist only these):
   - `http://localhost:PORT` (local dev)
   - the Vercel preview origin(s) you actually use
   - the production origin
3. Sign in once as the owner (Google or magic link) to create the `auth.users`
   row. Copy that user's UUID.
4. Apply `00006_owner_registry.sql`, then insert the owner:
   ```sql
   INSERT INTO app_owner (user_id, note)
   VALUES ('<owner-uuid>', 'production owner');
   SELECT app_is_owner();  -- must return true while signed in as the owner
   ```
5. **Disable public sign-up** once the owner login is proven usable.

---

## 3. Migration apply order (Phase 2.3–2.5)

Apply in numeric order **after** step 2 has inserted the owner row:

| File | Effect | Guard |
|---|---|---|
| `00006_owner_registry.sql` | `app_owner`, `app_is_owner()`, single-owner trigger | — |
| `00007_row_ownership.sql` | nullable `user_id` + backfill + indexes | raises if no active owner |
| `00008_owner_constraints.sql` | `NOT NULL`, owner-scoped keys, ownership triggers | needs zero-null rows |
| `00009_owner_policies.sql` | drop `anon_all`, add owner-only RLS | deploy client same window |
| `00010_scope_functions.sql` | owner-scope balance/net-worth fns | `authenticated` grant only |

**Verification between 00007 and 00008** — every count must be 0:

```sql
SELECT 'accounts' t, count(*) c FROM accounts WHERE user_id IS NULL
UNION ALL SELECT 'transactions', count(*) FROM transactions WHERE user_id IS NULL
UNION ALL SELECT 'transaction_labels', count(*) FROM transaction_labels WHERE user_id IS NULL
UNION ALL SELECT 'labels', count(*) FROM labels WHERE user_id IS NULL
UNION ALL SELECT 'invoices', count(*) FROM invoices WHERE user_id IS NULL
UNION ALL SELECT 'goals', count(*) FROM goals WHERE user_id IS NULL
UNION ALL SELECT 'recurring_expenses', count(*) FROM recurring_expenses WHERE user_id IS NULL
UNION ALL SELECT 'recurring_income', count(*) FROM recurring_income WHERE user_id IS NULL
UNION ALL SELECT 'category_rules', count(*) FROM category_rules WHERE user_id IS NULL
UNION ALL SELECT 'monthly_snapshots', count(*) FROM monthly_snapshots WHERE user_id IS NULL
UNION ALL SELECT 'chat_sessions', count(*) FROM chat_sessions WHERE user_id IS NULL;
```

**After 00009** — run `supabase/tests/rls_owner_scoping.sql` (see Phase 2.7) to
prove anon/non-owner access fails closed.

**Deploy the auth-capable Flutter client in the same window** as 00009. Never
leave an anon client pointed at owner-only RLS, and never leave owner-only RLS
un-deployed behind an anon client.

### Later migrations (Phases 4–6)

| File | Effect | Guard |
|---|---|---|
| `00011_family_and_account_integrity.sql` | `account_id NOT NULL`, `FAMILY` rename, exclusion flag | raises if any row lacks an account |
| `00012_primary_labels_and_lifecycle.sql` | primary-label column + label lifecycle | — |
| `00013_label_and_transaction_rpcs.sql` | atomic transaction save + label lifecycle RPCs | `authenticated` grant only |
| `00014_goal_contributions.sql` | goal status/target date, contribution history, atomic allocation | seeds one opening contribution per goal |
| `00015_goal_editing_and_states.sql` | goal edit/status/delete RPCs, overfund + safe-delete guards | replaces the 00014 RPC signatures |

**After 00015** — run `supabase/tests/goal_allocation.sql` (Phase 6.5). It runs
inside a rolled-back transaction and proves allocation stays reconciled, never
goes negative, conserves totals across a reallocation, leaves net worth
untouched, and refuses to delete a goal that has history.

Note that `00015` drops and recreates `contribute_to_goal` and
`reallocate_goal_funds` with an added `p_allow_overfunding` argument, so deploy
the matching client — the old 3-arg/4-arg signatures no longer exist.

---

## 4. Gemini key rotation (Phase 3.3)

After the Edge Function path is live:
```bash
supabase secrets set GEMINI_API_KEY=<new-key>
```
Then revoke the old key in Google AI Studio and remove `GEMINI_API_KEY` from
Vercel env, `.env`, and `vercel-build.sh` (already done in the Phase 3 client).

---

## 5. Snapshot rebuild (Phase 7.5 / 8.6)

When historical transactions are corrected (e.g. Phase 4 account reassignments),
recompute the affected month's snapshot as-of month end:
```sql
-- see fn_net_worth_asof() once 00020 lands; delete + rebuild the stale row.
DELETE FROM monthly_snapshots WHERE user_id = auth.uid() AND year = $1 AND month = $2;
```

---

## 6. Cache recovery (Phase 11.6)

On release, clear obsolete service-worker caches so the installed PWA receives
the new build (bump the cache-buster query in `vercel.json`/bootstrap). Confirm
via the browser Application panel that the new version is served.
