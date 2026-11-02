import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

enum ChatConnectionPhase { connected, reconnecting, restored }

/// B1 (2026-10-21 user choice): a quiet live-connection notice for a chat.
///
/// Reads an existing health signal only; it never starts IO. An interruption
/// is announced after [threshold] of continuous ill health (shorter jitter is
/// silent), and only after the connection was healthy once, so startup is not
/// an "interruption". Recovery shows [ChatConnectionPhase.restored] for
/// [restoredFor]. Without a health source (gateway off, older Host, example
/// port) nothing is ever shown: the chat behaves as before.
final class ChatConnectionNotice extends ChangeNotifier {
  ChatConnectionNotice({
    required this.healthy,
    this.onRestored,
    this.threshold = const Duration(seconds: 3),
    this.restoredFor = const Duration(seconds: 2),
    this.poll = const Duration(milliseconds: 500),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Null when this chat has no health source.
  final bool? Function() healthy;
  final void Function()? onRestored;
  final Duration threshold, restoredFor, poll;
  final DateTime Function() _now;
  ChatConnectionPhase phase = ChatConnectionPhase.connected;
  bool _seenHealthy = false, _disposed = false;
  DateTime? _illSince;
  Timer? _poll, _restored;

  void start() {
    if (_disposed) return;
    _poll ??= Timer.periodic(poll, (_) => check());
    check();
  }

  void stop() {
    _poll?.cancel();
    _poll = null;
    _restored?.cancel();
    _restored = null;
    _illSince = null;
    _set(ChatConnectionPhase.connected);
  }

  @visibleForTesting
  void check() {
    if (_disposed) return;
    final value = healthy();
    if (value == null) return;
    if (value) {
      _seenHealthy = true;
      _illSince = null;
      if (phase == ChatConnectionPhase.reconnecting) {
        _set(ChatConnectionPhase.restored);
        onRestored?.call();
        _restored?.cancel();
        _restored = Timer(restoredFor, () {
          _restored = null;
          if (phase == ChatConnectionPhase.restored) {
            _set(ChatConnectionPhase.connected);
          }
        });
      }
      return;
    }
    if (!_seenHealthy) return;
    final since = _illSince ??= _now();
    if (phase != ChatConnectionPhase.reconnecting &&
        _now().difference(since) >= threshold) {
      _restored?.cancel();
      _restored = null;
      _set(ChatConnectionPhase.reconnecting);
    }
  }

  void _set(ChatConnectionPhase value) {
    if (_disposed || phase == value) return;
    phase = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _restored?.cancel();
    super.dispose();
  }
}

/// The 2px line at the top of the conversation while reconnecting. It flows
/// unless motion is reduced, then it is a still line.
class ChatReconnectLine extends StatelessWidget {
  const ChatReconnectLine(this.notice, {super.key});
  final ChatConnectionNotice notice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notice,
    builder: (context, _) {
      if (notice.phase != ChatConnectionPhase.reconnecting) {
        return const SizedBox(height: 2);
      }
      final color = context.tokens.colors.warning;
      return SizedBox(
        key: const ValueKey('chat-reconnect-line'),
        height: 2,
        child: resolveStarBridgeInteraction(context).reduceMotion
            ? ColoredBox(color: color.withValues(alpha: .6))
            : LinearProgressIndicator(
                minHeight: 2,
                color: color,
                backgroundColor: Colors.transparent,
              ),
      );
    },
  );
}

/// The composer status line: "正在重新连接…", then "已恢复" which fades out.
class ChatConnectionStatus extends StatelessWidget {
  const ChatConnectionStatus(this.notice, {super.key});
  final ChatConnectionNotice notice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notice,
    builder: (context, _) {
      final colors = context.tokens.colors;
      String t(String key) => AppStrings.of(context).text('direct.$key');
      final phase = notice.phase;
      final Widget line = switch (phase) {
        ChatConnectionPhase.reconnecting => Text(
          t('connection.reconnecting'),
          key: const ValueKey('chat-connection-reconnecting'),
          style: TextStyle(color: colors.warning),
        ),
        ChatConnectionPhase.restored => Text(
          t('connection.restored'),
          key: const ValueKey('chat-connection-restored'),
          style: TextStyle(color: colors.success),
        ),
        ChatConnectionPhase.connected => const SizedBox.shrink(
          key: ValueKey('chat-connection-quiet'),
        ),
      };
      return Semantics(
        liveRegion: phase != ChatConnectionPhase.connected,
        child: AnimatedSwitcher(
          duration: resolveStarBridgeInteraction(context).reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 400),
          child: line,
        ),
      );
    },
  );
}
