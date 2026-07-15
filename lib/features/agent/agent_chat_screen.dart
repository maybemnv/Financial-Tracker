import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/newsprint_primitives.dart';
import 'llm_service.dart';

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final _messages = <_ChatMessage>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _agent = LlmService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    await _agent.ready;
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(_agent.visibleMessages().map(
              (message) => _ChatMessage(
                text: message.text,
                isUser: message.isUser,
              ),
            ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return NewsprintPage(
      kicker: 'Agent Desk',
      title: 'Interrogate the ledger',
      subtitle: 'Ask for affordability, spending shape, goal pressure, or invoice exposure. The model answers from your live finance data.',
      actions: [
        NewsprintTag(label: 'Gemini ${_agent.modelName}'),
        OutlinedButton.icon(
          onPressed: () async {
            setState(() {
              _messages.clear();
            });
            await _agent.reset();
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('RESET'),
        ),
      ],
      child: Column(
        children: [
          Expanded(
            child: _messages.isEmpty ? _emptyState() : _messageThread(),
          ),
          const SizedBox(height: 12),
          NewsprintPanel(
            color: AppTheme.paper,
            child: Column(
              children: [
                TextField(
                  controller: _inputCtrl,
                  maxLines: 4,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: 'Ask the agent what changed, what is risky, or what you can afford next.',
                  ),
                  onSubmitted: _isLoading ? null : _sendMessage,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _suggestion('Can I afford a new keyboard?'),
                          _suggestion('What did I spend most on this month?'),
                          _suggestion('How much did I earn this month?'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : () => _sendMessage(_inputCtrl.text),
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(_isLoading ? 'THINKING' : 'SEND'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: NewsprintPanel(
        color: AppTheme.paperAlt,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('NO QUESTIONS YET', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Start with a practical question. The agent is best when the ask is concrete and tied to a decision.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageThread() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: EdgeInsets.zero,
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return Align(
          alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
            margin: const EdgeInsets.only(bottom: 10),
            child: NewsprintPanel(
              color: msg.isUser ? AppTheme.ink : AppTheme.paper,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.isUser ? 'YOU' : 'AGENT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: msg.isUser ? AppTheme.paperMuted : AppTheme.textSecondary,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    msg.text,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: msg.isUser ? AppTheme.paper : AppTheme.ink,
                        ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _suggestion(String text) {
    return ActionChip(
      label: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppTheme.ink)),
      onPressed: _isLoading ? null : () => _sendMessage(text),
      backgroundColor: AppTheme.paperAlt,
      side: const BorderSide(color: AppTheme.ink, width: 1.5),
      shape: const RoundedRectangleBorder(),
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
      final response = await _agent.ask(text);
      if (mounted) {
        setState(() {
          _messages.add(_ChatMessage(text: response, isUser: false));
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollCtrl.hasClients) return;
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
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
  const _ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}
