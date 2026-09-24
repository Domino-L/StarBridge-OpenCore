import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/scheduler.dart';

import 'privacy_page_drafts.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_privacy_controller.dart';
import 'local_privacy_page.dart';
import 'direct_message_privacy_module.dart';
import 'friend_request_privacy_module.dart';
import 'recently_played_privacy_module.dart';
import 'sync_privacy_module.dart';
import 'sync_privacy_page.dart';
import 'event_sharing_page.dart';
import 'friend_sharing_setting.dart';
import 'game_id_visibility_setting.dart';
import '../../platform/bridge/bridge_client_session.dart';

enum PrivacySettingsSection { scopes, account, events }

/// Keeps domain ownership independent while sharing one editor transaction.
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({
    required this.localPrivacy,
    required this.syncPrivacy,
    this.directMessagePrivacy,
    this.friendRequestPrivacy,
    this.recentlyPlayedPrivacy,
    this.eventSession,
    super.key,
  });

  final LocalPrivacyController localPrivacy;
  final SyncPrivacyModule syncPrivacy;
  final DirectMessagePrivacyModule? directMessagePrivacy;
  final FriendRequestPrivacyModule? friendRequestPrivacy;
  final RecentlyPlayedPrivacyModule? recentlyPlayedPrivacy;
  final BridgeClientSession? eventSession;

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  PrivacySettingsSection selected = PrivacySettingsSection.scopes;
  final drafts = PrivacyPageDrafts();
  StreamSubscription? _accountEvents;
  bool _saving = false;
  bool get _dirty => drafts.dirty || widget.localPrivacy.dirty;
  bool get _canSave => _dirty || widget.localPrivacy.canSave;

  @override
  void initState() {
    super.initState();
    drafts.addListener(_changed);
    widget.localPrivacy.addListener(_changed);
    privacyPageLeaveGuards[widget.localPrivacy] = _confirmLeave;
    _accountEvents = widget.eventSession?.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        drafts.discard();
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _discard() {
    drafts.discard();
    widget.localPrivacy.discard();
  }

  Future<bool> _save() async {
    if (_saving) return false;
    setState(() => _saving = true);
    final epoch = drafts.epoch;
    final localDraft = widget.localPrivacy.draft;
    try {
      final remoteOk = await drafts.save();
      if (!mounted || epoch != drafts.epoch) return false;
      if (!identical(localDraft, widget.localPrivacy.draft)) return false;
      final localOk =
          (!widget.localPrivacy.dirty && widget.localPrivacy.hasSaved) ||
          await widget.localPrivacy.save();
      return remoteOk && localOk;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (_saving ||
        widget.localPrivacy.saving ||
        widget.localPrivacy.publicationBusy) {
      return false;
    }
    if (!_dirty) return true;
    final epoch = drafts.epoch;
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('privacy.local.$key');
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('privacy-leave-dialog'),
        title: Text(t('leaveTitle')),
        content: Text(strings.text('settings.privacy.page.leave')),
        actions: [
          TextButton(
            key: const Key('privacy-leave-cancel'),
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text(t('stay')),
          ),
          TextButton(
            key: const Key('privacy-leave-discard'),
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text(t('discard')),
          ),
          FilledButton(
            key: const Key('privacy-leave-save'),
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(strings.text('settings.privacy.page.save')),
          ),
        ],
      ),
    );
    if (!mounted || epoch != drafts.epoch) return false;
    if (result == 'save') return _save();
    if (result == 'discard') {
      _discard();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    privacyPageLeaveGuards[widget.localPrivacy] = null;
    widget.localPrivacy.removeListener(_changed);
    drafts.removeListener(_changed);
    // Async writes may still finish; the epoch prevents the remaining groups.
    drafts.discard();
    unawaited(_accountEvents?.cancel());
    drafts.dispose();
    super.dispose();
  }

  Future<void> _select(PrivacySettingsSection next) async {
    if (next == selected) return;
    if (_saving) return;
    if (!mounted) return;
    setState(() => selected = next);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    return PrivacyDraftScope(
      drafts: drafts,
      child: Column(
        key: const Key('privacy-settings-page'),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surfaces.chrome.fill,
              border: Border(
                bottom: BorderSide(
                  color: tokens.surfaces.chrome.border,
                  width: tokens.stroke.hairline,
                ),
              ),
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                tokens.space.xl,
                tokens.space.sm,
                tokens.space.xl,
                tokens.space.sm,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Row(
                    children: [
                      Expanded(
                        child: _PrivacySectionButton(
                          section: PrivacySettingsSection.scopes,
                          selected: selected == PrivacySettingsSection.scopes,
                          titleKey: 'settings.privacy.sections.scopes',
                          descriptionKey:
                              'settings.privacy.sections.scopesDescription',
                          onPressed: _select,
                        ),
                      ),
                      SizedBox(width: tokens.space.sm),
                      if (widget.eventSession != null) ...[
                        Expanded(
                          child: _PrivacySectionButton(
                            section: PrivacySettingsSection.events,
                            selected: selected == PrivacySettingsSection.events,
                            titleKey: 'settings.privacy.events.title',
                            descriptionKey: 'settings.privacy.events.contexts',
                            onPressed: _select,
                          ),
                        ),
                        SizedBox(width: tokens.space.sm),
                      ],
                      Expanded(
                        child: _PrivacySectionButton(
                          section: PrivacySettingsSection.account,
                          selected: selected == PrivacySettingsSection.account,
                          titleKey: 'settings.privacy.sections.account',
                          descriptionKey:
                              'settings.privacy.sections.accountDescription',
                          onPressed: _select,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: selected.index,
              children: [
                LocalPrivacyPage(
                  controller: widget.localPrivacy,
                  showSaveBar: false,
                ),
                SyncPrivacyPage(
                  gameIdVisibility: widget.eventSession == null
                      ? null
                      : GameIdVisibilitySetting(session: widget.eventSession!),
                  friendSharing: widget.eventSession == null
                      ? null
                      : FriendSharingSetting(session: widget.eventSession!),
                  showLegacyEvents: widget.eventSession == null,
                  module: widget.syncPrivacy,
                  directMessagePrivacy: widget.directMessagePrivacy,
                  friendRequestPrivacy: widget.friendRequestPrivacy,
                  recentlyPlayedPrivacy: widget.recentlyPlayedPrivacy,
                ),
                if (widget.eventSession != null)
                  EventSharingPage(session: widget.eventSession!)
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.all(tokens.space.md),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  strings.text(
                    _saving
                        ? 'privacy.local.saving'
                        : drafts.failed
                        ? 'settings.privacy.page.failed'
                        : _dirty
                        ? 'privacy.local.dirty'
                        : 'settings.privacy.page.saved',
                  ),
                ),
                const SizedBox(width: 16),
                TextButton(
                  key: const Key('privacy-discard'),
                  onPressed: _dirty && !_saving ? _discard : null,
                  child: Text(strings.text('privacy.local.discard')),
                ),
                FilledButton(
                  key: const Key('privacy-save'),
                  onPressed: _canSave && !_saving ? _save : null,
                  child: Text(strings.text('settings.privacy.page.save')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacySectionButton extends StatelessWidget {
  const _PrivacySectionButton({
    required this.section,
    required this.selected,
    required this.titleKey,
    required this.descriptionKey,
    required this.onPressed,
  });

  final PrivacySettingsSection section;
  final bool selected;
  final String titleKey;
  final String descriptionKey;
  final ValueChanged<PrivacySettingsSection> onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? tokens.colors.accentSoft : tokens.surfaces.panel.fill,
        borderRadius: tokens.shape.small,
        child: InkWell(
          key: Key('privacy-section-${section.name}'),
          onTap: () => onPressed(section),
          borderRadius: tokens.shape.small,
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: EdgeInsetsDirectional.fromSTEB(
              tokens.space.md,
              tokens.space.sm,
              tokens.space.md,
              tokens.space.sm,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? tokens.colors.accent
                    : tokens.surfaces.panel.border,
                width: selected
                    ? tokens.stroke.regular
                    : tokens.stroke.hairline,
              ),
              borderRadius: tokens.shape.small,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  strings.text(titleKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? tokens.colors.accent
                        : tokens.colors.textPrimary,
                  ),
                ),
                SizedBox(height: tokens.space.xxs),
                Text(
                  strings.text(descriptionKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
