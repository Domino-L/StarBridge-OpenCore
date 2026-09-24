import 'package:flutter/material.dart';

import 'authoritative_privacy_setting.dart';
import 'direct_message_privacy_module.dart';

class DirectMessagePrivacySetting extends StatelessWidget {
  const DirectMessagePrivacySetting({this.module, super.key});

  final DirectMessagePrivacyModule? module;

  @override
  Widget build(BuildContext context) {
    final value = module;
    if (value == null) return _setting();
    return ValueListenableBuilder<DirectMessagePrivacyProjection>(
      valueListenable: value.projection,
      builder: (context, projection, _) => _setting(
        projection: projection,
        onChanged: value.save,
        onRetry: value.refresh,
      ),
    );
  }

  Widget _setting({
    DirectMessagePrivacyProjection? projection,
    Future<bool> Function(bool)? onChanged,
    Future<void> Function()? onRetry,
  }) {
    final snapshot = projection?.snapshot;
    final availability = snapshot?.availability;
    return AuthoritativePrivacySetting(
      settingKey: const Key('privacy-stranger-messages-authoritative'),
      titleKey: 'settings.privacy.social.strangerMessages',
      descriptionKey: 'settings.privacy.social.strangerMessagesDescription',
      value: availability == DirectMessagePrivacyAvailability.available
          ? snapshot?.allowStrangerDirectMessages
          : null,
      enabled: projection?.canEdit ?? false,
      loading: availability == DirectMessagePrivacyAvailability.loading,
      saving: projection?.operation == DirectMessagePrivacyOperation.saving,
      statusKey: projection == null
          ? 'settings.privacy.directMessages.unavailable'
          : _failureText(
              availability == DirectMessagePrivacyAvailability.signedOut,
              projection.failure ?? snapshot?.failure,
            ),
      loadingKey: const Key('direct-message-privacy-loading'),
      savingKey: const Key('direct-message-privacy-saving'),
      onChanged: onChanged ?? (_) async => false,
      onRetry: availability == DirectMessagePrivacyAvailability.unavailable
          ? onRetry
          : null,
    );
  }
}

String _failureText(bool signedOut, DirectMessagePrivacyFailure? failure) {
  if (signedOut) return 'settings.privacy.directMessages.signedOut';
  if (failure == null) return '';
  return switch (failure) {
    DirectMessagePrivacyFailure.identityUnavailable =>
      'settings.privacy.directMessages.identityUnavailable',
    DirectMessagePrivacyFailure.outcomeUnknown =>
      'settings.privacy.directMessages.outcomeUnknown',
    DirectMessagePrivacyFailure.invalidResponse =>
      'settings.privacy.directMessages.invalidResponse',
    DirectMessagePrivacyFailure.writeFailed =>
      'settings.privacy.directMessages.writeFailed',
    _ => 'settings.privacy.directMessages.unavailable',
  };
}
