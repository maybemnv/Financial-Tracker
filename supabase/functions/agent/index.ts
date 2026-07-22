// ============================================================================
// Agent Desk Edge Function (Phase 3)
//
// All Gemini traffic lives here — the browser never sees GEMINI_API_KEY. The
// caller must present a valid Supabase JWT belonging to the registered owner
// (app_is_owner()). Tools run owner-scoped DB reads under the caller's JWT, so
// RLS (Phase 2) is the backstop. No tool can create, modify, or move money.
//
// Deploy: supabase functions deploy agent
// Secret : supabase secrets set GEMINI_API_KEY=<key>
// ============================================================================
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";
const MODEL = "gemini-2.5-flash";
const MAX_TOOL_ROUNDS = 10;
const MAX_MESSAGES = 60;
const MAX_BODY_BYTES = 128 * 1024;

// Origins allowed to call the function. Extend via ALLOWED_ORIGINS (comma list).
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

function corsHeaders(origin: string | null): Record<string, string> {
  const allow =
    origin && (ALLOWED_ORIGINS.length === 0 || ALLOWED_ORIGINS.includes(origin))
      ? origin
      : ALLOWED_ORIGINS[0] ?? "*";
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

const SYSTEM_PROMPT = `You are the read-only finance assistant for a single owner.
You may read, classify, summarize, and forecast. You must NEVER create, modify,
delete, allocate, or move money. Prefer the provided tools over guessing. Report
Income, Total Outflow, Personal Spend, and Family Support distinctly, and never
present "Personal Savings After Own Spend" as money kept.`;

interface ToolActivity {
  name: string;
  ok: boolean;
}

function jsonResponse(
  body: unknown,
  status: number,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
  });
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  const correlationId = crypto.randomUUID();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(origin) });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed", correlationId }, 405, origin);
  }

  // --- Auth: require an owner JWT -------------------------------------------
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "missing_token", correlationId }, 401, origin);
  }

  const supabase: SupabaseClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  try {
    const { data: isOwner, error: ownerErr } = await supabase.rpc("app_is_owner");
    if (ownerErr || isOwner !== true) {
      return jsonResponse({ error: "not_owner", correlationId }, 403, origin);
    }
  } catch (_e) {
    return jsonResponse({ error: "auth_check_failed", correlationId }, 403, origin);
  }

  // --- Validate request body ------------------------------------------------
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) {
    return jsonResponse({ error: "payload_too_large", correlationId }, 413, origin);
  }
  let parsed: { messages?: unknown };
  try {
    parsed = JSON.parse(raw);
  } catch (_e) {
    return jsonResponse({ error: "invalid_json", correlationId }, 400, origin);
  }
  const messages = sanitizeMessages(parsed.messages);
  if (messages.length === 0) {
    return jsonResponse({ error: "no_messages", correlationId }, 400, origin);
  }

  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiKey) {
    return jsonResponse({ error: "server_misconfigured", correlationId }, 500, origin);
  }

  // Prepend the system prompt if the client did not.
  const convo: Msg[] = messages[0]?.role === "system"
    ? messages
    : [{ role: "system", content: SYSTEM_PROMPT }, ...messages];

  const toolActivity: ToolActivity[] = [];

  try {
    for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
      const res = await callGemini(convo, geminiKey);
      if (!res.ok) {
        return jsonResponse(
          { error: "model_error", status: res.status, correlationId },
          502,
          origin,
        );
      }
      const data = await res.json();
      const choice = data?.choices?.[0]?.message;
      if (!choice) {
        return jsonResponse({ error: "no_choices", correlationId }, 502, origin);
      }

      const toolCalls = choice.tool_calls ?? [];
      const text = extractText(choice.content);

      if (toolCalls.length > 0) {
        convo.push({ role: "assistant", content: text, tool_calls: toolCalls });
        for (const call of toolCalls) {
          const name = call?.function?.name ?? "";
          const args = decodeArgs(call?.function?.arguments);
          let result: string;
          let ok = true;
          try {
            result = await executeTool(supabase, name, args);
          } catch (e) {
            ok = false;
            result = `Error executing ${name}`;
            console.error(correlationId, "tool_error", name, String(e));
          }
          toolActivity.push({ name, ok });
          convo.push({ role: "tool", tool_call_id: call.id, content: result });
        }
        continue;
      }

      if (text) {
        return jsonResponse({ answer: text, toolActivity, correlationId }, 200, origin);
      }
      return jsonResponse(
        { answer: "I could not complete that request. Please rephrase.", toolActivity, correlationId },
        200,
        origin,
      );
    }
    return jsonResponse(
      { answer: "That needed too many steps. Please narrow the question.", toolActivity, correlationId },
      200,
      origin,
    );
  } catch (e) {
    console.error(correlationId, "unhandled", String(e));
    return jsonResponse({ error: "internal_error", correlationId }, 500, origin);
  }
});

