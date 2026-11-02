import 'dart:async';

import 'package:flutter/foundation.dart';

import 'onboarding_profile_port.dart';

enum OnboardingProfileLoad { idle, loading, absent, ready, failed }

@immutable
final class OnboardingProfileView {
  const OnboardingProfileView({
    this.load = OnboardingProfileLoad.idle,
    this.snapshot,
    this.draft = '',
    this.saving = false,
    this.saved = false,
    this.failureKey,
    this.rsiFailed = false,
    this.resultsExpanded = false,
  });
  final OnboardingProfileLoad load;
  final OnboardingProfileSnapshot? snapshot;
  final String draft;
  final bool saving, saved, rsiFailed, resultsExpanded;

  /// Copy key for the last unconfirmed rename; cleared by the next edit.
  final String? failureKey;

  bool get visible => load == OnboardingProfileLoad.ready && snapshot != null;
  bool get dirty => snapshot != null && draft.trim() != snapshot!.callSign;
  bool get canSave =>
      visible &&
      snapshot!.canRename &&
      !saving &&
      dirty &&
      validOnboardingCallSign(draft.trim());

  OnboardingProfileView copyWith({
    OnboardingProfileLoad? load,
    OnboardingProfileSnapshot? snapshot,
    String? draft,
    bool? saving,
    bool? saved,
    String? failureKey,
    bool clearFailure = false,
    bool? rsiFailed,
    bool? resultsExpanded,
  }) => OnboardingProfileView(
    load: load ?? this.load,
    snapshot: snapshot ?? this.snapshot,
    draft: draft ?? this.draft,
    saving: saving ?? this.saving,
    saved: saved ?? this.saved,
    failureKey: clearFailure ? null : failureKey ?? this.failureKey,
    rsiFailed: rsiFailed ?? this.rsiFailed,
    resultsExpanded: resultsExpanded ?? this.resultsExpanded,
  );
}

/// Optional "你的资料" panel on the completed online finish page. It reads the
/// account only after setup was saved, never renames on its own, and leaving
/// with an unsaved draft keeps the current nickname.
final class OnboardingProfileController
    extends ValueNotifier<OnboardingProfileView> {
  OnboardingProfileController(this.port)
    : super(const OnboardingProfileView()) {
    _invalidations = port.invalidations.listen((_) {
      if (value.load != OnboardingProfileLoad.idle && !value.saving) {
        unawaited(_read());
      }
    });
  }
  final OnboardingProfilePort port;
  late final StreamSubscription<void> _invalidations;
  bool _disposed = false;
  int _epoch = 0;

  /// Starts reading once; later calls are no-ops.
  Future<void> activate() async {
    if (_disposed || value.load != OnboardingProfileLoad.idle) return;
    await _read();
  }

  Future<void> retry() => _read();

  Future<void> _read() async {
    final epoch = ++_epoch;
    value = value.copyWith(load: OnboardingProfileLoad.loading);
    try {
      final snapshot = await port.read();
      if (_disposed || epoch != _epoch) return;
      if (snapshot == null) {
        value = value.copyWith(load: OnboardingProfileLoad.absent);
        return;
      }
      // Keep what the user typed; only replace an untouched draft.
      final keep = value.snapshot != null && value.dirty;
      value = value.copyWith(
        load: OnboardingProfileLoad.ready,
        snapshot: snapshot,
        draft: keep ? value.draft : snapshot.callSign,
      );
    } on Object {
      if (_disposed || epoch != _epoch) return;
      value = value.copyWith(load: OnboardingProfileLoad.failed);
    }
  }

  void edit(String draft) {
    if (_disposed || value.saving) return;
    value = value.copyWith(draft: draft, saved: false, clearFailure: true);
  }

  Future<void> save() async {
    if (_disposed || !value.canSave) return;
    final snapshot = value.snapshot!;
    final next = value.draft.trim();
    value = value.copyWith(saving: true, saved: false, clearFailure: true);
    try {
      final confirmed = await port.saveCallSign(snapshot.callSign, next);
      if (_disposed) return;
      value = value.copyWith(
        saving: false,
        saved: true,
        draft: confirmed,
        snapshot: OnboardingProfileSnapshot(
          callSign: confirmed,
          avatarImageData: snapshot.avatarImageData,
          canRename: snapshot.canRename,
          canOpenRsi: snapshot.canOpenRsi,
        ),
      );
    } on OnboardingProfileSaveException catch (error) {
      if (_disposed) return;
      value = value.copyWith(saving: false, failureKey: error.key);
      // Never resend; reread the real name so the next attempt is explicit.
      if (error.conflict) await _read();
    } on Object {
      if (_disposed) return;
      value = value.copyWith(saving: false, failureKey: 'profile.save.failed');
    }
  }

  Future<void> openRsi() async {
    if (_disposed) return;
    value = value.copyWith(rsiFailed: false);
    try {
      await port.openRsiProfile();
    } on Object {
      if (!_disposed) value = value.copyWith(rsiFailed: true);
    }
  }

  void toggleResults() =>
      value = value.copyWith(resultsExpanded: !value.resultsExpanded);

  @override
  void dispose() {
    _disposed = true;
    unawaited(_invalidations.cancel());
    super.dispose();
  }
}
