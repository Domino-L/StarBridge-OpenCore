import 'package:flutter/material.dart';

import 'menu_bridge_style.dart';

/// Interruption confirmation, not an account/content recovery mechanism.
class MenuRecoveryPrompt extends StatelessWidget {
  const MenuRecoveryPrompt({
    super.key,
    required this.onChoose,
    this.busy = false,
    this.failed = false,
  });
  final ValueChanged<String> onChoose;
  final bool busy, failed;
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final english = locale.languageCode == 'en';
    final traditional = locale.countryCode == 'TW';
    String text(String simplified, String tw, String en) => english
        ? en
        : traditional
        ? tw
        : simplified;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ModalBarrier(dismissible: false, color: BridgeInk.scrim),
        FocusScope(
          autofocus: true,
          child: AlertDialog(
            constraints: const BoxConstraints(maxWidth: 640),
            scrollable: true,
            title: Text(
              text('恢复上次菜单窗口', '恢復上次選單視窗', 'Restore previous menu windows'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text(
                    '是否恢复上次打开的窗口？只恢复布局，不恢复聊天草稿、截图或参考图。',
                    '是否恢復上次開啟的視窗？只恢復版面配置，不恢復聊天草稿、截圖或參考圖。',
                    'Restore the windows that were open? This restores layout only, not chat drafts, screenshots or reference images.',
                  ),
                ),
                if (failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      text(
                        '未能确认恢复选择，请重试。原有布局仍保留。',
                        '無法確認恢復選擇，請重試。原有版面配置仍保留。',
                        'Could not confirm your choice. Try again; your saved layout is retained.',
                      ),
                    ),
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => onChoose('restore'),
                child: Text(text('恢复窗口', '恢復視窗', 'Restore windows')),
              ),
              FilledButton(
                autofocus: true,
                onPressed: busy ? null : () => onChoose('startClean'),
                child: Text(text('仅打开菜单', '僅開啟選單', 'Open menu only')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
