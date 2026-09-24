import 'package:flutter/foundation.dart';

enum OverlaySettingsAvailability { loading, unavailable, available }

enum OverlaySettingsOperation { none, saving }

enum OverlaySettingsFailure {
  hostUnavailable,
  readFailed,
  writeFailed,
  writeConflict,
  invalidValue,
  invalidResponse,
}

enum OverlaySettingsPosition { topLeft, topRight, bottomLeft, bottomRight }

@immutable
final class OverlaySettingsValue {
  const OverlaySettingsValue({
    required this.enabled,
    required this.opacity,
    required this.position,
    required this.showTeam,
  });

  static const defaults = OverlaySettingsValue(
    enabled: true,
    opacity: 0.85,
    position: OverlaySettingsPosition.topRight,
    showTeam: true,
  );

  final bool enabled;
  final double opacity;
  final OverlaySettingsPosition position;
  final bool showTeam;

  OverlaySettingsValue copyWith({
    bool? enabled,
    double? opacity,
    OverlaySettingsPosition? position,
    bool? showTeam,
  }) => OverlaySettingsValue(
    enabled: enabled ?? this.enabled,
    opacity: opacity ?? this.opacity,
    position: position ?? this.position,
    showTeam: showTeam ?? this.showTeam,
  );
}

@immutable
final class OverlaySettingsSnapshot {
  const OverlaySettingsSnapshot._({
    required this.availability,
    this.revision,
    this.settings,
    this.windowAvailable = false,
    this.failure,
    this.allowEditing = false,
  });

  const OverlaySettingsSnapshot.loading()
    : this._(availability: OverlaySettingsAvailability.loading);

  const OverlaySettingsSnapshot.unavailable({
    OverlaySettingsFailure failure = OverlaySettingsFailure.hostUnavailable,
  }) : this._(
         availability: OverlaySettingsAvailability.unavailable,
         failure: failure,
       );

  const OverlaySettingsSnapshot.available({
    required int revision,
    required OverlaySettingsValue settings,
    required bool windowAvailable,
    bool allowEditing = true,
  }) : this._(
         availability: OverlaySettingsAvailability.available,
         revision: revision,
         settings: settings,
         windowAvailable: windowAvailable,
         allowEditing: allowEditing,
       );

  final OverlaySettingsAvailability availability;
  final int? revision;
  final OverlaySettingsValue? settings;
  final bool windowAvailable;
  final OverlaySettingsFailure? failure;
  final bool allowEditing;
}

@immutable
final class OverlaySettingsWriteResult {
  const OverlaySettingsWriteResult.completed(this.snapshot) : failure = null;
  const OverlaySettingsWriteResult.failed(this.failure) : snapshot = null;

  final OverlaySettingsSnapshot? snapshot;
  final OverlaySettingsFailure? failure;
  bool get completed => snapshot != null;
}

@immutable
final class OverlaySettingsProjection {
  const OverlaySettingsProjection({
    required this.availability,
    required this.operation,
    this.revision,
    this.settings,
    this.windowAvailable = false,
    this.failure,
    this.allowEditing = false,
  });

  const OverlaySettingsProjection.loading()
    : this(
        availability: OverlaySettingsAvailability.loading,
        operation: OverlaySettingsOperation.none,
      );

  factory OverlaySettingsProjection.fromSnapshot(
    OverlaySettingsSnapshot snapshot,
  ) => OverlaySettingsProjection(
    availability: snapshot.availability,
    operation: OverlaySettingsOperation.none,
    revision: snapshot.revision,
    settings: snapshot.settings,
    windowAvailable: snapshot.windowAvailable,
    failure: snapshot.failure,
    allowEditing: snapshot.allowEditing,
  );

  final OverlaySettingsAvailability availability;
  final OverlaySettingsOperation operation;
  final int? revision;
  final OverlaySettingsValue? settings;
  final bool windowAvailable;
  final OverlaySettingsFailure? failure;
  final bool allowEditing;

  bool get canEdit =>
      availability == OverlaySettingsAvailability.available &&
      operation == OverlaySettingsOperation.none &&
      allowEditing &&
      settings != null &&
      revision != null;

  OverlaySettingsProjection copyWith({
    OverlaySettingsOperation? operation,
    OverlaySettingsFailure? failure,
    bool clearFailure = false,
  }) => OverlaySettingsProjection(
    availability: availability,
    operation: operation ?? this.operation,
    revision: revision,
    settings: settings,
    windowAvailable: windowAvailable,
    failure: clearFailure ? null : failure ?? this.failure,
    allowEditing: allowEditing,
  );
}
