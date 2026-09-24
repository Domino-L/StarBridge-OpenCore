import 'dart:ui';

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
