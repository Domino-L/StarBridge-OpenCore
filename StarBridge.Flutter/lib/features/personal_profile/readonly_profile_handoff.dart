import 'package:flutter/foundation.dart';

import 'personal_profile_models.dart';
import 'personal_profile_module.dart';

/// Materialized cached presentation only. No port, invalidation subscription,
/// account context, private controller or edit lease survives in this object.
final class ReadonlyProfileHandoff
    extends ValueNotifier<PersonalProfileProjection>
    implements PersonalProfileModule {
  ReadonlyProfileHandoff(PersonalProfileProjection display, {this.onRefresh})
    : super(
        display.copyWith(
          allowEditing: false,
          operation: PersonalProfileOperation.refreshing,
        ),
      );
  final Future<PersonalProfileActionResult> Function()? onRefresh;
  bool _closed = false;

  void withdraw(String failureKey) {
    if (_closed) return;
    value = PersonalProfileProjection.fromSnapshot(
      PersonalProfileSnapshot.unavailable(failureKey: failureKey),
    );
  }

  void capture(PersonalProfileProjection display) {
    if (_closed) return;
    value = display.copyWith(
      allowEditing: false,
      operation: PersonalProfileOperation.refreshing,
    );
  }

  void observe({required bool waiting, String? failureKey}) {
    if (_closed) return;
    final operation = waiting
        ? PersonalProfileOperation.refreshing
        : PersonalProfileOperation.none;
    if (value.operation == operation &&
        value.refreshFailed == !waiting &&
        value.failureKey == failureKey) {
      return;
    }
    value = value.copyWith(
      operation: operation,
      allowEditing: false,
      refreshFailed: !waiting,
      failureKey: failureKey,
      clearFailure: waiting,
    );
  }

  @override
  ValueListenable<PersonalProfileProjection> get projection => this;
  @override
  Future<PersonalProfileActionResult> initialize() async =>
      const PersonalProfileActionResult(PersonalProfileActionOutcome.completed);
  @override
  Future<PersonalProfileActionResult> refresh() async {
    if (_closed ||
        value.operation != PersonalProfileOperation.none ||
        (!value.refreshFailed &&
            value.availability != PersonalProfileAvailability.unavailable) ||
        onRefresh == null) {
      return const PersonalProfileActionResult(
        PersonalProfileActionOutcome.rejected,
      );
    }
    return onRefresh!();
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) async =>
      const PersonalProfileActionResult(PersonalProfileActionOutcome.rejected);
  @override
  void renameCommunity(String code, String name) {}
  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
