import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'help_support_action.dart';
import 'help_support_waiting.dart';
import 'sync_privacy_page_components.dart';
import 'privacy_page_drafts.dart';

class AuthoritativePrivacySetting extends StatefulWidget {
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
    this.presentationChanges,
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

  /// Observe the existing owner's notifications only for input provenance.
  /// This does not initialize, read, save, cancel or dispose that owner.
  final Listenable? presentationChanges;

  @override
  State<AuthoritativePrivacySetting> createState() =>
      _AuthoritativePrivacySettingState();
}

class _AuthoritativePrivacySettingState
    extends State<AuthoritativePrivacySetting> {
  InteractionSource _notificationSource = InteractionSource.programmatic;
  InteractionSource _loadingSource = InteractionSource.programmatic;
  InteractionSource _savingSource = InteractionSource.programmatic;
  InteractionSource _retrySource = InteractionSource.programmatic;
  int _phase = 0;
  int _loadingPhase = 0;
  int _savingPhase = 0;
  int _retryPhase = 0;
  bool _notifiedSinceBuild = false;
  Object? _retryToken;

  void _observeSource() {
    // Notifications run synchronously inside the actual save command, even
    // when a draft was edited earlier and submitted from a different target.
    _notificationSource = captureStarBridgeActivationSource()();
    _notifiedSinceBuild = true;
    // These owners publish at read completion, save, or identity invalidation,
    // not at ordinary refresh start. Retire the old read decoration on that
    // fact even if loading and a new snapshot coalesce before the next build.
    // The original Future still runs; its finally cannot clear a newer token.
    _retryToken = null;
  }

  @override
  void initState() {
    super.initState();
    widget.presentationChanges?.addListener(_observeSource);
  }

  @override
  void didUpdateWidget(AuthoritativePrivacySetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presentationChanges, widget.presentationChanges)) {
      oldWidget.presentationChanges?.removeListener(_observeSource);
      widget.presentationChanges?.addListener(_observeSource);
      _notificationSource = InteractionSource.programmatic;
      _loadingSource = InteractionSource.programmatic;
      _savingSource = InteractionSource.programmatic;
      _retryToken = null;
      _loadingPhase = ++_phase;
      _savingPhase = ++_phase;
    } else {
      if (widget.loading && (!oldWidget.loading || _notifiedSinceBuild)) {
        // Ordinary refresh does not replace the snapshot with loading. A new
        // loading context retires any old explicit-read decoration, not work.
        _retryToken = null;
        _loadingSource = _notificationSource;
        _loadingPhase = ++_phase;
      }
      if (widget.saving && (!oldWidget.saving || _notifiedSinceBuild)) {
        _savingSource = _notificationSource;
        _savingPhase = ++_phase;
      }
    }
    // A completion and another start can coalesce before a frame. A fresh
    // owner notification renews that phase even if both widget flags are true.
    // Theme/parent-only rebuilds have no such notification and do not replay it.
    _notifiedSinceBuild = false;
  }

  Future<void> _retry(
    Future<void> Function() original,
    Listenable? owner,
    InteractionSource source,
  ) => runStarBridgeActivation<void>(source, () async {
    Object? token;
    if (mounted &&
        identical(owner, widget.presentationChanges) &&
        _retryToken == null) {
      token = Object();
      setState(() {
        _retryToken = token;
        _retrySource = source;
        _retryPhase = ++_phase;
      });
    }
    try {
      // The original callback still receives every activation. Its owner
      // decides admission/queuing; a decoration token is not a business lock.
      await original();
    } finally {
      if (token != null &&
          mounted &&
          identical(owner, widget.presentationChanges) &&
          identical(token, _retryToken)) {
        setState(() => _retryToken = null);
      }
    }
  });

  Widget _wait(Key key, InteractionSource source, int phase, String labelKey) =>
      KeyedSubtree(
        key: key,
        child: HelpSupportWaiting(
          key: ValueKey(phase),
          source: source,
          label:
              '${AppStrings.of(context).text(widget.titleKey)} · '
              '${AppStrings.of(context).text(labelKey)}',
        ),
      );

  @override
  void dispose() {
    widget.presentationChanges?.removeListener(_observeSource);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Preserve each rendered callback's original owner and values, including
    // draft commits held beyond a later rebuild or module replacement.
    final settingKey = widget.settingKey;
    final titleKey = widget.titleKey;
    final descriptionKey = widget.descriptionKey;
    final value = widget.value;
    final enabled = widget.enabled;
    final loading = widget.loading;
    final saving = widget.saving;
    final statusKey = widget.statusKey;
    final loadingKey = widget.loadingKey;
    final savingKey = widget.savingKey;
    final onChanged = widget.onChanged;
    final originalRetry = widget.onRetry;
    final owner = widget.presentationChanges;
    final ValueChanged<InteractionSource>? onRetry = originalRetry == null
        ? null
        : (source) => _retry(originalRetry, owner, source);
    final drafts = PrivacyDraftScope.of(context);
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _wait(
          loadingKey,
          _loadingSource,
          _loadingPhase,
          'settings.privacy.loading',
        ),
      );
    }
    final retryWait = _retryToken == null
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _wait(
              ValueKey((settingKey, 'retry-wait')),
              _retrySource,
              _retryPhase,
              'settings.privacy.loading',
            ),
          );
    if (value == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UnavailablePrivacySetting(
            titleKey: titleKey,
            statusKey: statusKey,
            onRetry: onRetry,
          ),
          ?retryWait,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SyncPrivacySettingRow(
          settingKey: settingKey,
          titleKey: titleKey,
          descriptionKey: descriptionKey,
          value: drafts?.value(titleKey, value) ?? value,
          enabled: enabled && !(drafts?.saving ?? false),
          onChanged: (next) async {
            if (drafts == null) return onChanged(next);
            drafts.edit(titleKey, value, next, onChanged);
            return true;
          },
          showDivider: false,
        ),
        if (saving)
          _wait(savingKey, _savingSource, _savingPhase, 'privacy.local.saving'),
        if (statusKey.isNotEmpty)
          _PrivacySettingStatus(statusKey: statusKey, onRetry: onRetry),
        ?retryWait,
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
  final ValueChanged<InteractionSource>? onRetry;

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
            HelpSupportAction(
              controlKey: const Key('authoritative-privacy-retry'),
              onActivate: onRetry,
              icon: StarBridgeIconSemantic.refresh,
              child: Text(strings.text('settings.privacy.retry')),
            ),
        ],
      ),
    );
  }
}

class _PrivacySettingStatus extends StatelessWidget {
  const _PrivacySettingStatus({required this.statusKey, this.onRetry});

  final String statusKey;
  final ValueChanged<InteractionSource>? onRetry;

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
            HelpSupportAction(
              controlKey: const Key('authoritative-privacy-status-retry'),
              onActivate: onRetry,
              child: Text(strings.text('settings.privacy.retry')),
            ),
        ],
      ),
    );
  }
}
