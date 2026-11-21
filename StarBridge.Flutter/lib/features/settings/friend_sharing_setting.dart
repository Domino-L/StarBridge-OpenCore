import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'friend_sharing_controller.dart';
import 'privacy_page_drafts.dart';
import 'privacy_sharing_suggestion.dart';
import 'sharing_settings_waiting.dart';

class FriendSharingSetting extends StatefulWidget {
  const FriendSharingSetting({
    required this.session,
    this.onSuggestionVisibilityChanged,
    super.key,
  });

  final BridgeClientSession session;
  final PrivacySuggestionVisibilityChanged? onSuggestionVisibilityChanged;
  @override
  State<FriendSharingSetting> createState() => _FriendSharingSettingState();
}

typedef _FriendDraftBasis = ({String? owner, int? revision, int fields});

class _FriendSharingSettingState extends State<FriendSharingSetting> {
  static const _draftKey = 'friend-fields';
  static const _fieldLabels = {
    1: 'presence',
    2: 'serverRelation',
    4: 'serverDetails',
    8: 'ship',
    16: 'location',
    32: 'lastOnline',
  };
  late final controller = FriendSharingController(widget.session);
  PrivacyPageDrafts? _drafts;

  _FriendDraftBasis _readBasis() => (
    owner: controller.accountKey,
    revision: controller.snapshot?['revision'] as int?,
    fields: controller.fields,
  );

  bool _matchesDraft(_FriendDraftBasis live, int? draft) =>
      live.revision != null && live.revision != 0 && live.fields == draft;

  @override
  void initState() {
    super.initState();
    controller.addListener(_reconcileReadback);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _drafts = PrivacyDraftScope.of(context);
  }

