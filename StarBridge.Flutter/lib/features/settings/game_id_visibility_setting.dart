import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
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
              // 11-15 decision 甲: one callsign for SCM accounts, edited here or in
              // the profile editor; the Relay is written first, Hong Kong kept in step.
              if (c.hasCallsign) ...[
                SizedBox(height: tokens.space.sm),
                _CallsignRow(controller: c),
                Text(strings.text('settings.privacy.gameId.callsignHint')),
                if (c.needsCallsignToHide)
                  Text(
                    strings.text(
                      locations == 15
                          ? 'settings.privacy.gameId.needCallsign'
                          : 'settings.privacy.gameId.hiddenWithoutCallsign',
                    ),
                    key: const Key('game-id-needs-callsign'),
                  ),
                // Every out-of-step state can be retried by tapping its line.
                if (c.mirror != 'synced')
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StarBridgeActionButton(
                      kind: StarBridgeActionKind.quiet,
                      controlKey: Key('game-id-mirror-${c.mirror}'),
                      onActivate: c.busy ? null : (_) => c.retrySync(),
                      child: Text(
                        strings.text(switch (c.mirror) {
                          'restorePending' =>
                            'settings.privacy.gameId.restorePending',
                          'unknown' => 'settings.privacy.gameId.mirrorUnknown',
                          _ => switch (c.lastSave) {
                            'callsign' =>
                              'settings.privacy.gameId.pendingCallsign',
                            'settings' =>
                              'settings.privacy.gameId.pendingSettings',
                            _ => 'settings.privacy.gameId.pendingFound',
                          },
                        }),
                      ),
                    ),
                  ),
                SizedBox(height: tokens.space.sm),
              ],
              Text(
                strings.text(
                  c.error != null
                      ? 'settings.privacy.gameId.unavailable'
                      : c.snapshot == null
                      ? 'settings.privacy.loading'
                      // SCM accounts without a callsign get the decision 乙 notes
                      // above; these two texts are for legacy accounts only.
                      : c.snapshot!['canConfigure'] == false &&
                            !c.needsCallsignToHide
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
                                    _switchable(c, locations, item.key) &&
                                    !(drafts?.saving ?? false),
                                trailing: control,
                              ),
                        value: locations & item.key != 0,
                        onChanged:
                            _switchable(c, locations, item.key) &&
                                !(drafts?.saving ?? false)
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
                                    if (!c.canChange(next)) return false;
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

// Decision 乙: without an independent callsign a switch can only be turned on.
bool _switchable(GameIdVisibilityController c, int locations, int bit) =>
    c.canEdit || (c.needsCallsignToHide && !c.busy && locations & bit == 0);

class _CallsignRow extends StatefulWidget {
  const _CallsignRow({required this.controller});
  final GameIdVisibilityController controller;
  @override
  State<_CallsignRow> createState() => _CallsignRowState();
}

class _CallsignRowState extends State<_CallsignRow> {
  final _text = TextEditingController();
  String? _shown;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, strings = AppStrings.of(context);
    final tokens = context.tokens;
    // Follow the confirmed value (another device, the profile editor) unless the
    // user has typed a different draft here.
    final current = c.callsign ?? '';
    if (_shown != current) {
      if (_text.text == (_shown ?? '')) _text.text = current;
      _shown = current;
    }
    final draft = _text.text.trim();
    final invalid = !GameIdVisibilityController.validCallsign(_text.text);
    // Clearing the callsign while some place still hides the game ID is refused
    // up front (decision 乙): switch those places to "show" first.
    final clearBlocked =
        draft.isEmpty && current.isNotEmpty && c.locations != 15;
    final error = invalid
        ? 'settings.privacy.gameId.callsignInvalid'
        : clearBlocked
        ? 'settings.privacy.gameId.clearNeedsShow'
        : switch (c.callsignError) {
            'invalid' => 'settings.privacy.gameId.callsignInvalid',
            'conflict' => 'settings.privacy.gameId.callsignConflict',
            'hiddenRequiresCallsign' =>
              'settings.privacy.gameId.clearNeedsShow',
            'unavailable' => 'settings.privacy.gameId.callsignUnavailable',
            _ => null,
          };
    final canSave = !c.busy && !invalid && !clearBlocked && draft != current;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: StarBridgeFieldFrame(
            enabled: !c.busy,
            error: error != null,
            builder: (_, focus) => TextField(
              key: const Key('game-id-callsign-field'),
              focusNode: focus,
              controller: _text,
              enabled: !c.busy,
              maxLength: 20,
              decoration: InputDecoration(
                labelText: strings.text('settings.privacy.gameId.callsign'),
                errorText: error == null ? null : strings.text(error),
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        SizedBox(width: tokens.space.md),
        Padding(
          padding: EdgeInsets.only(top: tokens.space.xs),
          child: StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: const Key('game-id-callsign-save'),
            onActivate: canSave
                ? (_) async {
                    final saved = await c.saveCallsign(_text.text);
                    if (saved && mounted) {
                      setState(() {
                        _shown = c.callsign ?? '';
                        _text.text = _shown!;
                      });
                    }
                  }
                : null,
            child: Text(strings.text('settings.privacy.gameId.callsignSave')),
          ),
        ),
      ],
    );
  }
}
