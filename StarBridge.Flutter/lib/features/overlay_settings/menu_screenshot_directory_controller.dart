import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/window/menu_screenshot_directory.dart';

/// Immediate native destination actions, not an unsaved menu layout draft.
class MenuScreenshotDirectoryController extends ChangeNotifier {
  MenuScreenshotDirectoryController(this.port);
  final MenuScreenshotDirectoryPort port;
  MenuScreenshotDirectory? saved;
  bool busy = false, closed = false, failed = false;
  String status = 'loading';
  bool get canAct => !closed && !busy && !failed && saved != null;

  Future<void> load() => _run('read', port.read);
  Future<void> choose() async {
    if (canAct) await _run('choose', () => port.choose(saved!));
  }

  Future<void> reset() async {
    if (canAct) await _run('reset', () => port.reset(saved!));
  }

  Future<void> open() async {
    if (canAct) await _run('open', () => port.open(saved!));
  }

  Future<void> _run(
    String action,
    Future<MenuScreenshotDirectory> Function() work,
  ) async {
    if (closed || busy) return;
    busy = true;
    failed = false;
    status = action == 'choose' ? 'choosing' : 'busy';
    notifyListeners();
    try {
      final value = await work();
      if (closed) return;
      saved = value;
      status = value.cancelled
          ? 'cancelled'
          : value.opened
          ? 'opened'
          : action == 'choose' || action == 'reset'
          ? 'changed'
          : 'ready';
    } on Object catch (error) {
      if (closed) return;
      failed = true;
      status =
          error is BridgeClientException &&
              error.code == 'menuScreenshotDirectory.revision_conflict'
          ? 'conflict'
          : '${action}Failed';
      // Retain the last confirmed path for display only. No action may use it
      // until an explicit successful read clears the unknown outcome.
    } finally {
      if (!closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    closed = true;
    saved = null;
    super.dispose();
  }
}
