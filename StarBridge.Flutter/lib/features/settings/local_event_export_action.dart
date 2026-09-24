import 'package:flutter/material.dart';

import 'local_event_export.dart';

/// Embedded in the existing history dialog. Closing it cancels its save picker.
class LocalEventExportAction extends StatefulWidget {
  const LocalEventExportAction({
    required this.port,
    required this.enabled,
    super.key,
  });
  final LocalEventExportPort port;
  final bool enabled;
  @override
  State<LocalEventExportAction> createState() => _LocalEventExportActionState();
}

class _LocalEventExportActionState extends State<LocalEventExportAction> {
  bool _busy = false;
  int _epoch = 0;
  LocalEventExportResult? _result;
  @override
  void didUpdateWidget(LocalEventExportAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port) {
      oldWidget.port.cancel();
      _epoch++;
      _busy = false;
      _result = null;
    }
  }

  @override
  void dispose() {
    _epoch++;
    widget.port.cancel();
    super.dispose();
  }

  Future<void> _export() async {
    if (_busy || !widget.enabled) return;
    final epoch = _epoch;
    final locale = Localizations.localeOf(context);
    final language = locale.languageCode == 'en'
        ? 'en'
        : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
        ? 'zh-TW'
        : 'zh-CN';
    setState(() {
      _busy = true;
      _result = null;
    });
    LocalEventExportResult result;
    try {
      result = await widget.port.export(language);
    } on Object {
      result = const LocalEventExportResult('unknown');
    }
    if (!mounted || epoch != _epoch) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      OutlinedButton(
        key: const Key('history-export'),
        onPressed: _busy || !widget.enabled ? null : _export,
        child: Text(_text(context, _busy ? 'working' : 'export')),
      ),
      if (_result case final result?)
        Semantics(
          liveRegion: true,
          child: Text(
            _text(
              context,
              result.code == 'saved' && result.recovered
                  ? 'savedBackup'
                  : result.code,
            ).replaceAll('{count}', '${result.count}'),
            key: const Key('history-export-result'),
          ),
        ),
    ],
  );
}

String _text(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final value = _copy[key] ?? _copy['unknown']!;
  if (locale.languageCode == 'en') return value.$3;
  return locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? value.$2
      : value.$1;
}

const _copy = <String, (String, String, String)>{
  'export': ('导出全部记录', '匯出全部記錄', 'Export all records'),
  'working': ('正在导出…', '正在匯出…', 'Exporting…'),
  'saved': ('已导出 {count} 条记录', '已匯出 {count} 筆記錄', 'Exported {count} records'),
  'savedBackup': (
    '已从备份导出 {count} 条记录',
    '已從備份匯出 {count} 筆記錄',
    'Exported {count} records from backup',
  ),
  'cancelled': ('已取消导出', '已取消匯出', 'Export cancelled'),
  'fileExists': (
    '文件已存在，请换一个文件名。',
    '檔案已存在，請換一個檔名。',
    'File already exists. Choose a different name.',
  ),
  'invalidDestination': (
    '请选择其他本机文件夹，保存为 TXT。',
    '請選擇其他本機資料夾，儲存為 TXT。',
    'Choose another local folder and save as TXT.',
  ),
  'dataUnavailable': (
    '无法读取记录，请刷新后重试。',
    '無法讀取記錄，請重新整理後重試。',
    'Cannot read records. Refresh and try again.',
  ),
  'empty': ('没有可导出的记录。', '沒有可匯出的記錄。', 'No records to export.'),
  'busy': (
    '请先完成已打开的保存窗口。',
    '請先完成已開啟的儲存視窗。',
    'Finish the open save dialog first.',
  ),
  'unavailable': (
    '暂时无法导出，请重新打开此页。',
    '暫時無法匯出，請重新開啟此頁。',
    'Export unavailable. Reopen this page.',
  ),
  'failed': (
    '未能保存，请检查文件夹权限或剩余空间。',
    '未能儲存，請檢查資料夾權限或剩餘空間。',
    'Could not save. Check folder permissions and free space.',
  ),
  'unknown': (
    '尚未确认导出结果，请先检查目标文件夹。',
    '尚未確認匯出結果，請先檢查目標資料夾。',
    'Export result is unconfirmed. Check the destination folder first.',
  ),
};
