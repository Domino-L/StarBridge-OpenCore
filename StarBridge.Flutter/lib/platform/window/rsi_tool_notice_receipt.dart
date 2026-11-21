import 'package:flutter/services.dart';

/// Device-local teaching receipt, unrelated to terms or account consent.
abstract interface class RsiToolNoticeReceipt {
  static const key = 'rsiToolNotice.2026-11-03';
  Future<bool> read();
  Future<void> markSeen();
}

final class MethodChannelRsiToolNoticeReceipt implements RsiToolNoticeReceipt {
  const MethodChannelRsiToolNoticeReceipt();
  static const _channel = MethodChannel('starbridge/rsi-tool-notice');

  @override
  Future<bool> read() async =>
      await _channel.invokeMethod<bool>('read', RsiToolNoticeReceipt.key) ==
      true;

  @override
  Future<void> markSeen() =>
      _channel.invokeMethod<void>('markSeen', RsiToolNoticeReceipt.key);
}
