import 'package:crypto/crypto.dart';
import 'dart:convert';

/// SHA-256 dedup for SMS-sourced transactions. The hash is stored in
/// `transactions.raw_sms_hash` and checked before insert so a re-delivered SMS
/// (or a restarted listener) can't create duplicates.
class Dedup {
  /// Returns the hex SHA-256 of [rawSms], or null if the input is empty.
  static String? hashSms(String? rawSms) {
    if (rawSms == null || rawSms.isEmpty) return null;
    return sha256.convert(utf8.encode(rawSms)).toString();
  }
}
