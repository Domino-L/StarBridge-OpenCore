import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
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

  @override
  void didUpdateWidget(GameplayDataExportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.port != oldWidget.port) {
      oldWidget.port.cancel();
      _epoch++;
      _busy = false;
      _outcome = null;
    }
  }

  @override
  void dispose() {
    _epoch++;
    widget.port.cancel();
    super.dispose();
  }

  Future<void> _export() async {
    if (_busy) return;
    final epoch = _epoch;
    final locale = Localizations.localeOf(context);
    final language = locale.languageCode == 'en'
        ? 'en'
        : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
        ? 'zh-TW'
        : 'zh-CN';
    setState(() {
      _busy = true;
      _outcome = null;
    });
    GameplayExportOutcome outcome;
    try {
      outcome = await widget.port.export(language);
    } on Object {
      outcome = GameplayExportOutcome.unknown;
    }
    if (!mounted || epoch != _epoch) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String t(String key) => gameplayExportCopy(context, key);
    return Column(
      key: const Key('gameplay-data-export'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('description')),
        SizedBox(height: tokens.space.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            key: const Key('gameplay-data-export-start'),
            onPressed: _busy ? null : _export,
            child: Text(t(_busy ? 'working' : 'title')),
          ),
        ),
        if (_outcome != null)
          Padding(
            padding: EdgeInsets.only(top: tokens.space.sm),
            child: Semantics(liveRegion: true, child: Text(t(_outcome!.name))),
          ),
      ],
    );
  }
}
