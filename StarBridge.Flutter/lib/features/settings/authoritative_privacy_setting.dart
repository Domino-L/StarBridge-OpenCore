import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'sync_privacy_page_components.dart';
import 'privacy_page_drafts.dart';

class AuthoritativePrivacySetting extends StatelessWidget {
  const AuthoritativePrivacySetting({
    required this.settingKey,
    required this.titleKey,
    required this.descriptionKey,
    required this.value,
    required this.enabled,
    required this.loading,
    required this.saving,
    required this.statusKey,
    required this.loadingKey,
    required this.savingKey,
    required this.onChanged,
    this.onRetry,
    super.key,
  });

  final Key settingKey;
  final String titleKey;
  final String descriptionKey;
  final bool? value;
  final bool enabled;
  final bool loading;
  final bool saving;
  final String statusKey;
  final Key loadingKey;
  final Key savingKey;
  final Future<bool> Function(bool) onChanged;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final drafts = PrivacyDraftScope.of(context);
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(key: loadingKey),
      );
    }
    if (value == null) {
      return _UnavailablePrivacySetting(
        titleKey: titleKey,
        statusKey: statusKey,
        onRetry: onRetry,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SyncPrivacySettingRow(
          settingKey: settingKey,
          titleKey: titleKey,
          descriptionKey: descriptionKey,
          value: drafts?.value(titleKey, value!) ?? value!,
          enabled: enabled && !(drafts?.saving ?? false),
          onChanged: (next) async {
            if (drafts == null) return onChanged(next);
            drafts.edit(titleKey, value!, next, onChanged);
            return true;
          },
          showDivider: false,
        ),
        if (saving) LinearProgressIndicator(key: savingKey),
        if (statusKey.isNotEmpty)
          _PrivacySettingStatus(statusKey: statusKey, onRetry: onRetry),
      ],
    );
  }
}

class _UnavailablePrivacySetting extends StatelessWidget {
  const _UnavailablePrivacySetting({
    required this.titleKey,
    required this.statusKey,
    this.onRetry,
  });

  final String titleKey;
  final String statusKey;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text(titleKey),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                SizedBox(height: tokens.space.xxs),
                Text(
                  strings.text(statusKey),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.colors.textDisabled),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton.icon(
              onPressed: onRetry,
              icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
              label: Text(strings.text('settings.privacy.retry')),
            ),
        ],
      ),
    );
  }
}

class _PrivacySettingStatus extends StatelessWidget {
  const _PrivacySettingStatus({required this.statusKey, this.onRetry});

  final String statusKey;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      margin: EdgeInsets.only(top: tokens.space.sm),
      padding: EdgeInsets.all(tokens.space.sm),
      decoration: BoxDecoration(
        color: tokens.colors.warningSoft,
        borderRadius: tokens.shape.small,
      ),
      child: Row(
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.warning,
            color: tokens.colors.warning,
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(child: Text(strings.text(statusKey))),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(strings.text('settings.privacy.retry')),
            ),
        ],
      ),
    );
  }
}
