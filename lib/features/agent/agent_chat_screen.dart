import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
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
                      ],
                    ),
                  ],
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
                    onSubmitted: _sendMessage,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: AppTheme.primaryGreen),
                  onPressed: () => _sendMessage(_inputCtrl.text),
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
      onPressed: () => _sendMessage(text),
      backgroundColor: AppTheme.darkCard,
      side: const BorderSide(color: Color(0xFF2C3E50)),
    );
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
    });
    _inputCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(text: '...', isUser: false));
    });

    try {
      final response = await _queryClaude(text);
      setState(() {
        _messages.removeLast();
        _messages.add(_ChatMessage(text: response, isUser: false));
      });
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add(_ChatMessage(text: 'Sorry, I couldn\'t process that: $e', isUser: false));
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Future<String> _queryClaude(String question) async {
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
        'messages': [
          {
            'role': 'user',
            'content': question,
          },
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