  void _reconcileReadback() {
    final drafts = _drafts;
    final basis = drafts?.basis<_FriendDraftBasis>(_draftKey);
    if (controller.canEdit &&
        basis != null &&
        (basis.revision != 0 || basis.owner != controller.accountKey)) {
      drafts!.reconcileConflict(_draftKey);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final strings = AppStrings.of(context), tokens = context.tokens;
      final c = controller;
      final drafts = _drafts;
      final draft = drafts?.value<int?>(_draftKey, null);
      final current = _readBasis();
      final owner = current.owner;
      final conflict = drafts?.conflict(_draftKey);
      final firstUse = drafts != null && current.revision == 0 && owner != null;
      final basis = drafts?.basis<_FriendDraftBasis>(_draftKey);
      final sameOwner = basis == null || basis.owner == owner;
      final matchesDraft = _matchesDraft(current, draft);
      final fields = sameOwner ? draft ?? current.fields : current.fields;
      final canEdit =
          c.canEdit &&
          !(drafts?.saving ?? false) &&
          sameOwner &&
          (basis == null || basis == current || matchesDraft);

      void edit(int next) {
        if (!canEdit || !c.canEdit || _readBasis() != current) return;
        drafts!.edit(
          _draftKey,
          // An absent preference differs from an explicitly saved OFF.
          firstUse ? -1 : current.fields,
          next,
          (value) async {
            final live = _readBasis();
            if (owner != live.owner || !c.canEdit) return false;
            if (_matchesDraft(live, value)) return true;
            if (live != current) return false;
            await c.saveFields(value, expectedRevision: current.revision!);
            return owner == c.accountKey &&
                c.canEdit &&
                _matchesDraft(_readBasis(), value);
          },
          basis: current,
          checkConflict: (value) {
            if (!c.canEdit) return null;
            final live = _readBasis();
            if (live.owner != owner ||
                (live != current && !_matchesDraft(live, value))) {
              return PrivacyDraftConflict.savedElsewhere;
            }
            return null;
          },
        );
      }

      String fieldLabel(String field) =>
          strings.text('settings.privacy.field.$field');

      Future<void> adopt() async {
        final epoch = drafts!.epoch;
        final items = _fieldLabels.entries.toList();
        final confirmed = await confirmPrivacySharingSuggestion(context, [
          for (final item in items) fieldLabel(item.value),
        ]);
        if (!confirmed ||
            !context.mounted ||
            !identical(PrivacyDraftScope.of(context), drafts) ||
            drafts.epoch != epoch ||
            drafts.value<int?>(_draftKey, null) != draft ||
            drafts.saving ||
            !c.canEdit ||
            c.accountKey != owner) {
          return;
        }
        if (_readBasis() != current) {
          drafts.rejectEdit(_draftKey, PrivacyDraftConflict.savedElsewhere);
          return;
        }
        edit(items.fold(0, (fields, item) => fields | item.key));
      }

      String? fieldDescription(int bit) => switch (bit) {
        1 => fieldLabel(
          firstUse ? 'presenceFirstUseDescription' : 'presenceDescription',
        ),
        32 => fieldLabel('lastOnlineDescription'),
        _ => null,
      };

      return Card(
        child: Padding(
          padding: EdgeInsets.all(tokens.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.text('settings.privacy.friends.title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(strings.text('settings.privacy.friends.description')),
              SharingSettingsWaiting(
                owner: c,
                pending: () => c.busy && c.snapshot == null,
                titleKey: 'settings.privacy.friends.title',
                labelKey: 'settings.privacy.loading',
              ),
              Text(
                strings.text(
                  c.error != null
                      ? 'settings.privacy.friends.unavailable'
                      : c.snapshot == null
                      ? 'settings.privacy.loading'
                      : c.fields == 0
                      ? (firstUse
                            ? 'settings.privacy.friends.firstUseOff'
                            : 'settings.privacy.friends.off')
                      : c.state == 'active'
                      ? 'settings.privacy.friends.active'
                      : 'settings.privacy.friends.savedPaused',
                ),
              ),
              if (conflict != null)
                Semantics(
                  liveRegion: true,
                  child: Text(strings.text(conflict.messageKey)),
                ),
              if (firstUse)
                PrivacySharingSuggestion(
                  adoptKey: const Key('friend-sharing-adopt-suggestion'),
                  onAdopt: canEdit ? adopt : null,
                  onVisibilityChanged: widget.onSuggestionVisibilityChanged,
                ),
              for (final item in _fieldLabels.entries)
                if (firstUse || item.key != 32)
                  StarBridgeSwitch.tile(
                    controlKey: Key('friend-sharing-${item.value}'),
                    preserveNativeTile: true,
                    subtitle: fieldDescription(item.key),
                    subtitleWidget: switch (fieldDescription(item.key)) {
                      final description? => Text(description),
                      null => null,
                    },
                    label: fieldLabel(item.value),
                    titleWidget: Text(fieldLabel(item.value)),
                    rowBuilder: (control) =>
                        resolveStarBridgeInteraction(context).suite ==
                            InteractionSuite.standard
                        ? control
                        : ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(fieldLabel(item.value)),
                            subtitle: switch (fieldDescription(item.key)) {
                              final description? => Text(description),
                              null => null,
                            },
                            enabled: canEdit,
                            trailing: control,
                          ),
                    value: fields & item.key != 0,
                    onChanged: canEdit
                        ? (value) {
                            if (drafts == null) {
                              c.change(item.key, value);
                              return;
                            }
                            final mask = !firstUse && item.key == 1
                                ? 33
                                : item.key;
                            final latestFields = drafts.value(
                              _draftKey,
                              current.fields,
                            );
                            edit(
                              value
                                  ? latestFields | mask
                                  : latestFields & ~mask,
                            );
                          }
                        : null,
                  ),
              SharingSettingsWaiting(
                owner: c,
                pending: () => c.busy && c.snapshot != null,
                titleKey: 'settings.privacy.friends.title',
                labelKey: 'privacy.local.saving',
              ),
            ],
          ),
        ),
      );
    },
  );
}
