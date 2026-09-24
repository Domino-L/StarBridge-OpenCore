import 'dart:async';

import 'application_lifecycle_port.dart';

final class InMemoryApplicationLifecycle implements ApplicationLifecyclePort {
  final StreamController<void> _closeRequests =
      StreamController<void>.broadcast(sync: true);

  ApplicationWindowBehavior? behavior;
  int hideCount = 0;
  int exitCount = 0;
  int cancelledCloseCount = 0;
  bool? lastShowHint;

  @override
  Stream<void> get closeRequests => _closeRequests.stream;

  void requestClose() => _closeRequests.add(null);

  @override
  Future<void> configure(ApplicationWindowBehavior behavior) async {
    this.behavior = behavior;
  }

  @override
  Future<void> hideToTray({required bool showHint}) async {
    hideCount++;
    lastShowHint = showHint;
  }

  @override
  Future<void> exitApplication() async {
    exitCount++;
  }

  @override
  Future<void> cancelCloseRequest() async {
    cancelledCloseCount++;
  }

  @override
  void dispose() {
    unawaited(_closeRequests.close());
  }
}
