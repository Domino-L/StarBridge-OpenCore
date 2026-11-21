import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'authoritative_privacy_setting.dart';
import 'recently_played_privacy_module.dart';

class RecentlyPlayedPrivacySetting extends StatefulWidget {
  const RecentlyPlayedPrivacySetting({this.module, this.scmOnly, super.key});

  final RecentlyPlayedPrivacyModule? module;

  /// True while a SCM account without a linked legacy account cannot use this
  /// setting yet (the relay does not offer the account migration).
  final ValueListenable<bool>? scmOnly;

  @override
  State<RecentlyPlayedPrivacySetting> createState() =>
      _RecentlyPlayedPrivacySettingState();
}

class _RecentlyPlayedPrivacySettingState
    extends State<RecentlyPlayedPrivacySetting> {
  ValueListenable<bool>? _listened;
  bool _blocked = false;

  RecentlyPlayedPrivacyModule? get module => widget.module;
  ValueListenable<bool>? get scmOnly => widget.scmOnly;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(RecentlyPlayedPrivacySetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scmOnly, widget.scmOnly)) _listen();
  }

  void _listen() {
    _listened?.removeListener(_scmOnlyChanged);
    _listened = widget.scmOnly?..addListener(_scmOnlyChanged);
    _blocked = widget.scmOnly?.value == true;
  }

  // Once the relay opens this setting to SCM-only accounts, read it again
  // instead of leaving the earlier identity refusal on screen.
  void _scmOnlyChanged() {
    final blocked = widget.scmOnly?.value == true;
    final opened = _blocked && !blocked;
    _blocked = blocked;
    final value = widget.module;
    if (!opened || value == null) return;
    final projection = value.projection.value;
    if ((projection.failure ?? projection.snapshot.failure) ==
        RecentlyPlayedPrivacyFailure.identityUnavailable) {
      value.refresh();
    }
  }

  @override
  void dispose() {
    _listened?.removeListener(_scmOnlyChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = module;
    if (value == null) return _setting();
    final scm = scmOnly;
    return ListenableBuilder(
      listenable: scm == null
          ? value.projection
          : Listenable.merge([value.projection, scm]),
      builder: (context, _) => _setting(
        projection: value.projection.value,
        onChanged: value.save,
        onRetry: value.refresh,
      ),
    );
  }

  Widget _setting({
    RecentlyPlayedPrivacyProjection? projection,
    Future<bool> Function(bool)? onChanged,
    Future<void> Function()? onRetry,
  }) {
    final snapshot = projection?.snapshot;
    final availability = snapshot?.availability;
    final scmOnlyFailure =
        scmOnly?.value == true &&
        (projection?.failure ?? snapshot?.failure) ==
            RecentlyPlayedPrivacyFailure.identityUnavailable;
    return AuthoritativePrivacySetting(
      presentationChanges: module?.projection,
      settingKey: const Key('privacy-recently-played-authoritative'),
      titleKey: 'settings.privacy.social.recentlyPlayed',
      descriptionKey: 'settings.privacy.social.recentlyPlayedDescription',
      value: availability == RecentlyPlayedPrivacyAvailability.available
          ? snapshot?.enabled
          : null,
      enabled: projection?.canEdit ?? false,
      loading: availability == RecentlyPlayedPrivacyAvailability.loading,
      saving: projection?.operation == RecentlyPlayedPrivacyOperation.saving,
      statusKey: projection == null
          ? 'settings.privacy.recentlyPlayed.unavailable'
          : scmOnlyFailure
          ? 'settings.privacy.recentlyPlayed.scmOnly'
          : _failureText(
              availability == RecentlyPlayedPrivacyAvailability.signedOut,
              projection.failure ?? snapshot?.failure,
            ),
      loadingKey: const Key('recently-played-privacy-loading'),
      savingKey: const Key('recently-played-privacy-saving'),
      onChanged: onChanged ?? (_) async => false,
      onRetry:
          availability == RecentlyPlayedPrivacyAvailability.unavailable &&
              !scmOnlyFailure
          ? onRetry
          : null,
    );
  }
}

String _failureText(bool signedOut, RecentlyPlayedPrivacyFailure? failure) {
  if (signedOut) return 'settings.privacy.recentlyPlayed.signedOut';
  if (failure == null) return '';
  return switch (failure) {
    RecentlyPlayedPrivacyFailure.identityUnavailable =>
      'settings.privacy.recentlyPlayed.identityUnavailable',
    RecentlyPlayedPrivacyFailure.outcomeUnknown =>
      'settings.privacy.recentlyPlayed.outcomeUnknown',
    RecentlyPlayedPrivacyFailure.writeConflict =>
      'settings.privacy.recentlyPlayed.writeConflict',
    RecentlyPlayedPrivacyFailure.invalidResponse =>
      'settings.privacy.recentlyPlayed.invalidResponse',
    RecentlyPlayedPrivacyFailure.writeFailed =>
      'settings.privacy.recentlyPlayed.writeFailed',
    _ => 'settings.privacy.recentlyPlayed.unavailable',
  };
}
