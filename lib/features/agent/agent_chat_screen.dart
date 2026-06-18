import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final _messages = <_ChatMessage>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isLoading = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance Agent')),
      body: Column(
        children: [
          if (_messages.isEmpty)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.smart_toy, size: 64, color: AppTheme.textSecondary),
                      const SizedBox(height: 16),
                      const Text('Ask me anything about your finances', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _suggestionChip('Can I afford a new keyboard?'),
                          _suggestionChip('What did I spend most on?'),
                          _suggestionChip('How much did I earn this month?'),
                          _suggestionChip('What are my outstanding invoices?'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return Align(
                    alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                      decoration: BoxDecoration(
                        color: msg.isUser ? AppTheme.primaryGreen.withAlpha(40) : AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(msg.text, style: const TextStyle(color: AppTheme.textPrimary)),
                    ),
                  );
                },
              ),
            ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppTheme.darkSurface,
              border: Border(top: BorderSide(color: Color(0xFF2C3E50))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Ask something...',
                      border: InputBorder.none,
                      filled: false,
                    ),
                    onSubmitted: _isLoading ? null : _sendMessage,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: AppTheme.primaryGreen),
                  onPressed: _isLoading ? null : () => _sendMessage(_inputCtrl.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: _isLoading ? null : () => _sendMessage(text),
      backgroundColor: AppTheme.darkCard,
      side: const BorderSide(color: Color(0xFF2C3E50)),
    );
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _inputCtrl.clear();

    try {
      final data = await _gatherFinancialData();
      final response = await _queryClaude(text, data);
      setState(() {
        _messages.add(_ChatMessage(text: response, isUser: false));
      });
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage(text: 'Sorry, I could not process that: $e', isUser: false));
      });
    } finally {
      setState(() => _isLoading = false);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Future<String> _gatherFinancialData() async {
    final supabase = SupabaseService().client;
    final buffer = StringBuffer();

    try {
      final balance = await supabase.rpc('fn_current_balance');
      buffer.writeln('Current balance: $balance');
    } catch (_) {}

    try {
      final earned = await supabase.from('transactions').select('amount').eq('type', 'credit').gte('created_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String());
      final spent = await supabase.from('transactions').select('amount').eq('type', 'debit').gte('created_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String());
      final earnedSum = (earned as List).fold(0.0, (s, t) => s + ((t as Map)['amount'] as num).toDouble());
      final spentSum = (spent as List).fold(0.0, (s, t) => s + ((t as Map)['amount'] as num).toDouble());
      buffer.writeln('Last 30 days - Earned: $earnedSum, Spent: $spentSum');
    } catch (_) {}

    try {
      final txCount = await supabase.from('transactions').select('id', count: CountOption.exact);
      buffer.writeln('Total transactions: ${txCount.count}');
    } catch (_) {}

    try {
      final invoices = await supabase.from('invoices').select('invoiced_usd, received_paypal, received_bank');
      double totalInvoiced = 0, totalReceived = 0;
      for (final inv in (invoices as List)) {
        final i = inv as Map;
        totalInvoiced += (i['invoiced_usd'] as num).toDouble();
        totalReceived += (i['received_paypal'] as num?)?.toDouble() ?? 0;
        totalReceived += (i['received_bank'] as num?)?.toDouble() ?? 0;
      }
      buffer.writeln('Invoices - Total invoiced: \$$totalInvoiced, Total received: \$$totalReceived');
    } catch (_) {}

    try {
      final goals = await supabase.from('goals').select('name, target_amount, allocated_amount');
      for (final g in (goals as List)) {
        final goal = g as Map;
        final pct = ((goal['allocated_amount'] as num?)?.toDouble() ?? 0) / ((goal['target_amount'] as num).toDouble()) * 100;
        buffer.writeln('Goal "${goal['name']}": ${pct.toStringAsFixed(0)}% funded');
      }
    } catch (_) {}

    return buffer.toString();
  }

  Future<String> _queryClaude(String question, String context) async {
    final response = await http.post(
      Uri.parse(AppConstants.claudeApiUrl),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': AppConstants.claudeApiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': 'claude-sonnet-4-20250514',
        'max_tokens': 1024,
        'system': 'You are a financial assistant. The user has provided their financial data below. Answer their question using only this data. Be concise and specific.',
        'messages': [
          {'role': 'user', 'content': 'Here is my current financial data:\n\n$context\n\nQuestion: $question'},
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = data['content'] as List<dynamic>;
      return content.map((c) => (c as Map<String, dynamic>)['text'] as String).join('\n');
    }
    return 'Error: ${response.statusCode} ${response.body}';
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}
