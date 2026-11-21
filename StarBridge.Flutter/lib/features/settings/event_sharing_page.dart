import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/localization/account_card_title.dart';
import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'event_scope_editor.dart';
import 'event_sharing_controller.dart';
import 'privacy_page_drafts.dart';
import 'privacy_sharing_suggestion.dart';
import 'sharing_settings_waiting.dart';
import '../communities/community_logo.dart';

class EventSharingPage extends StatefulWidget {
  const EventSharingPage({
    required this.session,
    this.scmOnly,
    this.onSuggestionVisibilityChanged,
    super.key,
  });

  final BridgeClientSession session;
  final ValueListenable<bool>? scmOnly;
  final PrivacySuggestionVisibilityChanged? onSuggestionVisibilityChanged;
  @override
  State<EventSharingPage> createState() => _EventSharingPageState();
}

typedef _EventDraftBasis = ({
  String? owner,
  Map<String, String> memberships,
  int? revision,
  bool? publicationEnabled,
  Map<String?, EventSharingChoice> choices,
});

class _EventSharingPageState extends State<EventSharingPage> {
  static const _draftKey = 'event-choices';
  late final controller = EventSharingController(
    widget.session,
    scmOnly: widget.scmOnly,
  );
  PrivacyPageDrafts? _drafts;

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
    final basis = drafts?.basis<_EventDraftBasis>(_draftKey);
    if (controller.canEdit &&
        basis != null &&
        basis.owner != controller.accountKey) {
      drafts!.reconcileConflict(_draftKey);
    }
  }

  _EventDraftBasis _readBasis() {
    final c = controller;
    final communities = c.targets?.communities ?? [];
    return (
      owner: c.accountKey,
      memberships: {
        for (final target in communities) target.code: target.joinedAt,
      },
      revision: c.snapshot?['revision'] as int?,
      publicationEnabled: c.snapshot?['publicationEnabled'] as bool?,
      choices: {
        null: c.choice(null),
        for (final target in communities) target.code: c.choice(target.code),
      },
    );
  }

  bool _sameSavedSettings(_EventDraftBasis before, _EventDraftBasis now) =>
      before.revision == now.revision &&
      before.publicationEnabled == now.publicationEnabled &&
      before.choices[null] == now.choices[null] &&
      now.memberships.entries.every(
        (entry) =>
            before.memberships[entry.key] != entry.value ||
            before.choices[entry.key] == now.choices[entry.key],
      );

  bool _matchesChoices(
    _EventDraftBasis current,
    Map<String?, EventSharingChoice> choices,
  ) =>
      current.revision != null &&
      current.revision != 0 &&
      current.publicationEnabled ==
          choices.values.any((choice) => choice.effectiveTypes != 0) &&
      mapEquals(current.choices, choices);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final strings = AppStrings.of(context);
      final tokens = context.tokens;
      final drafts = _drafts;
      const initial = EventSharingChoice(
        enabled: true,
        selectedTypes: EventSharingChoice.allTypes,
      );
      final current = _readBasis();
      final saved = current.choices;
      final owner = current.owner;
      final memberships = current.memberships;
      final firstUse =
          drafts != null &&
          current.revision == 0 &&
          owner != null &&
          c.targets != null;
      final draft = drafts?.value<Map<String?, EventSharingChoice>?>(
        _draftKey,
        null,
      );
      final basis = drafts?.basis<_EventDraftBasis>(_draftKey);
      final conflict = drafts?.conflict(_draftKey);
      final sameOwner = basis == null || basis.owner == owner;
      final sameMemberships =
          basis == null || mapEquals(basis.memberships, memberships);
      final targets = c.targets?.communities ?? [];

      Map<String?, EventSharingChoice> choicesWithDraft(
        Map<String?, EventSharingChoice>? pending,
        _EventDraftBasis? pendingBasis,
      ) {
        if (pending == null ||
            pendingBasis == null ||
            pendingBasis.owner != owner ||
            (pendingBasis.revision == 0 &&
                !mapEquals(pendingBasis.memberships, memberships))) {
          return saved;
        }
        return {
          null: pending[null] ?? saved[null]!,
          for (final entry in memberships.entries)
            entry.key: pendingBasis.memberships[entry.key] == entry.value
                ? pending[entry.key] ?? saved[entry.key]!
                : saved[entry.key]!,
        };
      }

      final choices = choicesWithDraft(draft, basis);
      final sameSaved = basis == null || _sameSavedSettings(basis, current);
      final matchesSavedDraft =
          basis != null &&
          sameMemberships &&
          draft != null &&
          _matchesChoices(current, draft);
      final canEdit =
          c.canEdit &&
          !(drafts?.saving ?? false) &&
          sameOwner &&
          (basis?.revision != 0 || sameMemberships) &&
          (sameSaved || matchesSavedDraft);

      bool canApplyEdit(_EventDraftBasis base) {
        if (!canEdit || !c.canEdit || base.owner != c.accountKey) return false;
        final latest = _readBasis();
        return mapEquals(latest.memberships, base.memberships) &&
            _sameSavedSettings(base, latest);
      }

      void edit(Map<String?, EventSharingChoice> next, _EventDraftBasis base) {
        if (!canApplyEdit(base)) return;

        bool confirmsChoices(_EventDraftBasis live, {bool accepted = false}) =>
            c.canEdit &&
            base.owner == live.owner &&
            (accepted || c.state != 'unconfirmed') &&
            mapEquals(live.memberships, base.memberships) &&
            _matchesChoices(live, next);

        drafts!.edit(
          _draftKey,
          // An absent preference differs from explicitly saving all scopes off.
          base.revision == 0
              ? const <String?, EventSharingChoice>{}
              : base.choices,
          next,
          (value) async {
            if (!c.canEdit || base.owner != c.accountKey) return false;
            final latest = _readBasis();
            if (!mapEquals(latest.memberships, base.memberships)) return false;
            if (confirmsChoices(latest)) return true;
            if (!_sameSavedSettings(base, latest)) return false;
            final accepted = await c.saveChoices(
              value,
              omitUnconfirmedCommunities: base.revision == 0,
            );
            return confirmsChoices(_readBasis(), accepted: accepted);
          },
          basis: base,
          checkConflict: (value) {
            if (!c.canEdit) return null;
            if (c.accountKey != base.owner) {
              return PrivacyDraftConflict.savedElsewhere;
            }
            final latest = _readBasis();
            if (!mapEquals(latest.memberships, base.memberships)) {
              return PrivacyDraftConflict.membershipsChanged;
            }
            // Readback verifies settings even while the stream is unconfirmed.
            if (!_sameSavedSettings(base, latest) &&
                !_matchesChoices(latest, value)) {
              return PrivacyDraftConflict.savedElsewhere;
            }
            return null;
          },
        );
      }

      void change(String? code, EventSharingChoiceEdit apply) {
        if (drafts == null) {
          if (canApplyEdit(current)) c.change(code, apply(c.choice(code)));
          return;
        }
        final latestChoices = choicesWithDraft(
          drafts.value(_draftKey, null),
          drafts.basis(_draftKey),
        );
        edit({...latestChoices, code: apply(latestChoices[code]!)}, current);
      }

      Future<void> adopt() async {
        final epoch = drafts!.epoch;
        final confirmed = await confirmPrivacySharingSuggestion(context, [
          strings.text('settings.privacy.events.room'),
          for (final target in targets) target.name,
          strings.text('settings.privacy.suggestion.allEventTypes'),
        ]);
        if (!confirmed || !mounted) return;
        if (c.busy) await c.refresh();
        if (!context.mounted ||
            !identical(PrivacyDraftScope.of(context), drafts) ||
            drafts.epoch != epoch ||
            !identical(
              drafts.value<Map<String?, EventSharingChoice>?>(_draftKey, null),
              draft,
            ) ||
            drafts.saving ||
            !c.canEdit ||
            c.accountKey != owner) {
          return;
        }
        final latest = _readBasis();
        if (memberships.entries.any(
          (entry) => latest.memberships[entry.key] != entry.value,
        )) {
          drafts.rejectEdit(_draftKey, PrivacyDraftConflict.membershipsChanged);
          return;
        }
        if (!_sameSavedSettings(current, latest)) {
          drafts.rejectEdit(_draftKey, PrivacyDraftConflict.savedElsewhere);
          return;
        }
        // Newly joined communities keep their actual choice. Only the
        // identities shown in the dialog can acquire an enabled choice.
        edit({
          ...latest.choices,
          null: initial,
          for (final code in memberships.keys) code: initial,
        }, latest);
      }

      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(tokens.space.lg),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: tokens.density.contentMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        strings.text('settings.privacy.events.title'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      SizedBox(height: tokens.space.sm),
                      Text(strings.text('settings.privacy.events.scopeHelp')),
                      if (conflict != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(strings.text(conflict.messageKey)),
                        ),
                      if (firstUse)
                        PrivacySharingSuggestion(
                          adoptKey: const Key('event-sharing-adopt-suggestion'),
                          onAdopt: canEdit ? adopt : null,
                          onVisibilityChanged:
                              widget.onSuggestionVisibilityChanged,
                        ),
                      SizedBox(height: tokens.space.md),
                      if (c.snapshot != null && c.targets != null) ...[
                        EventScopeEditor(
                          scopeKey: 'event-room',
                          title: strings.text('settings.privacy.events.room'),
                          description: strings.text(
                            'settings.privacy.events.roomHelp',
                          ),
                          choice: choices[null]!,
                          canEdit: canEdit,
                          canEditInactiveTypes: current.revision == 0,
                          onChanged: (value) => change(null, value),
                        ),
                        for (final target in c.targets!.communities) ...[
                          SizedBox(height: tokens.space.md),
                          EventScopeEditor(
                            scopeKey: 'event-${target.code}',
                            title: target.name,
                            leading: CommunityLogo(
                              data: target.logoImageData,
                              size: 36,
                              framed: false,
                            ),
                            description: strings.text(
                              'settings.privacy.events.organizationHelp',
                            ),
                            choice: choices[target.code] ?? saved[target.code]!,
                            canEdit: canEdit,
                            canEditInactiveTypes: current.revision == 0,
                            onChanged: (value) => change(target.code, value),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SharingSettingsWaiting(
                  owner: c,
                  pending: () => c.busy,
                  titleKey: 'settings.privacy.events.title',
                  labelKey: 'settings.privacy.events.pending',
                ),
                Text(
                  withAccountCardTitle(
                    context,
                    strings.text(
                      c.scmOnlyUnavailable
                          ? 'settings.privacy.events.scmOnly'
                          : c.error != null
                          ? 'settings.privacy.events.unavailable'
                          : c.snapshot == null
                          ? 'settings.privacy.loading'
                          : !firstUse && c.state == 'unconfirmed'
                          ? 'settings.privacy.events.publicationUnconfirmed'
                          : c.snapshot!['publicationEnabled'] == false
                          ? (firstUse
                                ? 'settings.privacy.events.firstUseOff'
                                : 'settings.privacy.events.off')
                          : c.state == 'active'
                          ? 'settings.privacy.events.active'
                          : 'settings.privacy.events.savedPaused',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
