import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/diagnostics/frame_pace_recorder.dart';
import '../../design_system/interaction/starbridge_switch.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'maintenance_action.dart';

/// The opt-in switch for "记录界面流畅度（排查卡顿用）".
class FramePacePanel extends StatefulWidget {
  const FramePacePanel({
    required this.recorder,
    this.openFolder = _openFolder,
    super.key,
  });

  final FramePaceRecorder recorder;
  final Future<void> Function(String path) openFolder;

  static Future<void> _openFolder(String path) async {
    await Process.start('explorer.exe', [path]);
  }

  @override
  State<FramePacePanel> createState() => _FramePacePanelState();
}

class _FramePacePanelState extends State<FramePacePanel> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _set(bool value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    final saved = await widget.recorder.setEnabled(value);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _failed = !saved;
    });
  }

  Future<void> _open() async {
    try {
      await widget.openFolder(widget.recorder.directory.path);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.recorder.enabled,
        builder: (context, enabled, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StarBridgeSwitch.tile(
              controlKey: const Key('frame-pace-switch'),
              label: framePaceText(context, 'switch'),
              subtitle: framePaceText(context, 'what'),
              value: enabled,
              onChanged: _saving ? null : _set,
            ),
            SizedBox(height: tokens.space.sm),
            Text(framePaceText(context, 'where')),
            if (_failed)
              Padding(
                padding: EdgeInsets.only(top: tokens.space.sm),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    framePaceText(context, 'failed'),
                    style: TextStyle(color: tokens.colors.warning),
                  ),
                ),
              ),
            if (enabled) ...[
              SizedBox(height: tokens.space.md),
              Align(
                alignment: Alignment.centerLeft,
                child: MaintenanceAction(
                  OutlinedButton(
                    key: const Key('frame-pace-open-folder'),
                    onPressed: _open,
                    child: Text(framePaceText(context, 'folder')),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String framePaceText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final entry = _copy[key]!;
  return locale.languageCode == 'en'
      ? entry.$3
      : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
      ? entry.$2
      : entry.$1;
}

const _copy = <String, (String, String, String)>{
  'switch': (
    '记录界面流畅度（排查卡顿用）',
    '記錄介面流暢度（排查卡頓用）',
    'Record interface smoothness (for finding stutter)',
  ),
  'what': (
    '打开后每分钟记一条：当前页面、窗口大小、是否最大化、卡顿的画面有几帧，以及当时有没有在运行星际公民或其他全屏程序。不记账号，也不记页面内容。',
    '開啟後每分鐘記一筆：目前頁面、視窗大小、是否最大化、卡頓的畫面有幾格，以及當時有沒有在執行星際公民或其他全螢幕程式。不記帳號，也不記頁面內容。',
    'Once a minute while on: the current page, window size, whether it is maximized, how many frames stuttered, and whether Star Citizen or another full-screen program was running. No account or page content is recorded.',
  ),
  'where': (
    '记录只存在这台电脑上，最多占 2 MB，写满后自动删掉最早的部分。关掉后不再记录。',
    '記錄只存在這台電腦上，最多佔 2 MB，寫滿後自動刪掉最早的部分。關掉後不再記錄。',
    'Kept on this computer only, at most 2 MB; the oldest part is removed when full. Nothing is recorded while off.',
  ),
  'folder': ('打开记录所在文件夹', '開啟記錄所在資料夾', 'Open the record folder'),
  'failed': (
    '没能保存这个设置，请重试。',
    '沒能儲存這個設定，請重試。',
    'The setting could not be saved. Please try again.',
  ),
};
