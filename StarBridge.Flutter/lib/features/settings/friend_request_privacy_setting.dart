import 'package:flutter/material.dart';

import 'authoritative_privacy_setting.dart';
import 'friend_request_privacy_module.dart';

class FriendRequestPrivacySetting extends StatelessWidget {
  const FriendRequestPrivacySetting({this.module, super.key});

  final FriendRequestPrivacyModule? module;

  @override
  Widget build(BuildContext context) {
    final value = module;
    if (value == null) return _setting();
    return ValueListenableBuilder<FriendRequestPrivacyProjection>(
      valueListenable: value.projection,
      builder: (context, projection, _) => _setting(
        projection: projection,
        onChanged: value.save,
        onRetry: value.refresh,
      ),
    );
  }

  Widget _setting({
    FriendRequestPrivacyProjection? projection,
    Future<bool> Function(bool)? onChanged,
    Future<void> Function()? onRetry,
  }) {
    final snapshot = projection?.snapshot;
    final availability = snapshot?.availability;
    return AuthoritativePrivacySetting(
      settingKey: const Key('privacy-friend-requests-authoritative'),
      titleKey: 'settings.privacy.social.friendRequests',
      descriptionKey: 'settings.privacy.social.friendRequestsDescription',
      value: availability == FriendRequestPrivacyAvailability.available
          ? snapshot?.allowFriendRequests
          : null,
      enabled: projection?.canEdit ?? false,
      loading: availability == FriendRequestPrivacyAvailability.loading,
      saving: projection?.operation == FriendRequestPrivacyOperation.saving,
      statusKey: projection == null
          ? 'settings.privacy.friendRequests.unavailable'
          : _failureText(
              availability == FriendRequestPrivacyAvailability.signedOut,
              projection.failure ?? snapshot?.failure,
            ),
      loadingKey: const Key('friend-request-privacy-loading'),
      savingKey: const Key('friend-request-privacy-saving'),
      onChanged: onChanged ?? (_) async => false,
      onRetry: availability == FriendRequestPrivacyAvailability.unavailable
          ? onRetry
          : null,
    );
  }
}

String _failureText(bool signedOut, FriendRequestPrivacyFailure? failure) {
  if (signedOut) return 'settings.privacy.friendRequests.signedOut';
  if (failure == null) return '';
  return switch (failure) {
    FriendRequestPrivacyFailure.identityUnavailable =>
      'settings.privacy.friendRequests.identityUnavailable',
    FriendRequestPrivacyFailure.outcomeUnknown =>
      'settings.privacy.friendRequests.outcomeUnknown',
    FriendRequestPrivacyFailure.invalidResponse =>
      'settings.privacy.friendRequests.invalidResponse',
    FriendRequestPrivacyFailure.writeFailed =>
      'settings.privacy.friendRequests.writeFailed',
    _ => 'settings.privacy.friendRequests.unavailable',
  };
}
