import 'package:flutter/services.dart';

import '../../features/tools/exec_hangar_port.dart';
import 'menu_bridge_relay.dart';
import 'menu_browser_resume.dart';
import 'menu_browser_resume_request.dart';
import 'menu_exec_hangar_summary.dart';

/// Menu requests that need only the current opening's fence and their own port.
/// Returns null for a method none of them accepts.
Future<Object?>? routeMenuWindowRequest(
  MethodCall call, {
  required int? opening,
  required bool Function() isCurrent,
  required ExecHangarPort? Function()? execHangar,
  required void Function() openExecHangar,
  required MenuBrowserResumePort? Function() browserResume,
  required MenuBridgeRelay? relay,
}) {
  if (MenuBridgeRelay.accepts(call.method)) {
    if (relay == null) throw PlatformException(code: 'menu.closed');
    return relay.handle(call.arguments, opening: opening, isCurrent: isCurrent);
  }
  if (MenuExecHangarRequest.accepts(call.method)) {
    return MenuExecHangarRequest.handle(
      method: call.method,
      arguments: call.arguments,
      opening: opening,
      isCurrent: isCurrent,
      port: execHangar?.call(),
      openTool: openExecHangar,
    );
  }
  if (call.method == 'browserResume') {
    return MenuBrowserResumeRequest.handle(
      arguments: call.arguments,
      opening: opening,
      isCurrent: isCurrent,
      port: browserResume(),
    );
  }
  return null;
}
