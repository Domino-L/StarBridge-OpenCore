import 'package:flutter/foundation.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';

/// Test-only original-mode observations, never a product account authority.
class ImageMode extends ChangeNotifier implements ConnectionModeControl {
  ImageMode({this.scope = 7});
  Object scope;
  ConnectionModeState state = ConnectionModeState.online;
  @override
  bool busy = false;
  @override
  bool failed = false;
  @override
  ConnectionModeSnapshot get snapshot => ConnectionModeSnapshot(
    scope: scope,
    revision: 1,
    state: state,
    canEnterOffline: state == ConnectionModeState.online,
  );
  @override
  bool get allowsOnlineTraffic =>
      !busy && !failed && state == ConnectionModeState.online;
  @override
  bool get canEnterOffline => allowsOnlineTraffic;
  void change(ConnectionModeState next) {
    state = next;
    notifyListeners();
  }

  @override
  Future<bool> enterOffline() async {
    change(ConnectionModeState.offline);
    return true;
  }
}
