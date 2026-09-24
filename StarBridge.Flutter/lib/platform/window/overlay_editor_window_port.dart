abstract interface class OverlayEditorWindowPort {
  Future<void> enter();
  Future<void> exit();
}

final class UnavailableOverlayEditorWindow implements OverlayEditorWindowPort {
  const UnavailableOverlayEditorWindow();

  @override
  Future<void> enter() => Future.error(StateError('editor.window_unavailable'));

  @override
  Future<void> exit() async {}
}
