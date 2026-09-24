import 'package:flutter/foundation.dart';

@immutable
final class ApplicationWindowBehavior {
  const ApplicationWindowBehavior({
    required this.keepRunningInBackground,
    required this.startMinimized,
  });

  final bool keepRunningInBackground;
  final bool startMinimized;
}

abstract interface class ApplicationLifecyclePort {
  Stream<void> get closeRequests;

  Future<void> configure(ApplicationWindowBehavior behavior);

  Future<void> hideToTray({required bool showHint});

  Future<void> exitApplication();

  Future<void> cancelCloseRequest();

  void dispose();
}
