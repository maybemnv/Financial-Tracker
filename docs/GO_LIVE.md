# Go-live guide — Supabase + infra

Everything you must change outside the codebase to run this branch for real,
in order. Written for the Supabase dashboard (SQL Editor), not `psql`.

Companion docs: `supabase/apply/README.md` (the scripts), `docs/RUNBOOK.md`
(backup, key rotation), `CHANGES.md` (what the branch contains).

---

## Step 0 — Fix the "Access denied" you are seeing right now

**Symptom:** you signed in with the magic link and got *"This account is signed
in but is not the registered owner of this finance desk."*

**Cause:** that screen is the app's `authenticatedNonOwner` state. It means
`app_is_owner()` ran and returned **false**. You applied `01_owner_registry.sql`,
which creates the `app_owner` table and the function — but the table is still
empty, and the function is written to fail closed:

```sql
SELECT EXISTS (SELECT 1 FROM app_owner WHERE user_id = auth.uid() AND is_active);
```

The `INSERT` is deliberately not part of the script: it needs your `auth.users`
UUID, which only exists once you have signed in — which you now have. So this is
the expected state at this point, not a misconfiguration.

**Fix.** In the Supabase SQL Editor:

```sql
-- 1. Find your UUID (the account you just signed in with).
SELECT id, email, created_at
FROM auth.users
ORDER BY created_at DESC;
```

Copy the `id` of the row whose `email` is the one you used, then:

```sql
-- 2. Register it as the owner.
INSERT INTO app_owner (user_id, note)
VALUES ('<paste-uuid-here>', 'production owner');

-- 3. Confirm exactly one active owner.
SELECT user_id, note, is_active FROM app_owner WHERE is_active;
```

Then in the running app: **Sign out and sign in again**, or press **Retry**.
The owner check is cached in the controller's state, so it will not re-run on
its own.

> **Get the UUID right.** Step 4 backfills every existing row to whoever is in
> `app_owner`. Registering the wrong account means your entire financial history
> is assigned to it, and fixing that afterwards is a manual data repair.

If you pick the wrong one before applying `02`, correct it with:

```sql
UPDATE app_owner SET is_active = false;             -- retire the wrong row
INSERT INTO app_owner (user_id, note) VALUES ('<right-uuid>', 'production owner');
```

---

## Step 1 — Supabase Auth configuration

**Dashboard → Authentication → Providers**

- Enable **Email** (magic link). Turn *Confirm email* on.
- Enable **Google** if you want the OAuth button; otherwise the magic link is
  enough and the button will simply fail.

**Dashboard → Authentication → URL Configuration**

- **Site URL** — your production origin, e.g. `https://your-app.vercel.app`.
  This is the fallback target when a redirect is not allowlisted.
- **Redirect URLs** — add every origin you will actually sign in from:
  ```
  http://localhost:5000
  https://your-app.vercel.app
  https://<your-vercel-preview>.vercel.app
  ```

> **Pin your local port.** `flutter run -d chrome` picks a random port each run,
> and the app redirects to `Uri.base.origin`. An unlisted port silently falls
> back to Site URL, which sends you to production instead of localhost. Always
> run local dev as:
> ```bash
> flutter run -d chrome --web-port=5000
> ```

---

## Step 2 — Back up

Not optional. Every migration from here is forward-only; there is no scripted
rollback. `docs/RUNBOOK.md` §1 has the full procedure.

Dashboard → **Database → Backups** and take a manual backup, or:

```bash
supabase db dump --db-url "$PROD_DB_URL" -f backup_$(date +%F).sql
```

Keep it until the release has been stable for a week.

---

## Step 3 — Preflight

Run `supabase/apply/00_preflight.sql`. Read-only; changes nothing.

The one thing that will abort the next step is **transactions with a null
`account_id`**. Migration `00011` enforces `account_id NOT NULL` and refuses to
guess an account. If the preflight lists any rows, open each in the app and
assign the correct account through the normal edit flow (which records an audit
entry) before continuing.

---

## Step 4 — Apply the main migration set

Run `supabase/apply/02_phase2_to_phase6.sql`. This is migrations `00007`–`00016`:
ownership + backfill, owner-only RLS, scoped functions, account/Family-support
integrity, primary labels, the transaction and label RPCs, and the goals
redesign.

The SQL Editor runs it as one transaction, so a failure rolls everything back
and leaves the database untouched. It stops deliberately if the owner row is
missing (Step 0) or if null-account rows remain (Step 3).

> ### This is the breaking moment
> `00009` drops the permissive `anon_all` policies and replaces them with
> owner-only RLS. **Any deployed build that is not this branch stops reading
> data the instant this commits** — it has no auth gate and its anon requests
> now return nothing. Do Step 6 in the same sitting.

---

## Step 5 — Deploy the Agent Edge Function

The Gemini key no longer ships in the browser bundle; the function holds it.

