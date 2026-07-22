import '../../core/constants.dart';
import '../../core/supabase.dart';

class LlmVisibleMessage {
  const LlmVisibleMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

/// Thin client for the Agent Desk. All Gemini traffic and tool execution now
/// live in the `agent` Supabase Edge Function (Phase 3); this class only holds
/// the visible conversation, persists it to the owner-scoped `chat_sessions`
/// table, and forwards turns to the function with the caller's session JWT.
///
/// The public API (`ready`, `visibleMessages`, `modelName`, `reset`, `ask`) is
/// unchanged so `AgentChatScreen` did not need to change.
class LlmService {
  final supabase = SupabaseService().client;

  /// Only user/assistant text turns — the Edge Function runs its own tool loop
  /// per request, so the browser never holds tool/tool_call messages.
  final List<Map<String, dynamic>> _messages = [];
  late final Future<void> _loadFuture = _loadLastSession();

  String? _sessionId;

  Future<void> get ready => _loadFuture;
  String get modelName => AppConstants.agentModel;

  List<LlmVisibleMessage> visibleMessages() {
    final visible = <LlmVisibleMessage>[];
    for (final message in _messages) {
      final role = message['role'] as String?;
      final text = (message['content'] as String? ?? '').trim();
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

    String answer;
    try {
      final response = await supabase.functions.invoke(
        'agent',
        body: {'messages': _messages},
      );
      final status = response.status;
      final data = response.data;
      if (status == 200 && data is Map && data['answer'] is String) {
        answer = (data['answer'] as String).trim();
      } else if (data is Map && data['error'] is String) {
        answer = _friendlyError(status, data['error'] as String);
      } else {
        answer = 'The assistant is unavailable right now (status $status).';
      }
    } catch (e) {
      answer = 'The assistant could not be reached. Please try again.';
    }

    if (answer.isNotEmpty) {
      _messages.add({'role': 'assistant', 'content': answer});
    }
    await _persistMessages();
    return answer.isEmpty
        ? 'I could not complete that request. Please try rephrasing.'
        : answer;
  }

  String _friendlyError(int status, String code) {
    switch (code) {
      case 'not_owner':
      case 'missing_token':
        return 'Please sign in again to use the Agent Desk.';
      case 'payload_too_large':
        return 'That conversation is too long — start a new chat.';
      default:
        return 'The assistant hit an error ($code). Please try again.';
    }
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
      // Persistence must never block the agent.
    }
  }

  List<Map<String, dynamic>> _normalizeStoredMessages(List<dynamic> raw) {
    final normalized = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final role = item['role'] as String?;
      final content = item['content'];
      if ((role == 'user' || role == 'assistant') && content is String) {
        final text = content.trim();
        if (text.isNotEmpty) {
          normalized.add({'role': role, 'content': text});
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
      // Best-effort persistence.
    }
  }
}
