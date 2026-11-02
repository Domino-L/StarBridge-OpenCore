import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/routing/exit_application_intent.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'data_location_copy.dart';
import 'data_location_port.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

Future<void> showDataLocationDialog(
  BuildContext context,
  DataLocationPort port, {
  InteractionSource? source,
}) async {
  final canExit = Actions.maybeFind<ExitApplicationIntent>(context) != null;
  var operationSource = source ?? StarBridgeActivationOrigin.sourceOf(context);
  final choice = await showStarBridgeDialog<DataLocationMigrationChoice>(
    context,
    source: operationSource,
    builder: (_) => DataLocationDialog(
      port: port,
      exitAvailable: canExit,
      onSourceChanged: (value) => operationSource = value,
    ),
  );
  if (choice == null ||
      !context.mounted ||
      port is! DataLocationMigrationPort) {
    return;
  }
  Actions.maybeInvoke(
    context,
    ExitApplicationIntent(
      beforeExit: () async {
        try {
          await port.confirmMigration(choice.ticket);
          return true;
        } on Object catch (error) {
          if (context.mounted) {
            if (ScaffoldMessenger.maybeOf(context) != null) {
              showStarBridgeSnackBar(
                context,
                starBridgeTimedSnackBar(
                  content: Text(
                    dataLocationCopy(
                      context,
                      error is BridgeClientException &&
                              error.code == 'dataLocation.wpf_running'
                          ? 'migrationWpfRunning'
                          : 'migrationStartFailed',
                    ),
                  ),
                ),
                source: operationSource,
              );
            }
          }
          return false;
        }
      },
    ),
  );
}

class DataLocationDialog extends StatefulWidget {
  const DataLocationDialog({
    required this.port,
    this.exitAvailable = false,
    this.onSourceChanged,
    super.key,
  });
  final DataLocationPort port;
  final bool exitAvailable;

  /// Presentation origin only. Migration and exit remain owned by the Port
  /// and the existing ExitApplicationIntent handoff.
  final ValueChanged<InteractionSource>? onSourceChanged;

  @override
  State<DataLocationDialog> createState() => _DataLocationDialogState();
}

class _DataLocationDialogState extends State<DataLocationDialog> {
  DataLocation? _location;
  bool _loading = true;
  bool _busy = false;
  String? _feedback;
  int _revision = 0;
  Timer? _retryTimer;
  int _failedReads = 0;
  InteractionSource _source = InteractionSource.programmatic;
  StarBridgeDialogRoute<bool>? _confirmation;

  bool get _canMigrate =>
      !_loading &&
      _location?.exists == true &&
      widget.exitAvailable &&
      widget.port is DataLocationMigrationPort &&
      (widget.port as DataLocationMigrationPort).migrationAvailable;

  void _rememberSource(InteractionSource source) {
    _source = source;
    widget.onSourceChanged?.call(source);
  }

  void _retireConfirmation() {
    final route = _confirmation;
    _confirmation = null;
    retireStarBridgeDialog(route);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _retireConfirmation();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(DataLocationDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port) {
      _source = InteractionSource.programmatic;
      _retireConfirmation();
      unawaited(_read());
    } else if (!_canMigrate) {
      _retireConfirmation();
    }
  }

