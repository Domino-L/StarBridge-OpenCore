import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'event_scope_editor.dart';
import 'event_sharing_controller.dart';
import 'privacy_page_drafts.dart';
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

  void _prepareInitialDraft() {
    final c = controller;
    if (_drafts == null ||
        c.accountKey == null ||
        _preparedOwner == c.accountKey ||
        c.snapshot?['revision'] != 0 ||
        c.targets == null ||
        c.error != null) {
      return;
    }
    final owner = c.accountKey;
    _preparedOwner = owner;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || owner != c.accountKey) return;
      const all = EventSharingChoice(
        enabled: true,
        selectedTypes: EventSharingChoice.allTypes,
      );
      final memberships = [
        for (final t in c.targets!.communities) '${t.code}:${t.joinedAt}',
      ].join('|');
      final choices = <String?, EventSharingChoice>{
        null: all,
        for (final t in c.targets!.communities) t.code: all,
      };
      _drafts?.edit('event-choices', <String?, EventSharingChoice>{}, choices, (
        next,
      ) async {
        if (owner != c.accountKey ||
            !c.canEdit ||
            c.snapshot?['revision'] != 0 ||
            [for (final t in c.targets!.communities) '${t.code}:${t.joinedAt}']
                    .join('|') !=
                memberships) {
          return false;
        }
        await c.saveChoices(next);
        return c.error == null;
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
          if (c.snapshot?['revision'] != revision ||
              [
                    for (final t in c.targets?.communities ?? [])
                      '${t.code}:${t.joinedAt}',
                  ].join('|') !=
                  memberships) {
            return false;
          }
          if (!c.canEdit) return false;
          await c.saveChoices(value);
          return c.error == null;
        });
      }

      return SingleChildScrollView(
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
                if (c.busy) const LinearProgressIndicator(),
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
                      choice: choices[target.code]!,
                      canEdit: c.canEdit && !(drafts?.saving ?? false),
                      onChanged: (value) => change(target.code, value),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
