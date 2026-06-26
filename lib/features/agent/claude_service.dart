import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../core/supabase.dart';

enum ClaudeModel {
  sonnet4,
  haiku35,
}

extension ClaudeModelName on ClaudeModel {
  String get apiName {
    switch (this) {
      case ClaudeModel.sonnet4:
        return 'claude-sonnet-4-20250514';
      case ClaudeModel.haiku35:
        return 'claude-haiku-3-5-20241022';
    }
  }
}

class ClaudeService {
  static const _tools = [
    {
      'name': 'get_accounts',
      'description': 'List all financial accounts (SBI, Kotak, PayPal, Cash, investments) with their current balance derived from transactions.',
      'input_schema': {
        'type': 'object',
        'properties': {},
      },
    },
    {
      'name': 'get_net_worth',
      'description': 'Get total net worth across all accounts.',
      'input_schema': {
        'type': 'object',
        'properties': {},
      },
    },
    {
      'name': 'get_transactions',
      'description': 'Query transactions with optional filters. Returns amount, type, category, merchant, VPA, tags, date, account.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'type': {'type': 'string', 'description': 'Filter by type: debit, credit, transfer, investment', 'enum': ['debit', 'credit', 'transfer', 'investment']},
          'category': {'type': 'string', 'description': 'Filter by category: Food, Travel, Shopping, Work, Family, Health, Subscriptions, Other'},
          'days': {'type': 'number', 'description': 'How many days back to look (e.g. 7, 30, 90)'},
          'account_id': {'type': 'string', 'description': 'Filter by account UUID'},
          'limit': {'type': 'number', 'description': 'Max rows to return (default 50)'},
        },
      },
    },
    {
      'name': 'get_category_breakdown',
      'description': 'Get spending broken down by category for a given period.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'days': {'type': 'number', 'description': 'Period in days (e.g. 7, 30, 90). Default 30.'},
        },
      },
    },
    {
      'name': 'get_goals',
      'description': 'List all savings goals with target amount, amount allocated, and percent funded.',
      'input_schema': {
        'type': 'object',
        'properties': {},
      },
    },
    {
      'name': 'get_invoices',
      'description': 'Get freelance invoice summary: total invoiced, received via PayPal, received via bank, outstanding per client.',
      'input_schema': {
        'type': 'object',
        'properties': {},
      },
    },
    {
      'name': 'get_recurring_expenses',
      'description': 'List recurring/monthly expenses (subscriptions, SIPs, etc.) and their total monthly commitment.',
      'input_schema': {
        'type': 'object',
        'properties': {},
      },
    },
    {
      'name': 'get_monthly_snapshots',
      'description': 'Get monthly income/expenses/savings history from pre-computed snapshots. Useful for trends.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'months': {'type': 'number', 'description': 'Number of past months to return (default 12)'},
        },
      },
    },
  ];

  final supabase = SupabaseService().client;
  final List<Map<String, dynamic>> _messages = [];
  ClaudeModel model = ClaudeModel.sonnet4;

  void reset() => _messages.clear();

  Future<String> ask(String question) async {
    _messages.add({'role': 'user', 'content': question});

    for (int turn = 0; turn < 10; turn++) {
      final body = {
        'model': model.apiName,
        'max_tokens': 2048,
        'system': 'You are a personal finance assistant. You have access to financial data through tools. '
            'Use the tools to gather the information you need to answer the user\'s question. '
            'Be concise, specific, and cite actual numbers. '
            'If a question requires multiple data points, use multiple tool calls in parallel.',
        'messages': _messages,
        'tools': _tools,
      };

      final response = await http.post(
        Uri.parse(AppConstants.claudeApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': AppConstants.claudeApiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        return 'Error: ${response.statusCode} ${response.body}';
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = data['content'] as List<dynamic>;
      final stopReason = data['stop_reason'] as String?;

      if (content.isNotEmpty) {
        _messages.add({'role': 'assistant', 'content': content});
      }

      if (stopReason == 'end_turn' || stopReason == 'stop') {
        final texts = content
            .where((c) => (c as Map)['type'] == 'text')
            .map((c) => (c as Map)['text'] as String)
            .join('\n');
        return texts;
      }

      if (stopReason == 'tool_use') {
        final toolResults = <Map<String, dynamic>>[];

        for (final block in content) {
          if ((block as Map)['type'] != 'tool_use') continue;

          final toolName = block['name'] as String;
          final toolInput = block['input'] as Map<String, dynamic>? ?? {};
          final toolId = block['id'] as String;

          String result;
          try {
            result = await _executeTool(toolName, toolInput);
          } catch (e) {
            result = 'Error executing $toolName: $e';
          }

          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': toolId,
            'content': result,
          });
        }

        if (toolResults.isNotEmpty) {
          _messages.add({'role': 'user', 'content': toolResults});
        }

        continue;
      }

      break;
    }

    return 'I could not complete that request. Please try rephrasing.';
  }

  Future<String> _executeTool(String name, Map<String, dynamic> input) async {
    switch (name) {
      case 'get_accounts':
        return _getAccounts();
      case 'get_net_worth':
        return _getNetWorth();
      case 'get_transactions':
        return _getTransactions(input);
      case 'get_category_breakdown':
        return _getCategoryBreakdown(input);
      case 'get_goals':
        return _getGoals();
      case 'get_invoices':
        return _getInvoices();
      case 'get_recurring_expenses':
        return _getRecurringExpenses();
      case 'get_monthly_snapshots':
        return _getMonthlySnapshots(input);
      default:
        return 'Unknown tool: $name';
    }
  }

  Future<String> _getAccounts() async {
    try {
      final accounts = await supabase
          .from('accounts')
          .select('id, name, type, opening_balance, opening_date')
          .eq('is_deleted', false);

      final lines = <String>[];
      for (final a in (accounts as List)) {
        final acc = a as Map;
        try {
          final bal = await supabase.rpc('fn_account_balance',
              params: {'p_account_id': acc['id']});
          lines.add('${acc['name']} (${acc['type']}): $bal');
        } catch (_) {
          lines.add('${acc['name']} (${acc['type']}): balance unavailable');
        }
      }
      return lines.isEmpty ? 'No accounts found.' : lines.join('\n');
    } catch (e) {
      return 'Error fetching accounts: $e';
    }
  }

  Future<String> _getNetWorth() async {
    try {
      final netWorth = await supabase.rpc('fn_net_worth');
      return 'Net worth: $netWorth';
    } catch (e) {
      return 'Error computing net worth: $e';
    }
  }

  Future<String> _getTransactions(Map<String, dynamic> filters) async {
    try {
      var query = supabase
          .from('transactions')
          .select('amount, type, category, merchant, vpa, tags, account_id, created_at, note')
          .eq('is_deleted', false);

      if (filters['type'] != null) query = query.eq('type', filters['type']);
      if (filters['category'] != null) query = query.eq('category', filters['category']);
      if (filters['account_id'] != null) query = query.eq('account_id', filters['account_id']);
      if (filters['days'] != null) {
        final since = DateTime.now().subtract(Duration(days: (filters['days'] as num).toInt())).toIso8601String();
        query = query.gte('created_at', since);
      }

      final data = await query
          .order('created_at', ascending: false)
          .limit((filters['limit'] as num?)?.toInt() ?? 50);
      if ((data as List).isEmpty) return 'No transactions match those filters.';

      final lines = <String>[];
      for (final t in data) {
        final tx = t as Map;
        final prefix = tx['type'] == 'credit' ? '+' : '-';
        final cat = tx['category'] ?? 'uncategorized';
        final merchant = tx['merchant'] ?? 'unknown';
        final tags = (tx['tags'] as List?)?.join(', ') ?? '';
        lines.add('$prefix${tx['amount']} | $cat | $merchant${tags.isNotEmpty ? ' [$tags]' : ''}');
      }
      return lines.join('\n');
    } catch (e) {
      return 'Error querying transactions: $e';
    }
  }

  Future<String> _getCategoryBreakdown(Map<String, dynamic> input) async {
    try {
      final days = (input['days'] as num?)?.toInt() ?? 30;
      final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();

      final data = await supabase
          .from('transactions')
          .select('category, amount')
          .eq('type', 'debit')
          .eq('is_deleted', false)
          .gte('created_at', since);

      final categories = <String, double>{};
      double total = 0;

      for (final t in (data as List)) {
        final tx = t as Map;
        final cat = (tx['category'] as String?) ?? 'Uncategorized';
        final amt = (tx['amount'] as num).toDouble();
        categories.update(cat, (v) => v + amt, ifAbsent: () => amt);
        total += amt;
      }

      if (categories.isEmpty) return 'No spending in the last $days days.';

      final lines = <String>['Total spent in last $days days: $total'];
      final sorted = categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      for (final e in sorted) {
        final pct = (e.value / total * 100).toStringAsFixed(1);
        lines.add('  ${e.key}: ${e.value} ($pct%)');
      }
      return lines.join('\n');
    } catch (e) {
      return 'Error computing category breakdown: $e';
    }
  }

  Future<String> _getGoals() async {
    try {
      final data = await supabase
          .from('goals')
          .select('name, type, target_amount, allocated_amount')
          .eq('is_deleted', false);

      if ((data as List).isEmpty) return 'No goals set up yet.';

      final lines = <String>[];
      for (final g in data) {
        final goal = g as Map;
        final target = (goal['target_amount'] as num).toDouble();
        final allocated = (goal['allocated_amount'] as num?)?.toDouble() ?? 0;
        final pct = target == 0 ? 0 : (allocated / target) * 100;
        final typeTag = goal['type'] == 'emergency_fund' ? ' [emergency fund]' : '';
        lines.add('${goal['name']}$typeTag: $allocated / $target (${pct.toStringAsFixed(0)}%)');
      }
      return lines.join('\n');
    } catch (e) {
      return 'Error fetching goals: $e';
    }
  }

  Future<String> _getInvoices() async {
    try {
      final data = await supabase
          .from('invoices')
          .select('client, invoiced_usd, received_paypal, received_bank')
          .eq('is_deleted', false);

      if ((data as List).isEmpty) return 'No invoices yet.';

      double totalInvoiced = 0, totalReceived = 0;
      final lines = <String>[];
      for (final i in data) {
        final inv = i as Map;
        final invoiced = (inv['invoiced_usd'] as num).toDouble();
        final received = ((inv['received_paypal'] as num?)?.toDouble() ?? 0) +
            ((inv['received_bank'] as num?)?.toDouble() ?? 0);
        totalInvoiced += invoiced;
        totalReceived += received;
        lines.add('${inv['client']}: invoiced \$$invoiced, received \$$received, outstanding \$${invoiced - received}');
      }
      lines.add(''); // blank line before summary
      lines.add('Total invoiced: \$$totalInvoiced, Total received: \$$totalReceived, Outstanding: \$${totalInvoiced - totalReceived}');
      return lines.join('\n');
    } catch (e) {
      return 'Error fetching invoices: $e';
    }
  }

  Future<String> _getRecurringExpenses() async {
    try {
      final data = await supabase
          .from('recurring_expenses')
          .select('name, amount, frequency, category')
          .eq('is_deleted', false);

      if ((data as List).isEmpty) return 'No recurring expenses set up.';

      double monthlyTotal = 0;
      final lines = <String>[];
      for (final r in data) {
        final re = r as Map;
        final amt = (re['amount'] as num).toDouble();
        final freq = re['frequency'] as String;
        final monthly = freq == 'monthly' ? amt : freq == 'weekly' ? amt * 4.33 : amt / 12;
        monthlyTotal += monthly;
        lines.add('${re['name']} (${re['category']}): $amt/$freq (~${monthly.toStringAsFixed(0)}/month)');
      }
      lines.add('');
      lines.add('Total monthly commitment: ~${monthlyTotal.toStringAsFixed(0)}');
      return lines.join('\n');
    } catch (e) {
      return 'Error fetching recurring expenses: $e';
    }
  }

  Future<String> _getMonthlySnapshots(Map<String, dynamic> input) async {
    try {
      final months = (input['months'] as num?)?.toInt() ?? 12;
      final data = await supabase
          .from('monthly_snapshots')
          .select('month, year, income, expenses, savings, savings_rate')
          .order('year', ascending: false)
          .order('month', ascending: false)
          .limit(months);

      if ((data as List).isEmpty) return 'No monthly snapshot data yet.';

      final lines = <String>[];
      for (final s in data) {
        final snap = s as Map;
        lines.add('${snap['year']}-${snap['month'].toString().padLeft(2, '0')}: '
            'Income: ${snap['income']}, Expenses: ${snap['expenses']}, '
            'Saved: ${snap['savings']} (${snap['savings_rate']}%)');
      }
      return lines.join('\n');
    } catch (e) {
      return 'Error fetching monthly snapshots: $e';
    }
  }
}
