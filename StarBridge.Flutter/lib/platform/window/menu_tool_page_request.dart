import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Fixed client pages the menu may hand the user to. The menu names the page
/// by method, never by route; the runtime host maps each one to navigation.
/// Unlike the hangar there is no capability flag: these pages always exist.
final class MenuToolPageRequests {
  /// Method → the client route it opens. Fixed; the menu sends no route.
  static const routes = {
    'openHudSettings': '/overlay',
    'openFleetPage': '/fleet',
    'openCommunitiesPage': '/communities',
  };
  static const _methods = {
    'openHudSettings',
    'openFleetPage',
    'openCommunitiesPage',
  };
  final hudSettings = ValueNotifier<int>(0);

  /// The last page asked for, with a serial so asking twice navigates twice.
  final requested = ValueNotifier<(String, int)?>(null);
  int _serial = 0;

  bool accepts(String method) => _methods.contains(method);

  /// Native hides the menu and raises the client only after this returns true.
  bool handle(MethodCall call, int? opening, bool Function() isCurrent) {
    final arguments = call.arguments;
    if (!_methods.contains(call.method) ||
        !isCurrent() ||
        opening == null ||
        arguments is! Map ||
        arguments.length != 1 ||
        arguments['opening'] != opening) {
      throw PlatformException(code: 'menuToolPage.session_unavailable');
    }
    if (call.method == 'openHudSettings') hudSettings.value++;
    requested.value = (routes[call.method]!, ++_serial);
    return true;
  }
}
