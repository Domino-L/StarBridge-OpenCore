import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../platform/window/gameplay_log_picker.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../account/account_models.dart';
import 'game_log_controller.dart';

class GameLogPanel extends StatefulWidget {
  const GameLogPanel({
    required this.controller,
    this.pickLog = pickGameplayLog,
    super.key,
  });
  final GameLogController controller;
  final Future<String?> Function() pickLog;
  @override
  State<GameLogPanel> createState() => _GameLogPanelState();
}

class _GameLogPanelState extends State<GameLogPanel> {
  InteractionSource? _source;
  int _presentationEpoch = 0;
  (AccountSessionState, int)? _accountKey;
  StarBridgeDialogRoute<bool>? _removeRoute;
  Object? _removalIntent;
  String? _removeChannel;
  late StreamSubscription<BridgeEnvelope> _events;
  final _addVersionFocus = FocusNode();
  GameLogController get controller => widget.controller;
  Future<String?> Function() get pickLog => widget.pickLog;

  @override
  void initState() {
    super.initState();
    _accountChanged();
    controller.account.addListener(_accountChanged);
    controller.addListener(_controllerChanged);
    _listenToEvents();
  }

  void _listenToEvents() {
    final owner = controller;
    _events = owner.session.events.listen((event) {
      if (!mounted || controller != owner) return;
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _presentationEpoch++;
        _source = null;
        _retireRemoval();
      }
    });
  }

  void _controllerChanged() {
    if (_removalIntent != null &&
        (!controller.value.visible ||
            controller.value.busy ||
            !controller.value.channels.contains(_removeChannel))) {
      _retireRemoval();
    }
  }

  void _retireRemoval() {
    final route = _removeRoute;
    _removeRoute = null;
    _removalIntent = null;
    _removeChannel = null;
    retireStarBridgeDialog(route);
  }

  void _accountChanged() {
    final projection = controller.account.value;
    final key = (projection.sessionState, projection.generation);
    if (_accountKey == key) return;
    _accountKey = key;
    _presentationEpoch++;
    _source = null;
    _retireRemoval();
  }

  @override
  void didUpdateWidget(GameLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.account.removeListener(_accountChanged);
      oldWidget.controller.removeListener(_controllerChanged);
      unawaited(_events.cancel());
      controller.account.addListener(_accountChanged);
      controller.addListener(_controllerChanged);
      _listenToEvents();
      _accountKey = null;
      _accountChanged();
    }
  }

  @override
  void dispose() {
    controller.account.removeListener(_accountChanged);
    controller.removeListener(_controllerChanged);
    unawaited(_events.cancel());
    _retireRemoval();
    _addVersionFocus.dispose();
    super.dispose();
  }

  // Only a presentation fact. The original controller still owns busy state,
  // file selection, commands, account epochs and all acknowledgements.
  void _act(InteractionSource source, Future<void> Function() command) {
    _source = source;
    final epoch = ++_presentationEpoch;
    unawaited(
      command().whenComplete(() {
        if (mounted && epoch == _presentationEpoch) _source = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GameLogView>(
    valueListenable: controller,
    builder: (context, value, _) {
      if (!value.visible) return const SizedBox.shrink();
      final t = context.tokens;
      String text(String key) => AppStrings.of(context).text('gameLog.$key');
      final status =
          value.error ?? (value.match != 'unknown' ? value.match : value.state);
      final warning =
          value.error != null ||
          const {
            'mismatch',
            'ambiguous',
            'unreadable',
            'differentInstallation',
            'unknown',
            'notFound',
            'multipleLogs',
            'otherVersion',
          }.contains(status);
      final color = warning
          ? t.colors.warning
          : status == 'match'
          ? t.colors.success
          : t.colors.textSecondary;
      final enabled = !value.busy && value.error != 'unsupported';
      return StarBridgeSurface(
        role: SurfaceRole.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StarBridgeIcon(
                  StarBridgeIconSemantic.account,
                  size: t.icons.medium,
                  color: t.colors.accent,
                ),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: Text(
                    text('title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space.sm),
            Text(
              text('description'),
              style: TextStyle(color: t.colors.textSecondary),
            ),
            SizedBox(height: t.space.md),
            Text(text('version')),
            SizedBox(height: t.space.sm),
            Wrap(
              spacing: t.space.sm,
              runSpacing: t.space.sm,
              children: [
                for (final channel in value.channels)
                  StarBridgeChoiceChip.input(
                    key: ValueKey(('game-log-version', channel)),
                    controlKey: Key('game-log-version-$channel'),
                    deleteKey: Key('game-log-remove-$channel'),
                    label: const {'LIVE', 'PTU'}.contains(channel)
                        ? text(channel)
                        : channel,
                    selected: value.channel == channel,
                    onSelected: enabled
                        ? (selected) {
                            if (selected && value.channel != channel) {
                              _act(
                                currentStarBridgeActivationSource,
                                () => controller.run(
                                  command: 'configure',
                                  channel: channel,
                                ),
                              );
                            }
                          }
                        : null,
                    onDeleted: enabled && channel != 'LIVE'
                        ? (source) => _act(
                            source,
                            () =>
                                _removeVersion(context, channel, text, source),
                          )
                        : null,
                    deleteIcon: channel == 'LIVE'
                        ? null
                        : StarBridgeIcon(
                            StarBridgeIconSemantic.remove,
                            size: t.icons.small,
                          ),
                    deleteLabel: '${text('removeVersion')} · $channel',
                  ),
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('game-log-add-version'),
                  focusNode: _addVersionFocus,
                  onActivate: enabled
                      ? (source) =>
                            _act(source, () => controller.addVersion(pickLog))
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StarBridgeIcon(
                        StarBridgeIconSemantic.add,
                        size: t.icons.small,
                      ),
                      SizedBox(width: t.space.sm),
                      Text(text('addVersion')),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space.sm),
            Text(
              text(
                value.verifiedChannels.contains(value.channel)
                    ? 'versionReady'
                    : 'versionPending',
              ),
              style: TextStyle(color: t.colors.textSecondary),
            ),
            SizedBox(height: t.space.md),
            Text(
              text(value.selection),
              style: TextStyle(color: t.colors.textSecondary),
            ),
            SizedBox(height: t.space.sm),
            if (value.path != null) ...[
              SelectableText(
                value.path!,
                style: TextStyle(color: t.colors.textSecondary),
              ),
              SizedBox(height: t.space.md),
            ],
            Wrap(
              spacing: t.space.xl,
              runSpacing: t.space.sm,
              children: [
                Text('${text('expected')} · ${value.expectedHandle ?? '—'}'),
                Text('${text('detected')} · ${value.handle ?? '—'}'),
                if (value.handle == null && value.recentHandle != null)
                  Text('${text('recentDetected')} · ${value.recentHandle}'),
              ],
            ),
            SizedBox(height: t.space.md),
            Row(
              children: [
                if (value.busy) ...[
                  SizedBox(
                    width: 32,
                    child: _LogWaiting(
                      source:
                          _source ??
                          resolveStarBridgeInitialReadSource(
                            context,
                            InteractionSource.programmatic,
                          ),
                    ),
                  ),
                  SizedBox(width: t.space.sm),
                ],
                Expanded(
                  child: Text(
                    text(value.busy ? 'busy' : status),
                    style: TextStyle(color: color),
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space.md),
            Wrap(
              spacing: t.space.sm,
              key: const Key('game-log-actions'),
              runSpacing: t.space.sm,
              children: [
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.primary,
                  controlKey: const Key('game-log-find'),
                  onActivate: enabled
                      ? (source) =>
                            _act(source, () => controller.run(command: 'find'))
                      : null,
                  child: Text(text('find')),
                ),
                StarBridgeActionButton(
                  controlKey: const Key('game-log-select'),
                  onActivate: enabled
                      ? (source) => _act(source, () => controller.pick(pickLog))
                      : null,
                  child: Text(text('select')),
                ),
                if (value.enabled)
                  StarBridgeActionButton(
                    controlKey: const Key('game-log-stop'),
                    onActivate: enabled
                        ? (source) => _act(
                            source,
                            () => controller.run(command: 'stop'),
                          )
                        : null,
                    child: Text(text('stop')),
                  )
                else
                  StarBridgeActionButton(
                    controlKey: const Key('game-log-resume'),
                    onActivate: enabled
                        ? (source) => _act(
                            source,
                            () => controller.run(command: 'resume'),
                          )
                        : null,
                    child: Text(text('resume')),
                  ),
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('game-log-retry'),
                  onActivate: enabled
                      ? (source) =>
                            _act(source, () => controller.run(command: 'retry'))
                      : null,
                  child: Text(text('retry')),
                ),
              ],
            ),
            if (value.observedAt case final checkedAt?) ...[
              SizedBox(height: t.space.sm),
              Text(
                '${text('lastChecked')} · '
                '${MaterialLocalizations.of(context).formatShortDate(checkedAt)} '
                '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(checkedAt), alwaysUse24HourFormat: Localizations.localeOf(context).languageCode == 'zh')}',
                key: const Key('game-log-last-checked'),
                style: TextStyle(color: t.colors.textSecondary),
              ),
            ],
          ],
        ),
      );
    },
  );

  Future<void> _removeVersion(
    BuildContext context,
    String channel,
    String Function(String key) text,
    InteractionSource source,
  ) async {
    final owner = controller;
    if (_removalIntent != null ||
        channel == 'LIVE' ||
        !owner.value.visible ||
        owner.value.busy ||
        owner.value.error == 'unsupported' ||
        !owner.value.channels.contains(channel)) {
      return;
    }
    final intent = Object();
    _removalIntent = intent;
    _removeChannel = channel;
    bool valid() =>
        mounted && controller == owner && identical(_removalIntent, intent);
    final remove = await showStarBridgeDialog<bool>(
      context,
      source: source,
      onRouteCreated: (route) => _removeRoute = route,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          text('removeVersionTitle').replaceAll('{version}', channel),
        ),
        content: Text(text('removeVersionDetail')),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('game-log-keep-version'),
            onActivate: (source) {
              if (!valid() || _removeRoute?.isCurrent != true) return;
              _source = source;
              dismissStarBridgeDialog(
                dialogContext,
                result: false,
                source: source,
              );
            },
            child: Text(text('keepVersion')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: const Key('game-log-confirm-remove'),
            onActivate: (source) {
              if (!valid() || _removeRoute?.isCurrent != true) return;
              _source = source;
              dismissStarBridgeDialog(
                dialogContext,
                result: true,
                source: source,
              );
            },
            child: Text(text('removeVersion')),
          ),
        ],
      ),
    );
    if (!valid()) return;
    _removeRoute = null;
    _removalIntent = null;
    _removeChannel = null;
    if (remove == true && context.mounted) {
      final confirmationSource = _source ?? source;
      final confirmationEpoch = _presentationEpoch;
      await owner.run(command: 'removeVersion', channel: channel);
      bool canRestoreFocus() =>
          mounted &&
          controller == owner &&
          confirmationEpoch == _presentationEpoch &&
          confirmationSource == InteractionSource.keyboard &&
          !owner.value.channels.contains(channel) &&
          ModalRoute.of(context)?.isCurrent == true;
      if (canRestoreFocus()) {
        // The receipt re-enables targets on the next build. Requesting focus
        // while the old ExcludeFocus is still mounted would be discarded.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (canRestoreFocus()) _addVersionFocus.requestFocus();
        });
      }
    }
  }
}

class _LogWaiting extends StatelessWidget {
  const _LogWaiting({required this.source});
  final InteractionSource source;

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context);
        return InteractionScope(
          data: data.copyWith(
            reduceMotion:
                data.reduceMotion || source == InteractionSource.keyboard,
          ),
          child: const SuiteProgressBar(
            value: null,
            phase: ProgressPhase.running,
          ),
        );
      },
    ),
  );
}
