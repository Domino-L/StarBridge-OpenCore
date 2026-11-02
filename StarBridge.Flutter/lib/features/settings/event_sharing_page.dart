import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'event_scope_editor.dart';
import 'event_sharing_controller.dart';
import 'privacy_page_drafts.dart';
import 'sharing_settings_waiting.dart';
import '../communities/community_logo.dart';

class EventSharingPage extends StatefulWidget {
  const EventSharingPage({required this.session, super.key});
  final BridgeClientSession session;
  @override
  State<EventSharingPage> createState() => _EventSharingPageState();
}

class _EventSharingPageState extends State<EventSharingPage> {
  PrivacyPageDrafts? _drafts;
  String? _preparedOwner;
  late final EventSharingController controller = EventSharingController(
    widget.session,
  );
  @override
  void initState() {
    super.initState();
    controller.addListener(_prepareInitialDraft);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _drafts = PrivacyDraftScope.of(context);
    _prepareInitialDraft();
  }

  bool _confirmsChoices(
    String? owner,
    String memberships,
    Map<String?, EventSharingChoice> choices,
  ) {
    final c = controller;
    return owner != null &&
        owner == c.accountKey &&
        c.canEdit &&
        c.snapshot?['revision'] != 0 &&
        c.state != 'unconfirmed' &&
        [for (final t in c.targets!.communities) '${t.code}:${t.joinedAt}']
                .join('|') ==
            memberships &&
        c.snapshot?['publicationEnabled'] ==
            choices.values.any((choice) => choice.effectiveTypes != 0) &&
        choices.length == c.targets!.communities.length + 1 &&
        choices[null] == c.choice(null) &&
        c.targets!.communities.every(
          (target) => choices[target.code] == c.choice(target.code),
        );
  }

  void _prepareInitialDraft() {
    final c = controller;
    final drafts = _drafts;
    if (drafts == null ||
        c.accountKey == null ||
        _preparedOwner == c.accountKey ||
        !c.canEdit ||
        c.snapshot?['revision'] != 0 ||
        c.targets == null ||
        c.error != null) {
      return;
    }
    final owner = c.accountKey;
    _preparedOwner = owner;
    final epoch = drafts.epoch;
    final memberships = [
      for (final t in c.targets!.communities) '${t.code}:${t.joinedAt}',
    ].join('|');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_drafts, drafts) ||
          drafts.epoch != epoch ||
          owner != c.accountKey ||
          c.snapshot?['revision'] != 0 ||
          c.targets == null ||
          [for (final t in c.targets!.communities) '${t.code}:${t.joinedAt}']
                  .join('|') !=
              memberships) {
        return;
      }
      if (!c.canEdit) {
        // A same-lease refresh may temporarily occupy the owner before this
        // frame. Let its existing completion notification prepare again;
        // explicit discard or a changed lease has already retired above.
        _preparedOwner = null;
        return;
      }
      const all = EventSharingChoice(
        enabled: true,
        selectedTypes: EventSharingChoice.allTypes,
      );
      final choices = <String?, EventSharingChoice>{
        null: all,
        for (final t in c.targets!.communities) t.code: all,
      };
      drafts.edit('event-choices', <String?, EventSharingChoice>{}, choices, (
        next,
      ) async {
        if (owner != c.accountKey ||
            !c.canEdit ||
            [for (final t in c.targets!.communities) '${t.code}:${t.joinedAt}']
                    .join('|') !=
                memberships) {
          return false;
        }
        // A lost receipt is not success. A later authoritative, same-owner
        // read may confirm the exact choices without repeating the mutation.
        if (c.snapshot?['revision'] != 0) {
          return _confirmsChoices(owner, memberships, next);
        }
        await c.saveChoices(next);
        return _confirmsChoices(owner, memberships, next);
      });
    });
  }

  @override
  void dispose() {
    controller.removeListener(_prepareInitialDraft);
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
      final drafts = PrivacyDraftScope.of(context);
      const initial = EventSharingChoice(
        enabled: true,
        selectedTypes: EventSharingChoice.allTypes,
      );
      final saved = <String?, EventSharingChoice>{
        null: c.choice(null),
        for (final target in c.targets?.communities ?? [])
          target.code: c.choice(target.code),
      };
      final defaults = {
        for (final entry in saved.entries)
          entry.key: c.snapshot?['settings'] == null ? initial : entry.value,
      };
      final choices = drafts?.value('event-choices', defaults) ?? saved;
      final revision = c.snapshot?['revision'];
      final owner = c.accountKey;
      final memberships = [
        for (final t in c.targets?.communities ?? []) '${t.code}:${t.joinedAt}',
      ].join('|');
      void change(String? code, EventSharingChoice next) {
        if (drafts == null) {
          c.change(code, next);
          return;
        }
        drafts.edit('event-choices', saved, {...choices, code: next}, (
          value,
        ) async {
          if (owner != c.accountKey ||
              !c.canEdit ||
              [
                    for (final t in c.targets?.communities ?? [])
                      '${t.code}:${t.joinedAt}',
                  ].join('|') !=
                  memberships) {
            return false;
          }
          // Match saveChoices' current-scope projection using facts captured
          // by this edit: fill a new scope conservatively and omit removed
          // ones, without modifying the held draft or granting new access.
          final expected = <String?, EventSharingChoice>{
            for (final scope in saved.keys)
              scope: value[scope] ?? saved[scope]!,
          };
          if (_confirmsChoices(owner, memberships, expected)) return true;
          if (c.snapshot?['revision'] != revision) return false;
          await c.saveChoices(value);
          return _confirmsChoices(owner, memberships, expected);
        });
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
                      SizedBox(height: tokens.space.md),
                      SizedBox(height: tokens.space.md),
                      if (c.snapshot != null && c.targets != null) ...[
                        EventScopeEditor(
                          scopeKey: 'event-room',
                          title: strings.text('settings.privacy.events.room'),
                          description: strings.text(
                            'settings.privacy.events.roomHelp',
                          ),
                          choice: choices[null]!,
                          canEdit: c.canEdit && !(drafts?.saving ?? false),
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
                            canEdit: c.canEdit && !(drafts?.saving ?? false),
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
                  strings.text(
                    c.error != null
                        ? 'settings.privacy.events.unavailable'
                        : c.snapshot == null
                        ? 'settings.privacy.loading'
                        : c.snapshot!['publicationEnabled'] == false
                        ? 'settings.privacy.events.off'
                        : c.state == 'active'
                        ? 'settings.privacy.events.active'
                        : 'settings.privacy.events.savedPaused',
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
