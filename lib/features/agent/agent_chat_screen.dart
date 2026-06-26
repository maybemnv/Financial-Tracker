import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'claude_service.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final _messages = <_ChatMessage>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _claude = ClaudeService();
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
      appBar: AppBar(
        title: const Text('Finance Agent'),
        actions: [
          PopupMenuButton<ClaudeModel>(
            icon: const Icon(Icons.settings),
            onSelected: (m) => setState(() => _claude.model = m),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: ClaudeModel.sonnet4,
                child: Row(
                  children: [
                    Icon(Icons.check, size: 16, color: _claude.model == ClaudeModel.sonnet4 ? AppTheme.primaryGreen : Colors.transparent),
                    const SizedBox(width: 8),
                    const Text('Sonnet 4 (best)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ClaudeModel.haiku35,
                child: Row(
                  children: [
                    Icon(Icons.check, size: 16, color: _claude.model == ClaudeModel.haiku35 ? AppTheme.primaryGreen : Colors.transparent),
                    const SizedBox(width: 8),
                    const Text('Haiku 3.5 (fast)'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _messages.clear();
                _claude.reset();
              });
            },
          ),
        ],
      ),
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
                      Text('Model: ${_claude.model.apiName}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _suggestion('Can I afford a new keyboard?'),
                          _suggestion('What did I spend most on?'),
                          _suggestion('How much did I earn this month?'),
                          _suggestion('What are my outstanding invoices?'),
                          _suggestion('Am I on track for my emergency fund?'),
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

  Widget _suggestion(String text) {
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
      final response = await _claude.ask(text);
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(text: response, isUser: false));
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(text: 'Sorry, I could not process that: $e', isUser: false));
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}
