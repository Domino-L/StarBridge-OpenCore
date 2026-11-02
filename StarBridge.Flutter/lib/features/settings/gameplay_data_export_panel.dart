import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'gameplay_data_export_copy.dart';
import 'gameplay_data_export_port.dart';

/// Embed in the existing local-data-management detail; does not replace other actions.
class GameplayDataExportPanel extends StatefulWidget {
  const GameplayDataExportPanel({required this.port, super.key});
  final GameplayDataExportPort port;
  @override
  State<GameplayDataExportPanel> createState() =>
      _GameplayDataExportPanelState();
}

class _GameplayDataExportPanelState extends State<GameplayDataExportPanel> {
  bool _busy = false;
  GameplayExportOutcome? _outcome;
  int _epoch = 0;
  int _completed = 0;
  InteractionSource _source = InteractionSource.programmatic;

  @override
  void didUpdateWidget(GameplayDataExportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.port != oldWidget.port) {
      oldWidget.port.cancel();
      _epoch++;
      _busy = false;
      _outcome = null;
      _completed = 0;
      _source = InteractionSource.programmatic;
    }
  }

  @override
  void dispose() {
    _epoch++;
    widget.port.cancel();
    super.dispose();
  }

  Future<void> _export(
    InteractionSource source,
    GameplayDataExportPort owner,
    int epoch,
  ) async {
    if (!mounted ||
        _busy ||
        epoch != _epoch ||
        !identical(owner, widget.port)) {
      return;
    }
    final locale = Localizations.localeOf(context);
    final language = locale.languageCode == 'en'
        ? 'en'
        : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
        ? 'zh-TW'
        : 'zh-CN';
    setState(() {
      _busy = true;
      _outcome = null;
      _source = source;
    });
    GameplayExportOutcome outcome;
    try {
      outcome = await runStarBridgeActivation(
        source,
        () => owner.export(language),
      );
    } on Object {
      outcome = GameplayExportOutcome.unknown;
    }
    if (!mounted || epoch != _epoch || !identical(owner, widget.port)) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
      if (outcome != GameplayExportOutcome.cancelled) _completed++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.port, epoch = _epoch;
    final tokens = context.tokens;
    String t(String key) => gameplayExportCopy(context, key);
    return StarBridgeInteractionRegion(
      child: Builder(
        builder: (context) {
          final data = InteractionScope.of(context);
          final effective = data.copyWith(
            reduceMotion:
                data.reduceMotion || _source == InteractionSource.keyboard,
          );
          return Stack(
            children: [
              Column(
                key: const Key('gameplay-data-export'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t('description')),
                  SizedBox(height: tokens.space.md),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StarBridgeActionButton(
                      controlKey: const Key('gameplay-data-export-start'),
                      semanticLabel: t('title'),
                      kind: StarBridgeActionKind.primary,
                      onActivate: _busy
                          ? null
                          : (source) => _export(source, owner, epoch),
                      child: Text(t(_busy ? 'working' : 'title')),
                    ),
                  ),
                  if (_busy)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.space.sm),
                      child: Semantics(
                        liveRegion: true,
                        child: InteractionScope(
                          data: effective,
                          child: SuiteBusyLabel(t('working')),
                        ),
                      ),
                    ),
                  if (_outcome != null)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.space.sm),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(t(_outcome!.name)),
                      ),
                    ),
                ],
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: InteractionScope(
                      data: effective,
                      child: SuiteBusyFrame(
                        key: ValueKey(epoch),
                        busy: _busy,
                        doneToken: _completed,
                        doneOutcome: _outcome == GameplayExportOutcome.saved
                            ? TaskOutcome.success
                            : TaskOutcome.failure,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
