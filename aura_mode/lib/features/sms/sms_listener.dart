import 'dart:async';
import '../../models/transaction.dart';

class SmsListener {
  static final SmsListener _instance = SmsListener._();
  factory SmsListener() => _instance;
  SmsListener._();

  final _controller = StreamController<Transaction>.broadcast();
  Stream<Transaction> get onTransactionParsed => _controller.stream;

  bool _isListening = false;

  Future<void> start() async {
    if (_isListening) return;
    _isListening = true;
  }

  Future<void> stop() async {
    _isListening = false;
  }

  void emitTransaction(Transaction tx) {
    _controller.add(tx);
  }

  void dispose() {
    _controller.close();
  }
}
