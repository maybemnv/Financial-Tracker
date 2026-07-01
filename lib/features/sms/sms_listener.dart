import 'dart:async';

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';

import '../../models/transaction.dart';
import 'sms_parser.dart';

class SmsListener {
  static final SmsListener _instance = SmsListener._();
  factory SmsListener() => _instance;
  SmsListener._();

  final _controller = StreamController<Transaction>.broadcast();
  final _telephony = Telephony.instance;
  bool _isListening = false;

  Stream<Transaction> get onTransactionParsed => _controller.stream;

  Future<bool> start() async {
    if (_isListening) return true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;

    final granted = await _telephony.requestSmsPermissions ?? false;
    if (!granted) return false;

    _isListening = true;
    _telephony.listenIncomingSms(
      onNewMessage: _handleMessage,
      listenInBackground: false,
    );
    return true;
  }

  Future<void> stop() async {
    _isListening = false;
  }

  void _handleMessage(SmsMessage message) {
    if (!_isListening) return;

    final body = message.body;
    if (body == null || body.trim().isEmpty) return;

    final receivedAt = message.date != null
        ? DateTime.fromMillisecondsSinceEpoch(message.date!)
        : null;
    final tx = SmsParser.parse(
      body,
      sender: message.address,
      receivedAt: receivedAt,
    );
    if (tx != null) _controller.add(tx);
  }

  void dispose() {
    _controller.close();
  }
}
