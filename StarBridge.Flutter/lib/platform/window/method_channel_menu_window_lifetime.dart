import 'package:flutter/foundation.dart';

import '../bridge/bridge_client_session.dart';
import 'method_channel_menu_preview_window.dart';
import 'taskbar_attention_binding.dart';
import 'menu_recovery_lifecycle.dart';
import 'menu_startup_lifecycle.dart';
import 'menu_image_retirement.dart';
import 'menu_tool_page_request.dart';

import 'package:flutter/services.dart';

/// Owned by the primary application runtime and shared by its compositions.
/// Contains no account data; a replaced composition cannot clear the next one.
final class MenuWindowLifetime {
  final taskbarAttentionScope = TaskbarAttentionScope();
  MethodChannelMenuPreviewWindow? owner;
  int _nextRequest = 0;
  final recovery = MenuRecoveryLifecycle();
  int nextRequest() => ++_nextRequest;
  int _imageEpoch = 0;
  int get imageEpoch => _imageEpoch;
  int nextImageEpoch() => ++_imageEpoch;
  MenuImageRetirement imagesFor(Object owner, int? Function() request) =>
      MenuImageRetirement(
        this,
        const MethodChannel('starbridge/menu-primary'),
        isCurrent: () => identical(this.owner, owner),
        request: request,
      );
  final startup = MenuStartupLifecycle();
  final execHangarRequests = ValueNotifier<int>(0);
  final toolPages = MenuToolPageRequests();
  Future<void> prepareStartup(BridgeClientSession session) =>
      startup.prepare(session);

  /// Explicit normal application exit only, never hide, logout or disposal.
  Future<void> completeExit() async {
    try {
      if (owner != null && !await owner!.flushPreferencesForExit()) return;
      await recovery.finish();
    } on Object {
      // A failed flush/confirmation remains interrupted. Do not block exit.
    }
  }
}
