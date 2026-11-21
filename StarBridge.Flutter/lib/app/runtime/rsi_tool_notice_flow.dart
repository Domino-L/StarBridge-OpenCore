import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../platform/window/rsi_tool_notice_receipt.dart';
import '../localization/help_support_strings.dart';
import 'startup_prompt_queue.dart';

/// Main-window lifetime; terms readiness is owned by the caller. A failed
/// receipt write still consumes this launch, but never manufactures a disk read.
final class RsiToolNoticeFlow {
  RsiToolNoticeFlow({
    required this.receipt,
    required this.queue,
    required this.ready,
    required this.onChanged,
  });
  final RsiToolNoticeReceipt receipt;
  final StartupPromptQueue queue;
  final bool Function() ready;
  final VoidCallback onChanged;
  final _key = Object();
  bool _disposed = false, _reading = false, _checked = false, _seen = false;
  StarBridgeDialogRoute<void>? _route;
  VoidCallback? _cancelOperation;
  bool get blocksPrompts => !_disposed && !_seen;

  Future<T> _bounded<T>(Future<T> Function() action) async {
    final pending = Completer<T>();
    final timer = Timer(const Duration(seconds: 2), () {
      if (!pending.isCompleted) {
        pending.completeError(TimeoutException('Receipt'));
      }
    });
    void cancel() {
      timer.cancel();
      if (!pending.isCompleted) pending.completeError(StateError('Disposed'));
    }

    _cancelOperation = cancel;
    unawaited(
      Future<T>.sync(action).then(
        (value) {
          if (!pending.isCompleted) pending.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!pending.isCompleted) pending.completeError(error, stack);
        },
      ),
    );
    try {
      return await pending.future;
    } finally {
      timer.cancel();
      if (identical(_cancelOperation, cancel)) _cancelOperation = null;
    }
  }

  void wake() {
    if (_disposed || _seen || _reading || _route != null || !ready()) return;
    if (!_checked) {
      unawaited(_read());
      return;
    }
    queue.enqueue(
      _key,
      priority: 1, // Terms: 0; first-use onboarding: 50.
      eligible: () => !_disposed && !_seen && ready(),
      show: _show,
    );
  }

  Future<void> _read() async {
    _reading = true;
    var seen = false;
    try {
      seen = await _bounded(receipt.read);
    } catch (_) {}
    if (_disposed) return;
    _reading = false;
    _checked = true;
    _seen = seen;
    onChanged();
    wake();
  }

  Future<void> _show() async {
    final nav = queue.navigator;
    if (_disposed || nav == null || !ready()) return;
    await showStarBridgeDialog<void>(
      nav.context,
      barrierDismissible: false,
      onRouteCreated: (route) => _route = route,
      builder: (_) => RsiToolNoticeDialog(
        acknowledge: () async {
          try {
            await _bounded(receipt.markSeen);
          } catch (_) {
            // Next launch retries by showing the notice again.
          }
          if (_disposed) return;
          _seen = true;
          onChanged();
        },
      ),
    );
    _route = null;
  }

  void dispose() {
    _disposed = true;
    _cancelOperation?.call();
    queue.cancel(_key);
    retireStarBridgeDialog(_route);
  }
}

class RsiToolNoticeDialog extends StatefulWidget {
  const RsiToolNoticeDialog({required this.acknowledge, super.key});
  final Future<void> Function() acknowledge;

  @override
  State<RsiToolNoticeDialog> createState() => _RsiToolNoticeDialogState();
}

class _RsiToolNoticeDialogState extends State<RsiToolNoticeDialog> {
  bool _saving = false;

  Future<void> _acknowledge() async {
    if (_saving) return;
    final source = captureStarBridgeActivationSource()();
    setState(() => _saving = true);
    await widget.acknowledge();
    if (mounted) dismissStarBridgeDialog(context, source: source);
  }

  @override
  Widget build(BuildContext context) {
    final copy = rsiToolNoticeCopy(Localizations.localeOf(context));
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('rsi-tool-notice'),
        title: Text(copy.title),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(child: SelectableText(copy.body)),
        ),
        actions: [
          StarBridgeActionButton(
            key: const Key('rsi-tool-notice-got-it'),
            kind: StarBridgeActionKind.primary,
            onActivate: _saving ? null : (_) => unawaited(_acknowledge()),
            child: Text(copy.button),
          ),
        ],
      ),
    );
  }
}
