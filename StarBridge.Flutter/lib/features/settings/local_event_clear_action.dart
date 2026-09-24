import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
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
  @override
  void dispose() {
    _epoch++;
    widget.port.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(LocalEventClearAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port) {
      _epoch++;
      oldWidget.port.cancel();
      _busy = false;
      _result = null;
    }
  }

  Future<void> _clear() async {
    if (_busy || !widget.enabled) return;
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _result = null;
    });
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text(context, 'confirm')),
        content: Text(_text(context, 'scope')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_text(context, 'cancel')),
          ),
          TextButton(
            key: const Key('history-clear-confirm'),
            style: TextButton.styleFrom(
              foregroundColor: context.tokens.colors.danger,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_text(context, 'clear')),
          ),
        ],
      ),
    );
    if (!mounted || epoch != _epoch) return;
    if (yes != true) {
      setState(() => _busy = false);
      return;
    }
    String result;
    try {
      result = await widget.port.clear();
    } on Object {
      result = 'unknown';
    }
    if (!mounted || epoch != _epoch) return;
    setState(() {
      _busy = false;
      _result = result;
    });
    // Read actual state even on uncertainty; never fake an empty list or retry deletion.
    await widget.refresh();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton(
        key: const Key('history-clear'),
        style: TextButton.styleFrom(
          foregroundColor: context.tokens.colors.danger,
        ),
        onPressed: _busy || !widget.enabled ? null : _clear,
        child: Text(_text(context, _busy ? 'working' : 'clear')),
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
  );
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
