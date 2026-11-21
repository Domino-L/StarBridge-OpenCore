import 'package:flutter/foundation.dart';

/// A yes or no that is read again whenever [source] changes, and tells its
/// listeners only when the answer actually changes. Used where an entry must
/// appear or disappear as the account state is confirmed after startup.
final class ComputedFlag extends ChangeNotifier
    implements ValueListenable<bool> {
  ComputedFlag(this._source, this._read) : _value = _read() {
    _source.addListener(_changed);
  }

  final Listenable _source;
  final bool Function() _read;
  bool _value;

  void _changed() {
    final next = _read();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  bool get value => _value;

  @override
  void dispose() {
    _source.removeListener(_changed);
    super.dispose();
  }
}
