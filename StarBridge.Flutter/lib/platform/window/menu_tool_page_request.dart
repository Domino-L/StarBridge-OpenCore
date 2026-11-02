import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Fixed client pages the menu may hand the user to. The menu names the page
/// by method, never by route; the runtime host maps each one to navigation.
/// Unlike the hangar there is no capability flag: these pages always exist.
final class MenuToolPageRequests {
  static const _methods = {'openHudSettings'};
  final hudSettings = ValueNotifier<int>(0);

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
    hudSettings.value++;
    return true;
  }
}
