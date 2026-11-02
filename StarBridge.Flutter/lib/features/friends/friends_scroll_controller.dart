import 'package:flutter/widgets.dart';

import 'friends_module.dart';

/// A route borrows numeric viewport state from the directory session. Widgets
/// and ScrollPositions themselves are never retained by that session.
final class FriendsScrollController extends ScrollController {
  FriendsScrollController(this.module)
    : _epoch = module.viewEpoch,
      super(initialScrollOffset: module.scrollOffset) {
    addListener(_remember);
    module.addListener(_changed);
  }
  final FriendsModule module;
  int _epoch;
  bool _closed = false, _restorePending = false, _queued = false;

  void _remember() {
    if (!_restorePending && hasClients) {
      module.rememberScroll(offset, expectedEpoch: _epoch);
    }
  }

  void _changed() {
    if (_closed) return;
    if (_epoch != module.viewEpoch) {
      _epoch = module.viewEpoch;
      _restorePending = true;
    }
    if (!_restorePending || _queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (_closed || !hasClients) return;
      jumpTo(module.scrollOffset.clamp(0.0, position.maxScrollExtent));
      _restorePending = false;
      _remember();
    });
  }

  @override
  void dispose() {
    _remember();
    _closed = true;
    module.removeListener(_changed);
    super.dispose();
  }
}