```bash
supabase login
supabase link --project-ref <your-project-ref>

# The model key, server-side only.
supabase secrets set GEMINI_API_KEY=<your-gemini-key>

# Origins allowed to call the function (comma-separated, no spaces).
supabase secrets set ALLOWED_ORIGINS=https://your-app.vercel.app,http://localhost:5000

supabase functions deploy agent
```

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are injected automatically — do not set
them yourself.

The function requires a valid owner JWT and calls `app_is_owner()` itself, so
Step 0 must be done or every Agent Desk request returns `not_owner`.

---

## Step 6 — Deploy the client

**Vercel → Settings → Environment Variables**, confirm:

| Variable | Value |
|---|---|
| `SUPABASE_URL` | your project URL |
| `SUPABASE_ANON_KEY` | the anon (publishable) key |

**Delete `GEMINI_API_KEY` from Vercel** if it is still there. It is no longer
read at build time (`vercel-build.sh` explicitly does not write it into `.env`),
and leaving it set keeps a secret in your build environment for no reason.

Then deploy this branch — merge PR #8 to `master`, or point the Vercel project
at `feat/prd-v2-security-correctness`. Confirm the deployed build shows the
sign-in screen; if it loads straight into the dashboard, you are still serving
the old anon bundle.

---

## Step 7 — Verify

Run `supabase/apply/03_verify.sql`. Every row must read `OK`:
single active owner, no unowned rows, no `anon_all` policies left, all 12
expected functions present, no goal-allocation drift, goal history seeded, and
the single-exclusion Family-support invariant intact.

Then the behavioural suites. These need `psql` — they switch roles and use
`\set`, which the dashboard editor cannot do:

```bash
psql "$DB_URL" -f supabase/tests/rls_owner_scoping.sql   # anon/non-owner fail closed
psql "$DB_URL" -f supabase/tests/goal_allocation.sql     # allocation invariants
```

Both run inside rolled-back transactions and leave no data behind.

Finally, in the app: sign in, confirm the ledger loads, add a labelled expense
(you should now be asked which label it *counts under*), allocate to a goal and
confirm no account balance moves, and ask the Agent Desk a question.

---

## Step 8 — Lock it down

1. **Disable public sign-up.** Authentication → Providers → uncheck *Allow new
   users to sign up*. Without this, anyone can create an account. They would hit
   "Access denied" and see no data, but there is no reason to allow it.
2. **Rotate the Gemini key.** The old one shipped in the browser bundle
   historically, so treat it as public. Create a new key in Google AI Studio,
   `supabase secrets set GEMINI_API_KEY=<new-key>`, then revoke the old one.
3. **Reassign the D1 rows.** `supabase/reports/misassigned_cash_review.sql`
   lists cash expenses recorded against bank accounts. Fix them through the
   app's edit flow so each correction is audited.

---

## Troubleshooting

| What you see | Cause | Fix |
|---|---|---|
| "Access denied — not the registered owner" | `app_is_owner()` returned false | Step 0. Insert the `app_owner` row, then sign out and back in. |
| "Sign-in problem" with a Postgres message | `app_is_owner()` errored | Usually `01` was not applied. Re-run it. |
| Magic link opens production instead of localhost | Redirect URL not allowlisted | Step 1. Pin `--web-port=5000` and add that origin. |
| Signed in, but every screen is empty after Step 4 | Session predates the migration, or rows are unowned | Sign out and in to get a fresh JWT; then run `03_verify.sql` §2. |
| Deployed app broke right after Step 4 | Old anon bundle against owner-only RLS | Step 6. Deploy this branch. |
| Agent Desk returns `not_owner` | Function has no owner row to match | Step 0. |
| Agent Desk returns `server_misconfigured` | `GEMINI_API_KEY` secret not set | Step 5. |
| Saving an expense says "choose which label this expense counts under" | Working as intended | Pick the label the amount attributes to. Multi-label expenses never split. |

### Full reset while testing

Before you have real data worth keeping, the fastest way out of a bad owner
assignment:

```sql
-- Wipe ownership assignment only; keeps all financial rows.
UPDATE app_owner SET is_active = false;
INSERT INTO app_owner (user_id, note) VALUES ('<correct-uuid>', 'production owner');
UPDATE accounts SET user_id = '<correct-uuid>';
UPDATE transactions SET user_id = '<correct-uuid>';
UPDATE transaction_labels SET user_id = '<correct-uuid>';
UPDATE labels SET user_id = '<correct-uuid>';
UPDATE invoices SET user_id = '<correct-uuid>';
UPDATE goals SET user_id = '<correct-uuid>';
UPDATE goal_contributions SET user_id = '<correct-uuid>';
UPDATE recurring_expenses SET user_id = '<correct-uuid>';
UPDATE recurring_income SET user_id = '<correct-uuid>';
UPDATE category_rules SET user_id = '<correct-uuid>';
UPDATE monthly_snapshots SET user_id = '<correct-uuid>';
UPDATE chat_sessions SET user_id = '<correct-uuid>';
```

Run this as the `postgres` role in the SQL Editor — the ownership triggers block
reassignment from a client role by design.
