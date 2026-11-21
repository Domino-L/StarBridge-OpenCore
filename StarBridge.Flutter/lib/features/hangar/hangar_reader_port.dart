import 'dart:ui';

/// [uncleared]: a clear did not finish, so RSI sign-in data may remain.
/// [unknown]: the saved choice could not be read; nothing is cleared until it
/// is read or set again.
typedef HangarSignIn = ({bool remember, bool uncleared, bool unknown});

abstract interface class HangarBrowserPort {
  Future<void> open({required String profileKey});
  Future<Map<String, Object?>> lock();
  Future<void> unlock();
  Future<void> page(int page);
  Future<Map<String, Object?>> capture();
  Future<void> bounds(Rect rect, {required bool visible});
  Future<void> focus();
  void setFocusExitHandler(void Function(bool previous)? handler);
  Future<void> close();
  Future<void> clearData();

  /// Whether the RSI sign-in is remembered on this computer, and whether a
  /// clear failed. Native keeps both; not remembering is the default.
  Future<HangarSignIn> readSignIn();

  /// Closes any open page. Not remembering also clears the sign-in data.
  /// When saving the choice fails, nothing changes and the page stays open.
  Future<void> setRemember(bool remember);
}

abstract interface class HangarPreviewPort {
  Future<String> prepare();
  Future<Map<String, Object?>> begin();
  Future<Map<String, Object?>> verify(Map<String, Object?> observation);
  Future<Map<String, Object?>> observe(Map<String, Object?> observation);
  Future<void> cancel();
}

class HangarReaderFailure implements Exception {
  const HangarReaderFailure(this.code);
  final String code;
}