  Future<void> _read() async {
    _retryTimer?.cancel();
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _location = null;
      _feedback = null;
      _busy = false;
    });
    DataLocation? location;
    try {
      location = await widget.port.read();
    } on Object {
      /* Render retry, never raw errors. */
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _location = location;
      _loading = false;
    });
    if (location == null) {
      const delays = [2, 5, 15, 30];
      final seconds = delays[_failedReads.clamp(0, delays.length - 1)];
      _failedReads++;
      _retryTimer = Timer(Duration(seconds: seconds), _read);
    } else {
      _failedReads = 0;
    }
  }

  Future<void> _act(bool copy) async {
    final location = _location;
    if (_busy || location == null || (!copy && !location.exists)) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    var feedback = copy ? 'copied' : 'opened';
    try {
      if (copy) {
        await Clipboard.setData(ClipboardData(text: location.path));
      } else {
        await widget.port.open();
      }
    } on Object {
      feedback = copy ? 'copyFailed' : 'openFailed';
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _busy = false;
      _feedback = feedback;
    });
  }

  Future<void> _chooseMigration() async {
    if (_busy || !_canMigrate) {
      return;
    }
    final port = widget.port as DataLocationMigrationPort;
    final revision = _revision;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final choice = await port.chooseMigration();
      if (!mounted || revision != _revision) return;
      if (choice == null || !_canMigrate) {
        setState(() => _busy = false);
        return;
      }
      late StarBridgeDialogRoute<bool> confirmation;
      final confirmed = await showStarBridgeDialog<bool>(
        context,
        source: _source,
        onRouteCreated: (route) {
          confirmation = route;
          setState(() => _confirmation = route);
        },
        builder: (dialogContext) => AlertDialog(
          key: const Key('data-location-confirm-dialog'),
          title: Text(dataLocationCopy(dialogContext, 'confirmTitle')),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(dataLocationCopy(dialogContext, 'confirmBody')),
                SizedBox(height: dialogContext.tokens.space.md),
                Text(
                  dataLocationCopy(dialogContext, 'from'),
                  style: Theme.of(dialogContext).textTheme.labelLarge,
                ),
                SelectableText(choice.source),
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: dialogContext.tokens.space.sm,
                  ),
                  child: const StarBridgeIcon(
                    StarBridgeIconSemantic.menuDown,
                    size: 18,
                  ),
                ),
                Text(
                  dataLocationCopy(dialogContext, 'to'),
                  style: Theme.of(dialogContext).textTheme.labelLarge,
                ),
                SelectableText(choice.destination),
              ],
            ),
          ),
          actions: [
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: const Key('data-location-keep'),
              onActivate: (source) {
                if (!mounted ||
                    revision != _revision ||
                    !confirmation.isCurrent) {
                  return;
                }
                if (!_canMigrate) {
                  _retireConfirmation();
                  return;
                }
                _rememberSource(source);
                dismissStarBridgeDialog(
                  dialogContext,
                  result: false,
                  source: source,
                );
              },
              child: Text(dataLocationCopy(dialogContext, 'keep')),
            ),
            StarBridgeActionButton(
              kind: StarBridgeActionKind.primary,
              controlKey: const Key('data-location-confirm'),
              onActivate: (source) {
                if (!mounted ||
                    revision != _revision ||
                    !confirmation.isCurrent) {
                  return;
                }
                if (!_canMigrate) {
                  _retireConfirmation();
                  return;
                }
                _rememberSource(source);
                dismissStarBridgeDialog(
                  dialogContext,
                  result: true,
                  source: source,
                );
              },
              child: Text(dataLocationCopy(dialogContext, 'migrate')),
            ),
          ],
        ),
      );
      if (_confirmation == confirmation) _confirmation = null;
      if (!mounted || revision != _revision) return;
      if (confirmed == true && _canMigrate) {
        dismissStarBridgeDialog(context, result: choice, source: _source);
      } else {
        setState(() => _busy = false);
      }
    } on Object {
      if (mounted && revision == _revision) {
        setState(() {
          _busy = false;
          _feedback = 'migrationChooseFailed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String t(String key) => dataLocationCopy(context, key);
    final location = _location;
    return AlertDialog(
      key: const Key('data-location-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(t('title')),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading)
              _LocationWaiting(
                source: resolveStarBridgeInitialReadSource(context, _source),
              )
            else if (location == null)
              Text(t('failed'))
            else ...[
              Text(t('path'), style: Theme.of(context).textTheme.labelLarge),
              SizedBox(height: tokens.space.sm),
              SelectableText(
                location.path,
                key: const Key('data-location-path'),
              ),
              if (!location.exists) ...[
                SizedBox(height: tokens.space.sm),
                Text(
                  t('missing'),
                  style: TextStyle(color: tokens.colors.warning),
                ),
              ],
              SizedBox(height: tokens.space.md),
              Wrap(
                spacing: tokens.space.sm,
                runSpacing: tokens.space.sm,
                children: [
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.primary,
                    controlKey: const Key('data-location-open'),
                    onActivate: _busy || !location.exists
                        ? null
                        : (source) {
                            _rememberSource(source);
                            unawaited(_act(false));
                          },
                    child: Text(t('open')),
                  ),
                  StarBridgeActionButton(
                    controlKey: const Key('data-location-copy'),
                    onActivate: _busy
                        ? null
                        : (source) {
                            _rememberSource(source);
                            unawaited(_act(true));
                          },
                    child: Text(t('copy')),
                  ),
                ],
              ),
            ],
            // Choosing a folder/opening it is an async wait. Once the
            // confirmation is shown we are waiting for the user, not IO.
            if (_busy && _confirmation == null) ...[
              SizedBox(height: tokens.space.sm),
              _LocationWaiting(source: _source),
            ],
            if (_feedback != null)
              Padding(
                padding: EdgeInsets.only(top: tokens.space.sm),
                child: Semantics(liveRegion: true, child: Text(t(_feedback!))),
              ),
            SizedBox(height: tokens.space.md),
            OutlinedButtonTheme(
              data: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  disabledForegroundColor: tokens.colors.textSecondary,
                ),
              ),
              child: StarBridgeActionButton(
                controlKey: const Key('data-location-move'),
                onActivate: _busy || !_canMigrate
                    ? null
                    : (source) {
                        _rememberSource(source);
                        unawaited(_chooseMigration());
                      },
                child: Text(t('move')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!_loading && _location == null)
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('data-location-retry'),
            onActivate: _busy
                ? null
                : (source) {
                    _rememberSource(source);
                    unawaited(_read());
                  },
            child: Text(t('retry')),
          ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          controlKey: const Key('data-location-close'),
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source),
          child: Text(t('close')),
        ),
      ],
    );
  }
}

class _LocationWaiting extends StatelessWidget {
  const _LocationWaiting({required this.source});
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
