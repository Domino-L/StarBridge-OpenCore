import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import 'friends_module.dart';

/// Read-only presentation provenance. Never starts, cancels or changes an
/// operation. Sharing by owner preserves an in-flight source across view visits.
final class FriendsOperationMotion {
  FriendsOperationMotion._(this._module)
    : _reading = _module.reading,
      _busy = _module.busy,
      _revision = _module.accountRevision {
    _module.addListener(_observe);
  }

  static final _bindings = Expando<FriendsOperationMotion>();
  static FriendsOperationMotion retain(FriendsModule module) {
    final binding = _bindings[module] ??= FriendsOperationMotion._(module);
    binding._clients++;
    return binding;
  }

  final FriendsModule _module;
  int _clients = 0;
  bool _closed = false;
  bool _reading, _busy;
  int _revision;
  InteractionSource _readSource = InteractionSource.programmatic;
  InteractionSource _commandSource = InteractionSource.programmatic;

  InteractionSource get readSource =>
      _module.reading ? _readSource : InteractionSource.programmatic;
  InteractionSource get commandSource =>
      _module.busy ? _commandSource : InteractionSource.programmatic;

  void _observe() {
    if (_closed) return;
    final reading = _module.reading, busy = _module.busy;
    if (_revision != _module.accountRevision) {
      _revision = _module.accountRevision;
      _readSource = _commandSource = InteractionSource.programmatic;
    } else {
      // Capture a value, not a lease getter that expires when a void UI
      // callback returns. Duplicate/no-op calls cannot relabel a pending read.
      final source = captureStarBridgeActivationSource()();
      if (reading && !_reading) _readSource = source;
      if (busy && !_busy) _commandSource = source;
    }
    _reading = reading;
    _busy = busy;
    if (_clients == 0 && !reading && !busy) _detach();
  }

  void release({bool ownerDisposing = false}) {
    assert(_clients > 0);
    _clients--;
    if (ownerDisposing || _clients == 0 && !_module.reading && !_module.busy) {
      _detach();
    }
  }

  void _detach() {
    if (_closed) return;
    _closed = true;
    _module.removeListener(_observe);
    if (identical(_bindings[_module], this)) _bindings[_module] = null;
  }
}
