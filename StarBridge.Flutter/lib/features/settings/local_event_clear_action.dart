import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'local_event_clear.dart';

class LocalEventClearAction extends StatefulWidget {
  const LocalEventClearAction({
    required this.port,
    required this.enabled,
    required this.refresh,
    super.key,
  });
  final LocalEventClearPort port;
  final bool enabled;
  final Future<void> Function() refresh;
  @override
  State<LocalEventClearAction> createState() => _LocalEventClearActionState();
}

class _LocalEventClearActionState extends State<LocalEventClearAction> {
  bool _busy = false;
  int _epoch = 0;
  String? _result;
  bool _requesting = false;
  int _completed = 0;
  InteractionSource _source = InteractionSource.programmatic;
  StarBridgeDialogRoute<bool>? _confirmation;
  @override
  void dispose() {
    _epoch++;
    retireStarBridgeDialog(_confirmation);
    _confirmation = null;
    widget.port.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(LocalEventClearAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port ||
        oldWidget.refresh != widget.refresh ||
        (oldWidget.enabled && !widget.enabled && _confirmation != null)) {
      _epoch++;
      retireStarBridgeDialog(_confirmation);
      _confirmation = null;
      oldWidget.port.cancel();
      _busy = false;
      _result = null;
      _requesting = false;
      _completed = 0;
      _source = InteractionSource.programmatic;
    }
  }

  Future<void> _clear(
    InteractionSource source,
    LocalEventClearPort owner,
    Future<void> Function() refresh,
    int epoch,
  ) async {
    bool active() =>
        mounted &&
        epoch == _epoch &&
        identical(owner, widget.port) &&
        refresh == widget.refresh;
    if (!active() || _busy || !widget.enabled) return;
    var confirmedSource = source;
    setState(() {
      _busy = true;
      _result = null;
      _source = source;
    });
    StarBridgeDialogRoute<bool>? confirmation;
    final yes = await showStarBridgeDialog<bool>(
      context,
      source: source,
      onRouteCreated: (route) => _confirmation = confirmation = route,
      builder: (context) => AlertDialog(
        title: Text(_text(context, 'confirm')),
        content: Text(_text(context, 'scope')),
        actions: [
          StarBridgeActionButton(
            controlKey: const Key('history-clear-cancel'),
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) {
              if (!active() || ModalRoute.of(context)?.isCurrent != true) {
                return;
              }
              dismissStarBridgeDialog(context, source: source, result: false);
            },
            child: Text(_text(context, 'cancel')),
          ),
          StarBridgeActionButton(
            controlKey: const Key('history-clear-confirm'),
            kind: StarBridgeActionKind.quiet,
            tone: ActionTone.danger,
            onActivate: (source) {
              if (!active() ||
                  !widget.enabled ||
                  ModalRoute.of(context)?.isCurrent != true) {
                return;
              }
              confirmedSource = source;
              dismissStarBridgeDialog(context, source: source, result: true);
            },
            child: Text(_text(context, 'clear')),
          ),
        ],
      ),
    );
    if (_confirmation == confirmation) _confirmation = null;
    if (!active()) return;
    if (yes != true) {
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _requesting = true;
      _source = confirmedSource;
    });
    String result;
    try {
      result = await runStarBridgeActivation(confirmedSource, owner.clear);
    } on Object {
      result = 'unknown';
    }
    if (!active()) return;
    setState(() {
      _busy = false;
      _requesting = false;
      _result = result;
      _completed++;
    });
    // Read actual state even on uncertainty; never fake an empty list or retry deletion.
    await runStarBridgeActivation(confirmedSource, refresh);
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.port, refresh = widget.refresh, epoch = _epoch;
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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StarBridgeActionButton(
                    controlKey: const Key('history-clear'),
                    kind: StarBridgeActionKind.quiet,
                    tone: ActionTone.danger,
                    semanticLabel: _text(context, 'clear'),
                    onActivate: _busy || !widget.enabled
                        ? null
                        : (source) => _clear(source, owner, refresh, epoch),
                    child: Text(_text(context, _busy ? 'working' : 'clear')),
                  ),
                  if (_requesting && data.suite != InteractionSuite.standard)
                    Semantics(
                      liveRegion: true,
                      child: InteractionScope(
                        data: effective,
                        child: SuiteBusyLabel(_text(context, 'working')),
                      ),
                    ),
                  if (_result != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _text(context, _result!),
                        key: const Key('history-clear-result'),
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
                        busy: _requesting,
                        doneToken: _completed,
                        doneOutcome: _result == 'cleared'
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

String _text(BuildContext context, String key) {
  final locale = Localizations.localeOf(context),
      copy = _copy[key] ?? _copy['unknown']!;
  return locale.languageCode == 'en'
      ? copy.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? copy.$2
      : copy.$1;
}

const _copy = <String, (String, String, String)>{
  'clear': ('清空全部记录', '清空全部記錄', 'Clear all records'),
  'confirm': ('清空全部本地事件记录？', '清空全部本機事件記錄？', 'Clear all local event records?'),
  'scope': (
    '记录及其备份将被清空，无法恢复。不会修改游戏的 Game.log。',
    '記錄及其備份將被清空，無法復原。不會修改遊戲的 Game.log。',
    'Records and their backup will be cleared permanently. The game’s Game.log will not change.',
  ),
  'cancel': ('取消', '取消', 'Cancel'),
  'working': ('正在处理…', '正在處理…', 'Working…'),
  'cleared': ('已清空本地事件记录', '已清空本機事件記錄', 'Local event records cleared'),
  'failed': (
    '未能完成清空，请重试。',
    '未能完成清空，請重試。',
    'Could not complete clearing. Try again.',
  ),
  'unavailable': (
    '日志暂不可用，请关闭其他客户端后重试。',
    '記錄暫不可用，請關閉其他用戶端後重試。',
    'History is unavailable. Close other clients and try again.',
  ),
  'busy': (
    '请等待当前操作完成。',
    '請等待目前操作完成。',
    'Wait for the current operation to finish.',
  ),
  'unknown': (
    '清空结果尚未确认，请查看刷新后的记录。',
    '清空結果尚未確認，請查看重新整理後的記錄。',
    'Clearing is unconfirmed. Check the refreshed records.',
  ),
};
