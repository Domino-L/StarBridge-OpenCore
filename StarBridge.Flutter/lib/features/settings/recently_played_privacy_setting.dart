import 'package:flutter/material.dart';

import 'authoritative_privacy_setting.dart';
import 'recently_played_privacy_module.dart';

class RecentlyPlayedPrivacySetting extends StatelessWidget {
  const RecentlyPlayedPrivacySetting({this.module, super.key});

  final RecentlyPlayedPrivacyModule? module;

  @override
  Widget build(BuildContext context) {
    final value = module;
    if (value == null) return _setting();
    return ValueListenableBuilder<RecentlyPlayedPrivacyProjection>(
      valueListenable: value.projection,
      builder: (context, projection, _) => _setting(
        projection: projection,
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
    return AuthoritativePrivacySetting(
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
          : _failureText(
              availability == RecentlyPlayedPrivacyAvailability.signedOut,
              projection.failure ?? snapshot?.failure,
            ),
      loadingKey: const Key('recently-played-privacy-loading'),
      savingKey: const Key('recently-played-privacy-saving'),
      onChanged: onChanged ?? (_) async => false,
      onRetry: availability == RecentlyPlayedPrivacyAvailability.unavailable
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
