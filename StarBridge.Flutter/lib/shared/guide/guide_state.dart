import 'package:flutter/foundation.dart';

/// Per-profile guide memory kept by Host (`guide.state.v1`). Teaching only:
/// nothing here grants, changes or triggers any product action.
@immutable
final class GuideState {
  const GuideState({
    this.available = false,
    this.eligible = false,
    this.seen = const {},
    this.collapsed = false,
    this.dismissed = false,
    this.celebrated = false,
    this.done = const {},
  });

  static const unavailable = GuideState();

  final bool available;

  /// Finished the current first-use setup; only these profiles get the home
  /// checklist and automatic tours.
  final bool eligible;
  final Set<String> seen;
  final bool collapsed;
  final bool dismissed;
  final bool celebrated;
  final Set<String> done;

  GuideState apply(GuideOp op) => switch (op) {
    _MarkSeen(:final id) => _copy(seen: {...seen, id}),
    _ResetSeen() => _copy(seen: const {}),
    _MarkEligible() => _copy(eligible: true),
    _MarkDone(:final id) => _copy(done: {...done, id}),
    _SetChecklist() => _copy(
      collapsed: op.collapsed ?? collapsed,
      dismissed: op.dismissed ?? dismissed,
      celebrated: op.celebrated ?? celebrated,
    ),
    _ResetChecklist() => _copy(
      collapsed: false,
      dismissed: false,
      celebrated: false,
    ),
  };

  GuideState _copy({
    bool? eligible,
    Set<String>? seen,
    bool? collapsed,
    bool? dismissed,
    bool? celebrated,
    Set<String>? done,
  }) => GuideState(
    available: available,
    eligible: eligible ?? this.eligible,
    seen: seen ?? this.seen,
    collapsed: collapsed ?? this.collapsed,
    dismissed: dismissed ?? this.dismissed,
    celebrated: celebrated ?? this.celebrated,
    done: done ?? this.done,
  );

  @override
  bool operator ==(Object other) =>
      other is GuideState &&
      other.available == available &&
      other.eligible == eligible &&
      setEquals(other.seen, seen) &&
      other.collapsed == collapsed &&
      other.dismissed == dismissed &&
      other.celebrated == celebrated &&
      setEquals(other.done, done);

  @override
  int get hashCode => Object.hash(
    available,
    eligible,
    Object.hashAllUnordered(seen),
    collapsed,
    dismissed,
    celebrated,
    Object.hashAllUnordered(done),
  );
}

final _id = RegExp(r'^[a-z][a-z0-9.-]{0,47}$');

/// Idempotent edits; Host applies them in order and saves atomically.
sealed class GuideOp {
  const GuideOp();
  factory GuideOp.markSeen(String id) = _MarkSeen;
  const factory GuideOp.resetSeen() = _ResetSeen;
  const factory GuideOp.markEligible() = _MarkEligible;
  factory GuideOp.markDone(String id) = _MarkDone;
  const factory GuideOp.setChecklist({
    bool? collapsed,
    bool? dismissed,
    bool? celebrated,
  }) = _SetChecklist;
  const factory GuideOp.resetChecklist() = _ResetChecklist;

  Map<String, Object?> toWire();
}

final class _MarkSeen extends GuideOp {
  _MarkSeen(this.id) : assert(_id.hasMatch(id));
  final String id;
  @override
  Map<String, Object?> toWire() => {'op': 'markSeen', 'id': id};
}

final class _ResetSeen extends GuideOp {
  const _ResetSeen();
  @override
  Map<String, Object?> toWire() => const {'op': 'resetSeen'};
}

final class _MarkEligible extends GuideOp {
  const _MarkEligible();
  @override
  Map<String, Object?> toWire() => const {'op': 'markEligible'};
}

final class _MarkDone extends GuideOp {
  _MarkDone(this.id) : assert(_id.hasMatch(id));
  final String id;
  @override
  Map<String, Object?> toWire() => {'op': 'markDone', 'id': id};
}

final class _SetChecklist extends GuideOp {
  const _SetChecklist({this.collapsed, this.dismissed, this.celebrated});
  final bool? collapsed;
  final bool? dismissed;
  final bool? celebrated;
  @override
  Map<String, Object?> toWire() => {
    'op': 'setChecklist',
    'collapsed': ?collapsed,
    'dismissed': ?dismissed,
    'celebrated': ?celebrated,
  };
}

final class _ResetChecklist extends GuideOp {
  const _ResetChecklist();
  @override
  Map<String, Object?> toWire() => const {'op': 'resetChecklist'};
}

abstract interface class GuideStatePort {
  bool get supported;
  Future<GuideState> read();
  Future<GuideState> update(List<GuideOp> ops);
}

/// Fail-closed decoder for the Host projection.
GuideState parseGuideState(Map<String, Object?> raw) {
  if (raw['schemaVersion'] != 1) throw const FormatException();
  final state = raw['state'];
  if (state == 'unavailable') return GuideState.unavailable;
  if (state != 'ready') throw const FormatException();
  Set<String> ids(Object? value, int max) {
    if (value is! List || value.length > max) throw const FormatException();
    return {
      for (final id in value)
        if (id is String && _id.hasMatch(id))
          id
        else
          throw const FormatException(),
    };
  }

  bool flag(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is! bool) throw const FormatException();
    return value;
  }

  final checklist = raw['checklist'];
  final eligible = raw['eligible'];
  if (checklist is! Map || eligible is! bool) throw const FormatException();
  return GuideState(
    available: true,
    eligible: eligible,
    seen: ids(raw['seen'], 64),
    collapsed: flag(checklist, 'collapsed'),
    dismissed: flag(checklist, 'dismissed'),
    celebrated: flag(checklist, 'celebrated'),
    done: ids(checklist['done'], 16),
  );
}
