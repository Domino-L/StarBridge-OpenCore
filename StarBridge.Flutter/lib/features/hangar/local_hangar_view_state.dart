/// Session-local numeric presentation only: no Widget, controller or authority.
final class LocalHangarViewState {
  String query = '', sort = 'saved';
  String? size, category, status;
  bool former = false, favoritesOnly = false, grid = true;
  double scrollOffset = 0;
}

abstract interface class LocalHangarViewSource {
  LocalHangarViewState get view;
  int get viewEpoch;
}
