import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'game_id_visibility_controller.dart';
import 'privacy_page_drafts.dart';
import 'sharing_settings_waiting.dart';

class GameIdVisibilitySetting extends StatefulWidget {
  const GameIdVisibilitySetting({required this.session, super.key});
  final BridgeClientSession session;
  @override
  State<GameIdVisibilitySetting> createState() =>
      _GameIdVisibilitySettingState();
}

class _GameIdVisibilitySettingState extends State<GameIdVisibilitySetting> {
  late final controller = GameIdVisibilityController(widget.session);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller,
          strings = AppStrings.of(context),
          tokens = context.tokens;
      final drafts = PrivacyDraftScope.of(context);
      final locations = drafts?.value('game-id', c.locations) ?? c.locations;
      final revision = c.snapshot?['revision'];
      final identityStamp = c.snapshot?['identityStamp'];
      return Card(
        child: Padding(
          padding: EdgeInsets.all(tokens.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.text('settings.privacy.gameId.title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                strings.text(
                  c.error != null
                      ? 'settings.privacy.gameId.unavailable'
                      : c.snapshot == null
                      ? 'settings.privacy.loading'
                      : c.snapshot!['canConfigure'] == false
                      ? c.locations == 0
                            ? 'settings.privacy.gameId.unverified'
                            : 'settings.privacy.gameId.required'
                      : 'settings.privacy.gameId.help',
                ),
              ),
              SharingSettingsWaiting(
                owner: c,
                pending: () => c.busy && c.snapshot == null,
                titleKey: 'settings.privacy.gameId.title',
                labelKey: 'settings.privacy.loading',
              ),
              Wrap(
                spacing: tokens.space.md,
                children: [
                  for (final item in const {
                    1: 'organization',
                    2: 'room',
                    4: 'friends',
                    8: 'profile',
                  }.entries)
                    SizedBox(
                      width: 160,
                      child: StarBridgeSwitch.tile(
                        controlKey: Key('game-id-${item.value}'),
                        preserveNativeTile: true,
                        label: strings.text(
                          'settings.privacy.gameId.${item.value}',
                        ),
                        titleWidget: Text(
                          strings.text('settings.privacy.gameId.${item.value}'),
                        ),
                        rowBuilder: (control) =>
                            resolveStarBridgeInteraction(context).suite ==
                                InteractionSuite.standard
                            ? control
                            : ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  strings.text(
                                    'settings.privacy.gameId.${item.value}',
                                  ),
                                ),
                                enabled:
                                    c.canEdit && !(drafts?.saving ?? false),
                                trailing: control,
                              ),
                        value: locations & item.key != 0,
                        onChanged: c.canEdit && !(drafts?.saving ?? false)
                            ? (value) {
                                if (drafts == null) {
                                  c.change(item.key, value);
                                  return;
                                }
                                drafts.edit(
                                  'game-id',
                                  c.locations,
                                  value
                                      ? locations | item.key
                                      : locations & ~item.key,
                                  (next) async {
                                    if (c.locations == next &&
                                        c.error == null) {
                                      return true;
                                    }
                                    if (c.snapshot?['revision'] != revision ||
                                        c.snapshot?['identityStamp'] !=
                                            identityStamp) {
                                      return false;
                                    }
                                    if (!c.canEdit) return false;
                                    await c.saveLocations(next);
                                    return c.error == null &&
                                        c.locations == next;
                                  },
                                );
                              }
                            : null,
                      ),
                    ),
                ],
              ),
              SharingSettingsWaiting(
                owner: c,
                pending: () => c.busy && c.snapshot != null,
                titleKey: 'settings.privacy.gameId.title',
                labelKey: 'privacy.local.saving',
              ),
            ],
          ),
        ),
      );
    },
  );
}
