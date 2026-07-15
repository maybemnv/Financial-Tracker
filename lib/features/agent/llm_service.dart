import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/supabase.dart';

class LlmVisibleMessage {
  const LlmVisibleMessage({
    required this.text,
    required this.isUser,
  });

  final String text;
  final bool isUser;
}

class LlmService {
  static const _tools = [
    {
      'type': 'function',
      'function': {
        'name': 'get_accounts',
        'description':
            'List all financial accounts (PSB, Kotak, PayPal, Cash, investments) with their current balance derived from transactions.',
        'parameters': {
          'type': 'object',
          'properties': {},
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_net_worth',
        'description': 'Get total net worth across all accounts.',
        'parameters': {
          'type': 'object',
          'properties': {},
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_transactions',
        'description':
            'Query transactions with optional filters. Returns amount, type, category, merchant, tags, date, and flow direction.',
        'parameters': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'description':
                  'Filter by type: debit, credit, transfer, investment',
              'enum': ['debit', 'credit', 'transfer', 'investment']
            },
            'category': {
              'type': 'string',
              'description':
                  'Filter by category: Food, Travel, Shopping, Work, Family, Health, Subscriptions, Other'
            },
            'days': {
              'type': 'number',
              'description': 'How many days back to look (e.g. 7, 30, 90)'
            },
            'account_id': {
              'type': 'string',
              'description': 'Filter by account UUID'
            },
            'limit': {
              'type': 'number',
              'description': 'Max rows to return (default 50)'
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_category_breakdown',
        'description':
            'Get spending broken down by category for a given period.',
        'parameters': {
          'type': 'object',
          'properties': {
            'days': {
              'type': 'number',
              'description': 'Period in days (e.g. 7, 30, 90). Default 30.'
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_cashflow_summary',
        'description':
            'Get income, spending, investments, and savings for a specific month or rolling day window. PayPal payout/deposit inflows count as earnings.',
        'parameters': {
          'type': 'object',
          'properties': {
            'month': {
              'type': 'number',
              'description': 'Calendar month number 1-12. Pair with year.'
            },
            'year': {
              'type': 'number',
              'description': 'Calendar year, for example 2026. Pair with month.'
            },
            'days': {
              'type': 'number',
              'description':
                  'Optional rolling window in days. Ignored when month+year are provided.'
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_goals',
        'description':
            'List all savings goals with target amount, amount allocated, and percent funded.',
        'parameters': {
          'type': 'object',
          'properties': {},
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_invoices',
        'description':
            'Get freelance invoice summary: total invoiced, received via PayPal, INR bank receipts, and outstanding difference per client.',
        'parameters': {
          'type': 'object',
          'properties': {},
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_recurring_expenses',
        'description':
            'List recurring/monthly expenses (subscriptions, SIPs, etc.) and their total monthly commitment.',
        'parameters': {
          'type': 'object',
          'properties': {},
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_recurring_income',
        'description':
            'List expected recurring income and its approximate monthly total.',
        'parameters': {
          'type': 'object',
          'properties': {},
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_monthly_snapshots',
        'description':
            'Get monthly income, expenses, savings, and investment history from pre-computed snapshots.',
        'parameters': {
          'type': 'object',
          'properties': {
            'months': {
              'type': 'number',
              'description': 'Number of past months to return (default 12)'
            },
          },
        },
      },
    },
  ];

  final supabase = SupabaseService().client;
  final List<Map<String, dynamic>> _messages = [];
  late final Future<void> _loadFuture = _loadLastSession();

  String? _sessionId;

  Future<void> get ready => _loadFuture;
  String get modelName => AppConstants.agentModel;

  List<LlmVisibleMessage> visibleMessages() {
    final visible = <LlmVisibleMessage>[];
    for (final message in _messages) {
      final role = message['role'] as String?;
      final text = _extractVisibleText(message['content']);
      if (text.isEmpty) continue;
      if (role == 'user') {
        visible.add(LlmVisibleMessage(text: text, isUser: true));
      } else if (role == 'assistant') {
        visible.add(LlmVisibleMessage(text: text, isUser: false));
      }
    }
    return visible;
  }

  Future<void> reset() async {
    await _loadFuture;
    _messages.clear();
    await _persistMessages();
  }

  Future<String> ask(String question) async {
    await _loadFuture;
    _messages.add({'role': 'user', 'content': question});

    for (var turn = 0; turn < 10; turn++) {
      final body = {
        'model': modelName,
        'max_tokens': 2048,
        'temperature': 0.2,
        'messages': _messages,
        'tools': _tools,
        'tool_choice': 'auto',
      };

      http.Response response;
      try {
        response = await _postWithRetry(body);
      } catch (e) {
        await _persistMessages();
        return 'Error: $e';
      }

      if (response.statusCode != 200) {
        await _persistMessages();
        return 'Error: ${response.statusCode} ${response.body}';
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = (data['choices'] as List<dynamic>? ?? const []);
      if (choices.isEmpty) {
        await _persistMessages();
        return 'Error: Gemini returned no choices.';
      }

      final choice = Map<String, dynamic>.from(choices.first as Map);
      final message =
          Map<String, dynamic>.from(choice['message'] as Map? ?? const {});
      final assistantText = _extractVisibleText(message['content']);
      final toolCalls =
          (message['tool_calls'] as List<dynamic>? ?? const []).map((call) {
        return Map<String, dynamic>.from(call as Map);
      }).toList();

      if (toolCalls.isNotEmpty) {
        _messages.add({
          'role': 'assistant',
          'content': assistantText,
          'tool_calls': toolCalls,
        });

        for (final toolCall in toolCalls) {
          final function = Map<String, dynamic>.from(
            toolCall['function'] as Map? ?? const {},
          );
          final toolName = function['name'] as String? ?? '';
          final toolId = toolCall['id'] as String? ?? '';
          final toolInput = _decodeToolArguments(
            function['arguments'] as String?,
          );

          String result;
          try {
            result = await _executeTool(toolName, toolInput);
          } catch (e) {
            result = 'Error executing $toolName: $e';
          }

          _messages.add({
            'role': 'tool',
            'tool_call_id': toolId,
            'content': result,
          });
        }
        continue;
      }

      if (assistantText.isNotEmpty) {
        _messages.add({'role': 'assistant', 'content': assistantText});
        await _persistMessages();
        return assistantText;
      }

      await _persistMessages();
      return 'I could not complete that request. Please try rephrasing.';
    }

    await _persistMessages();
    return 'I could not complete that request. Please try rephrasing.';
  }

  Future<void> _loadLastSession() async {
    try {
      final session = await supabase
          .from('chat_sessions')
          .select('id, messages')
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (session == null) return;
      _sessionId = session['id'] as String?;
      final stored = session['messages'];
      if (stored is List) {
        _messages
          ..clear()
          ..addAll(_normalizeStoredMessages(stored));
      }
    } catch (_) {
      // Persistence must never block the agent if the migration is not applied.
    }
  }

  List<Map<String, dynamic>> _normalizeStoredMessages(List<dynamic> raw) {
    final normalized = <Map<String, dynamic>>[];

    for (final item in raw) {
      if (item is! Map) continue;
      final message = Map<String, dynamic>.from(item);
      final role = message['role'] as String?;
      if (role == null) continue;

      if (role == 'user') {
        final text = _extractVisibleText(message['content']);
        if (text.isNotEmpty) {
          normalized.add({'role': 'user', 'content': text});
        }
        continue;
      }

      if (role == 'assistant') {
        final toolCalls =
            (message['tool_calls'] as List<dynamic>? ?? const []).map((call) {
          return Map<String, dynamic>.from(call as Map);
        }).toList();
        final text = _extractVisibleText(message['content']);

        if (toolCalls.isNotEmpty) {
          normalized.add({
            'role': 'assistant',
            'content': text,
            'tool_calls': toolCalls,
          });
        } else if (text.isNotEmpty) {
          normalized.add({'role': 'assistant', 'content': text});
        }
        continue;
      }

      if (role == 'tool') {
        final content = _extractVisibleText(message['content']);
        final toolCallId = message['tool_call_id'] as String?;
        if (content.isNotEmpty && toolCallId != null && toolCallId.isNotEmpty) {
          normalized.add({
            'role': 'tool',
            'tool_call_id': toolCallId,
            'content': content,
          });
        }
      }
    }

    return normalized;
  }

  Future<void> _persistMessages() async {
    try {
      if (_sessionId == null) {
        final inserted = await supabase
            .from('chat_sessions')
            .insert({'messages': _messages})
            .select('id')
            .single();
        _sessionId = inserted['id'] as String?;
        return;
      }

      await supabase
          .from('chat_sessions')
          .update({'messages': _messages}).eq('id', _sessionId!);
    } catch (_) {
      // Chat persistence is best-effort; tool answers should still work.
    }
  }

  Future<http.Response> _postWithRetry(Map<String, dynamic> body) async {
    Object? lastError;
    http.Response? lastResponse;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http.post(
          Uri.parse(AppConstants.geminiApiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${AppConstants.geminiApiKey}',
          },
          body: jsonEncode(body),
        );

        if (response.statusCode != 429 && response.statusCode < 500) {
          return response;
        }
        lastResponse = response;
      } catch (e) {
        lastError = e;
      }

      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }

    if (lastResponse != null) {
      return lastResponse;
    }
    throw Exception(lastError ?? 'Gemini request failed');
  }

  Map<String, dynamic> _decodeToolArguments(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  String _extractVisibleText(dynamic content) {
    if (content is String) {
      return content.trim();
    }
    if (content is List) {
      return content
          .whereType<Map>()
          .map((block) => Map<String, dynamic>.from(block))
          .where((block) {
            final type = block['type'] as String?;
            return type == null || type == 'text';
          })
          .map((block) => block['text'] as String? ?? '')
          .where((text) => text.trim().isNotEmpty)
          .join('\n')
          .trim();
    }
    return '';
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
      case 'get_cashflow_summary':
        return _getCashflowSummary(input);
      case 'get_goals':
        return _getGoals();
      case 'get_invoices':
        return _getInvoices();
      case 'get_recurring_expenses':
        return _getRecurringExpenses();
      case 'get_recurring_income':
        return _getRecurringIncome();
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
          .select('id, name, type')
          .eq('is_deleted', false);

      final lines = <String>[];
      for (final rawAccount in (accounts as List)) {
        final account = Map<String, dynamic>.from(rawAccount as Map);
        try {
          final balance = await supabase.rpc('fn_account_balance',
              params: {'p_account_id': account['id']});
          lines.add('${account['name']} (${account['type']}): $balance');
        } catch (_) {
          lines.add(
              '${account['name']} (${account['type']}): balance unavailable');
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
      final limit = _boundedLimit(filters['limit'] as num?);
      final days = (filters['days'] as num?)?.toInt();
      final since =
          days != null ? DateTime.now().subtract(Duration(days: days)) : null;

      var query = supabase
          .from('transactions')
          .select(
              'amount, type, direction, category, merchant, vpa, tags, account_id, created_at, transacted_at, note')
          .eq('is_deleted', false);

      if (filters['type'] != null) {
        query = query.eq('type', filters['type']);
      }
      if (filters['category'] != null) {
        query = query.eq('category', filters['category']);
      }
      if (filters['account_id'] != null) {
        query = query.eq('account_id', filters['account_id']);
      }

      final data = await query
          .order('created_at', ascending: false)
          .limit(days != null ? 200 : limit);

      final rows = (data as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) {
        final effectiveDate = _effectiveDate(row);
        if (since != null &&
            (effectiveDate == null || effectiveDate.isBefore(since))) {
          return false;
        }
        return true;
      }).toList()
        ..sort((a, b) {
          final left =
              _effectiveDate(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right =
              _effectiveDate(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
          return right.compareTo(left);
        });

      if (rows.isEmpty) return 'No transactions match those filters.';

      final lines = <String>[];
      for (final tx in rows.take(limit)) {
        final direction = _isInflow(tx) ? '+' : '-';
        final date = _effectiveDate(tx);
        final merchant = tx['merchant'] ?? tx['note'] ?? tx['vpa'] ?? 'unknown';
        final label = tx['category'] ?? tx['type'];
        final tags = (tx['tags'] as List?)?.join(', ') ?? '';
        final dateLabel = date != null
            ? date.toIso8601String().split('T').first
            : 'unknown-date';
        lines.add(
          '$dateLabel | $direction${tx['amount']} | $label | $merchant${tags.isNotEmpty ? ' [$tags]' : ''}',
        );
      }
      return lines.join('\n');
    } catch (e) {
      return 'Error querying transactions: $e';
    }
  }

  Future<String> _getCategoryBreakdown(Map<String, dynamic> input) async {
    try {
      final days = (input['days'] as num?)?.toInt() ?? 30;
      final since = DateTime.now().subtract(Duration(days: days));

      final data = await supabase
          .from('transactions')
          .select('category, amount, created_at, transacted_at')
          .eq('type', 'debit')
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(200);

      final categories = <String, double>{};
      var total = 0.0;
      for (final rawTx in (data as List)) {
        final tx = Map<String, dynamic>.from(rawTx as Map);
        final effectiveDate = _effectiveDate(tx);
        if (effectiveDate == null || effectiveDate.isBefore(since)) {
          continue;
        }

        final category = (tx['category'] as String?) ?? 'Uncategorized';
        final amount = (tx['amount'] as num).toDouble();
        categories.update(category, (v) => v + amount, ifAbsent: () => amount);
        total += amount;
      }

      if (categories.isEmpty) return 'No spending in the last $days days.';

      final lines = <String>['Total spent in last $days days: $total'];
      final sorted = categories.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in sorted) {
        final pct = (entry.value / total * 100).toStringAsFixed(1);
        lines.add('  ${entry.key}: ${entry.value} ($pct%)');
      }
      return lines.join('\n');
    } catch (e) {
      return 'Error computing category breakdown: $e';
    }
  }

  Future<String> _getCashflowSummary(Map<String, dynamic> input) async {
    try {
      final month = (input['month'] as num?)?.toInt();
      final year = (input['year'] as num?)?.toInt();
      final days = (input['days'] as num?)?.toInt();

      final now = DateTime.now();
      late final DateTime periodStart;
      late final DateTime periodEnd;
      late final String label;

      if (month != null && year != null) {
        periodStart = DateTime(year, month);
        periodEnd = DateTime(year, month + 1);
        label =
            '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
      } else {
        final rollingDays = days ?? 30;
        periodStart = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: rollingDays - 1));
        periodEnd = now.add(const Duration(days: 1));
        label = 'last $rollingDays days';
      }

      final data = await supabase
          .from('transactions')
          .select(
              'amount, type, direction, merchant, bank, note, created_at, transacted_at')
          .eq('is_deleted', false)
          .order('created_at', ascending: false)
          .limit(500);

      var income = 0.0;
      var spending = 0.0;
      var investments = 0.0;
      var transactionCount = 0;

      for (final rawRow in (data as List)) {
        final row = Map<String, dynamic>.from(rawRow as Map);
        final effectiveDate = _effectiveDate(row);
        if (effectiveDate == null ||
            effectiveDate.isBefore(periodStart) ||
            !effectiveDate.isBefore(periodEnd)) {
          continue;
        }

        transactionCount += 1;
        final amount = (row['amount'] as num).toDouble();
        if (_isInvestmentOutflowRow(row)) {
          investments += amount;
        } else if (_isIncomeRow(row)) {
          income += amount;
        } else if (_isSpendingRow(row)) {
          spending += amount;
        }
      }

      final savings = income - spending;
      final savingsRate = income > 0 ? (savings / income) * 100 : 0.0;

      return '$label\n'
          'Income: ${income.toStringAsFixed(2)}\n'
          'Spending: ${spending.toStringAsFixed(2)}\n'
          'Investments: ${investments.toStringAsFixed(2)}\n'
          'Savings: ${savings.toStringAsFixed(2)}\n'
          'Savings rate: ${savingsRate.toStringAsFixed(1)}%\n'
          'Transactions considered: $transactionCount\n'
          'PayPal payout/deposit inflows are included in income.';
    } catch (e) {
      return 'Error computing cashflow summary: $e';
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
      for (final rawGoal in data) {
        final goal = Map<String, dynamic>.from(rawGoal as Map);
        final target = (goal['target_amount'] as num).toDouble();
        final allocated = (goal['allocated_amount'] as num?)?.toDouble() ?? 0;
        final pct = target == 0 ? 0 : (allocated / target) * 100;
        final typeTag =
            goal['type'] == 'emergency_fund' ? ' [emergency fund]' : '';
        lines.add(
            '${goal['name']}$typeTag: $allocated / $target (${pct.toStringAsFixed(0)}%)');
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
          .select(
              'client, invoiced_usd, received_paypal, received_bank, fx_rate')
          .eq('is_deleted', false);

      if ((data as List).isEmpty) return 'No invoices yet.';

      var totalInvoiced = 0.0;
      var totalPaypal = 0.0;
      var totalBankInr = 0.0;
      final lines = <String>[];
      for (final rawInvoice in data) {
        final invoice = Map<String, dynamic>.from(rawInvoice as Map);
        final invoiced = (invoice['invoiced_usd'] as num).toDouble();
        final paypal = (invoice['received_paypal'] as num?)?.toDouble() ?? 0;
        final bankInr = (invoice['received_bank'] as num?)?.toDouble() ?? 0;
        totalInvoiced += invoiced;
        totalPaypal += paypal;
        totalBankInr += bankInr;
        lines.add(
          '${invoice['client']}: invoiced \$$invoiced, PayPal \$$paypal, in bank INR $bankInr, difference \$${invoiced - paypal}',
        );
      }
      lines.add('');
      lines.add(
        'Total invoiced: \$$totalInvoiced, PayPal: \$$totalPaypal, In bank: INR $totalBankInr, Difference: \$${totalInvoiced - totalPaypal}',
      );
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

      var monthlyTotal = 0.0;
      final lines = <String>[];
      for (final rawExpense in data) {
        final expense = Map<String, dynamic>.from(rawExpense as Map);
        final amount = (expense['amount'] as num).toDouble();
        final frequency = expense['frequency'] as String;
        final monthly = _monthlyEquivalent(amount, frequency);
        monthlyTotal += monthly;
        lines.add(
          '${expense['name']} (${expense['category']}): $amount/$frequency (~${monthly.toStringAsFixed(0)}/month)',
        );
      }
      lines.add('');
      lines
          .add('Total monthly commitment: ~${monthlyTotal.toStringAsFixed(0)}');
      return lines.join('\n');
    } catch (e) {
      return 'Error fetching recurring expenses: $e';
    }
  }

  Future<String> _getRecurringIncome() async {
    try {
      final data = await supabase
          .from('recurring_income')
          .select('name, amount, frequency, source')
          .eq('is_deleted', false);

      if ((data as List).isEmpty) return 'No recurring income set up.';

      var monthlyTotal = 0.0;
      final lines = <String>[];
      for (final rawIncome in data) {
        final income = Map<String, dynamic>.from(rawIncome as Map);
        final amount = (income['amount'] as num).toDouble();
        final frequency = income['frequency'] as String;
        final monthly = _monthlyEquivalent(amount, frequency);
        monthlyTotal += monthly;
        final source = income['source'] ?? 'unknown source';
        lines.add(
          '${income['name']} ($source): $amount/$frequency (~${monthly.toStringAsFixed(0)}/month)',
        );
      }
      lines.add('');
      lines.add(
          'Expected monthly recurring income: ~${monthlyTotal.toStringAsFixed(0)}');
      return lines.join('\n');
    } catch (e) {
      return 'Error fetching recurring income: $e';
    }
  }

  Future<String> _getMonthlySnapshots(Map<String, dynamic> input) async {
    try {
      final months = (input['months'] as num?)?.toInt() ?? 12;
      final data = await supabase
          .from('monthly_snapshots')
          .select(
              'month, year, income, expenses, investments, savings, savings_rate')
          .order('year', ascending: false)
          .order('month', ascending: false)
          .limit(months);

      if ((data as List).isEmpty) return 'No monthly snapshot data yet.';

      final lines = <String>[];
      for (final rawSnapshot in data) {
        final snapshot = Map<String, dynamic>.from(rawSnapshot as Map);
        lines.add(
          '${snapshot['year']}-${snapshot['month'].toString().padLeft(2, '0')}: Income ${snapshot['income']}, Expenses ${snapshot['expenses']}, Investments ${snapshot['investments']}, Saved ${snapshot['savings']} (${snapshot['savings_rate']}%)',
        );
      }
      return lines.join('\n');
    } catch (e) {
      return 'Error fetching monthly snapshots: $e';
    }
  }

  int _boundedLimit(num? raw, {int fallback = 50}) {
    final value = raw?.toInt() ?? fallback;
    if (value < 1) return 1;
    if (value > 200) return 200;
    return value;
  }

  double _monthlyEquivalent(double amount, String frequency) {
    switch (frequency) {
      case 'weekly':
        return amount * 4.33;
      case 'yearly':
        return amount / 12;
      case 'monthly':
      default:
        return amount;
    }
  }

  DateTime? _effectiveDate(Map<String, dynamic> row) {
    final transactedAt = row['transacted_at'] as String?;
    if (transactedAt != null && transactedAt.isNotEmpty) {
      return DateTime.tryParse(transactedAt);
    }
    final createdAt = row['created_at'] as String?;
    if (createdAt != null && createdAt.isNotEmpty) {
      return DateTime.tryParse(createdAt);
    }
    return null;
  }

  bool _isInflow(Map<String, dynamic> row) {
    final direction = row['direction'] as String?;
    if (direction != null) return direction == 'inflow';
    return row['type'] == 'credit';
  }

  bool _isIncomeRow(Map<String, dynamic> row) {
    final type = row['type'] as String?;
    if (type == 'transfer' || type == 'investment') return false;
    if (_looksLikePayPalEarning(row) && _isInflow(row)) return true;
    return _isInflow(row) || type == 'credit';
  }

  bool _isSpendingRow(Map<String, dynamic> row) {
    final type = row['type'] as String?;
    if (type == 'transfer' || type == 'investment') return false;
    return !_isIncomeRow(row);
  }

  bool _isInvestmentOutflowRow(Map<String, dynamic> row) {
    final type = row['type'] as String?;
    if (type != 'investment') return false;
    final direction = row['direction'] as String?;
    return direction == null || direction == 'outflow';
  }

  bool _looksLikePayPalEarning(Map<String, dynamic> row) {
    final merchant = (row['merchant'] as String?)?.toLowerCase() ?? '';
    final bank = (row['bank'] as String?)?.toLowerCase() ?? '';
    final note = (row['note'] as String?)?.toLowerCase() ?? '';
    return merchant.contains('paypal') ||
        bank.contains('paypal') ||
        note.contains('paypal payout') ||
        note.contains('paypal deposit');
  }
}