// ---------------------------------------------------------------------------
// Gemini
// ---------------------------------------------------------------------------
type Msg = Record<string, unknown> & { role: string; content?: unknown };

async function callGemini(messages: Msg[], key: string): Promise<Response> {
  const body = {
    model: MODEL,
    max_tokens: 2048,
    temperature: 0.2,
    messages,
    tools: TOOLS,
    tool_choice: "auto",
  };
  let last: Response | null = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const res = await fetch(GEMINI_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${key}`,
        },
        body: JSON.stringify(body),
      });
      if (res.status !== 429 && res.status < 500) return res;
      last = res;
    } catch (_e) {
      // retry
    }
    if (attempt < 2) await new Promise((r) => setTimeout(r, 400 * (attempt + 1)));
  }
  return last ?? new Response("gemini_failed", { status: 502 });
}

// ---------------------------------------------------------------------------
// Message / arg sanitation — treat all model + client input as untrusted
// ---------------------------------------------------------------------------
function sanitizeMessages(input: unknown): Msg[] {
  if (!Array.isArray(input)) return [];
  const out: Msg[] = [];
  for (const item of input.slice(-MAX_MESSAGES)) {
    if (typeof item !== "object" || item === null) continue;
    const role = (item as Record<string, unknown>).role;
    if (role !== "user" && role !== "assistant" && role !== "tool" && role !== "system") {
      continue;
    }
    out.push(item as Msg);
  }
  return out;
}

function decodeArgs(raw: unknown): Record<string, unknown> {
  if (typeof raw !== "string" || raw.trim() === "") return {};
  try {
    const v = JSON.parse(raw);
    return typeof v === "object" && v !== null ? v as Record<string, unknown> : {};
  } catch (_e) {
    return {};
  }
}

function extractText(content: unknown): string {
  if (typeof content === "string") return content.trim();
  if (Array.isArray(content)) {
    return content
      .filter((b) => typeof b === "object" && b !== null)
      .map((b) => (b as Record<string, unknown>).text)
      .filter((t) => typeof t === "string")
      .join("\n")
      .trim();
  }
  return "";
}

function boundedInt(v: unknown, def: number, min: number, max: number): number {
  const n = typeof v === "number" ? Math.trunc(v) : def;
  return Math.max(min, Math.min(max, isFinite(n) ? n : def));
}

// ---------------------------------------------------------------------------
// Tools (read-only). Semantics for label breakdown / cashflow are refined to
// canonical metrics as Phases 4–5 columns (primary_label_id,
// exclude_from_personal_spend) land; today they mirror the existing client.
// ---------------------------------------------------------------------------
const TOOLS = [
  fn("get_accounts", "List accounts with derived balances.", {}),
  fn("get_net_worth", "Total net worth across accounts.", {}),
  fn("get_transactions", "Query transactions with optional filters.", {
    type: { type: "string", enum: ["debit", "credit", "transfer", "investment"] },
    label: { type: "string" },
    days: { type: "number" },
    account_id: { type: "string" },
    limit: { type: "number" },
  }),
  fn("get_label_breakdown", "Spending by label for a period.", {
    days: { type: "number" },
  }),
  fn("get_cashflow_summary", "Income, spending, investments, savings.", {
    month: { type: "number" },
    year: { type: "number" },
    days: { type: "number" },
  }),
  fn("get_goals", "List goals with target, allocated, percent funded.", {}),
  fn("get_invoices", "Freelance invoice summary.", {}),
  fn("get_recurring_expenses", "Recurring expenses and monthly total.", {}),
  fn("get_recurring_income", "Expected recurring income.", {}),
  fn("get_monthly_snapshots", "Monthly history from snapshots.", {
    months: { type: "number" },
  }),
];

function fn(name: string, description: string, properties: Record<string, unknown>) {
  return {
    type: "function",
    function: { name, description, parameters: { type: "object", properties } },
  };
}

async function executeTool(
  db: SupabaseClient,
  name: string,
  args: Record<string, unknown>,
): Promise<string> {
  switch (name) {
    case "get_accounts":
      return getAccounts(db);
    case "get_net_worth": {
      const { data } = await db.rpc("fn_net_worth");
      return `Net worth: ${data ?? 0}`;
    }
    case "get_transactions":
      return getTransactions(db, args);
    case "get_label_breakdown":
      return getLabelBreakdown(db, args);
    case "get_cashflow_summary":
      return getCashflow(db, args);
    case "get_goals":
      return getGoals(db);
    case "get_invoices":
      return getInvoices(db);
    case "get_recurring_expenses":
      return getRecurring(db, "recurring_expenses");
    case "get_recurring_income":
      return getRecurring(db, "recurring_income");
    case "get_monthly_snapshots":
      return getSnapshots(db, args);
    default:
      return `Unknown tool: ${name}`;
  }
}

async function getAccounts(db: SupabaseClient): Promise<string> {
  const { data } = await db.from("accounts").select("id, name, type").eq("is_deleted", false);
  const rows = (data ?? []) as Array<Record<string, unknown>>;
  if (rows.length === 0) return "No accounts found.";
  const lines: string[] = [];
  for (const a of rows) {
    const { data: bal } = await db.rpc("fn_account_balance", { p_account_id: a.id });
    lines.push(`${a.name} (${a.type}): ${bal ?? "unavailable"}`);
  }
  return lines.join("\n");
}

function effectiveDate(row: Record<string, unknown>): Date | null {
  const t = (row.transacted_at as string) || (row.created_at as string);
  return t ? new Date(t) : null;
}

function labelNames(row: Record<string, unknown>): string[] {
  const rel = row.transaction_labels;
  if (!Array.isArray(rel)) return [];
  return rel
    .map((r) => (r as Record<string, unknown>)?.label)
    .map((l) => (l as Record<string, unknown>)?.name)
    .filter((n): n is string => typeof n === "string");
}

async function getTransactions(db: SupabaseClient, args: Record<string, unknown>): Promise<string> {
  const limit = boundedInt(args.limit, 50, 1, 200);
  const days = args.days != null ? boundedInt(args.days, 30, 1, 3650) : null;
  const since = days != null ? new Date(Date.now() - days * 864e5) : null;
  const label = typeof args.label === "string" ? args.label : null;
  const rel = label
    ? "transaction_labels!inner(label:labels!inner(name))"
    : "transaction_labels(label:labels(name))";
  let q = db
    .from("transactions")
    .select(`amount, type, direction, merchant, vpa, account_id, created_at, transacted_at, note, ${rel}`)
    .eq("is_deleted", false);
  if (typeof args.type === "string") q = q.eq("type", args.type);
  if (typeof args.account_id === "string") q = q.eq("account_id", args.account_id);
  if (label) q = q.eq("transaction_labels.labels.name", label);
  const { data } = await q.order("created_at", { ascending: false }).limit(days ? 200 : limit);
  const rows = ((data ?? []) as Array<Record<string, unknown>>)
    .filter((r) => !since || (effectiveDate(r)?.getTime() ?? 0) >= since.getTime());
  if (rows.length === 0) return "No transactions match those filters.";
  return rows.slice(0, limit).map((r) => {
    const inflow = (r.direction ?? (r.type === "credit" ? "inflow" : "outflow")) === "inflow";
    const d = effectiveDate(r)?.toISOString().split("T")[0] ?? "unknown-date";
    const merch = r.merchant ?? r.note ?? r.vpa ?? "unknown";
    const labels = labelNames(r);
    return `${d} | ${inflow ? "+" : "-"}${r.amount} | ${labels.length ? labels.join(", ") : "Unlabeled"} | ${merch}`;
  }).join("\n");
}

async function getLabelBreakdown(db: SupabaseClient, args: Record<string, unknown>): Promise<string> {
  const days = boundedInt(args.days, 30, 1, 3650);
  const since = new Date(Date.now() - days * 864e5);
  const { data } = await db
    .from("transactions")
    .select("amount, created_at, transacted_at, transaction_labels(label:labels(name))")
    .eq("type", "debit").eq("is_deleted", false)
    .order("created_at", { ascending: false }).limit(200);
  const buckets = new Map<string, number>();
  let total = 0;
  for (const r of ((data ?? []) as Array<Record<string, unknown>>)) {
    const d = effectiveDate(r);
    if (!d || d < since) continue;
    const amt = Number(r.amount);
    const labels = labelNames(r);
    // Primary-label attribution replaces even-split once Phase 5 lands.
    const key = labels.length === 0 ? "Unlabeled" : labels[0];
    buckets.set(key, (buckets.get(key) ?? 0) + amt);
    total += amt;
  }
  if (buckets.size === 0) return `No spending in the last ${days} days.`;
  const lines = [`Total spent in last ${days} days: ${total}`];
  for (const [k, v] of [...buckets.entries()].sort((a, b) => b[1] - a[1])) {
    lines.push(`  ${k}: ${v} (${((v / total) * 100).toFixed(1)}%)`);
  }
  return lines.join("\n");
}

async function getCashflow(db: SupabaseClient, args: Record<string, unknown>): Promise<string> {
  const month = args.month != null ? boundedInt(args.month, 1, 1, 12) : null;
  const year = args.year != null ? boundedInt(args.year, 2020, 1970, 2100) : null;
  const now = new Date();
  let start: Date, end: Date, label: string;
  if (month && year) {
    start = new Date(Date.UTC(year, month - 1, 1));
    end = new Date(Date.UTC(year, month, 1));
    label = `${year}-${String(month).padStart(2, "0")}`;
  } else {
    const days = boundedInt(args.days, 30, 1, 3650);
    start = new Date(Date.now() - (days - 1) * 864e5);
    end = new Date(Date.now() + 864e5);
    label = `last ${days} days`;
  }
  const { data } = await db
    .from("transactions")
    .select("amount, type, direction, created_at, transacted_at")
    .eq("is_deleted", false).order("created_at", { ascending: false }).limit(500);
  let income = 0, spending = 0, investments = 0;
  for (const r of ((data ?? []) as Array<Record<string, unknown>>)) {
    const d = effectiveDate(r);
    if (!d || d < start || d >= end) continue;
    const amt = Number(r.amount);
    const type = r.type as string;
    const inflow = (r.direction ?? (type === "credit" ? "inflow" : "outflow")) === "inflow";
    if (type === "transfer") continue;
    if (type === "investment") { if (!inflow) investments += amt; continue; }
    if (inflow) income += amt; else spending += amt;
  }
  const savings = income - spending;
  const rate = income > 0 ? (savings / income) * 100 : 0;
  return `${label}\nIncome: ${income.toFixed(2)}\nTotal Outflow: ${spending.toFixed(2)}\n` +
    `Investments: ${investments.toFixed(2)}\nNet Cash Surplus: ${savings.toFixed(2)}\n` +
    `Savings rate: ${rate.toFixed(1)}%`;
}

async function getGoals(db: SupabaseClient): Promise<string> {
  const { data } = await db.from("goals")
    .select("name, type, target_amount, allocated_amount").eq("is_deleted", false);
  const rows = (data ?? []) as Array<Record<string, unknown>>;
  if (rows.length === 0) return "No goals set up yet.";
  return rows.map((g) => {
    const target = Number(g.target_amount);
    const alloc = Number(g.allocated_amount ?? 0);
    const pct = target === 0 ? 0 : (alloc / target) * 100;
    const tag = g.type === "emergency_fund" ? " [emergency fund]" : "";
    return `${g.name}${tag}: ${alloc} / ${target} (${pct.toFixed(0)}%)`;
  }).join("\n");
}

async function getInvoices(db: SupabaseClient): Promise<string> {
  const { data } = await db.from("invoices")
    .select("client, invoiced_usd, received_paypal, received_bank").eq("is_deleted", false);
  const rows = (data ?? []) as Array<Record<string, unknown>>;
  if (rows.length === 0) return "No invoices yet.";
  let inv = 0, pp = 0, bank = 0;
  const lines = rows.map((i) => {
    const invoiced = Number(i.invoiced_usd), paypal = Number(i.received_paypal ?? 0), b = Number(i.received_bank ?? 0);
    inv += invoiced; pp += paypal; bank += b;
    return `${i.client}: invoiced $${invoiced}, PayPal $${paypal}, in bank INR ${b}, difference $${invoiced - paypal}`;
  });
  lines.push("", `Total invoiced: $${inv}, PayPal: $${pp}, In bank: INR ${bank}, Difference: $${inv - pp}`);
  return lines.join("\n");
}

function monthlyEquivalent(amount: number, freq: string): number {
  if (freq === "weekly") return amount * 4.33;
  if (freq === "yearly") return amount / 12;
  return amount;
}

async function getRecurring(db: SupabaseClient, table: string): Promise<string> {
  const cols = table === "recurring_expenses" ? "name, amount, frequency, category" : "name, amount, frequency, source";
  const { data } = await db.from(table).select(cols).eq("is_deleted", false);
  const rows = (data ?? []) as Array<Record<string, unknown>>;
  if (rows.length === 0) return `No ${table.replace("_", " ")} set up.`;
  let total = 0;
  const lines = rows.map((r) => {
    const m = monthlyEquivalent(Number(r.amount), r.frequency as string);
    total += m;
    const tag = r.category ?? r.source ?? "";
    return `${r.name} (${tag}): ${r.amount}/${r.frequency} (~${m.toFixed(0)}/month)`;
  });
  lines.push("", `Total ~${total.toFixed(0)}/month`);
  return lines.join("\n");
}

async function getSnapshots(db: SupabaseClient, args: Record<string, unknown>): Promise<string> {
  const months = boundedInt(args.months, 12, 1, 120);
  const { data } = await db.from("monthly_snapshots")
    .select("month, year, income, expenses, investments, savings, savings_rate")
    .order("year", { ascending: false }).order("month", { ascending: false }).limit(months);
  const rows = (data ?? []) as Array<Record<string, unknown>>;
  if (rows.length === 0) return "No monthly snapshot data yet.";
  return rows.map((s) =>
    `${s.year}-${String(s.month).padStart(2, "0")}: Income ${s.income}, Outflow ${s.expenses}, ` +
    `Investments ${s.investments}, Saved ${s.savings} (${s.savings_rate}%)`
  ).join("\n");
}
