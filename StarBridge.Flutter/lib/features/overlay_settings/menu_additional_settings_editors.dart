import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'menu_additional_settings_draft.dart';
import 'menu_settings_draft.dart';
import 'overlay_settings_help.dart';
import 'overlay_workspace_hotkey_card.dart';
import 'overlay_workspace_models.dart';

Future<bool> confirmMenuSettingsSave(
  BuildContext context,
  MenuSettingsDraft draft,
) async {
  if (!draft.clearsBrowserMemory) return draft.save();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_copy(context, 'clearTitle')),
      content: Text(_copy(context, 'clearBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(_copy(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(_copy(context, 'clearSave')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  return draft.save(clearBrowserMemoryConfirmed: true);
}

String _copy(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final language = locale.languageCode == 'zh'
      ? (locale.scriptCode == 'Hant' ||
                ['TW', 'HK', 'MO'].contains(locale.countryCode)
            ? 'tw'
            : 'cn')
      : 'en';
  return switch ((key, language)) {
    ('clearTitle', 'cn') => '关闭网页记忆并保存？',
    ('clearTitle', 'tw') => '關閉網頁記憶並儲存？',
    ('clearTitle', _) => 'Turn off page memory and save?',
    ('clearBody', 'cn') =>
      '将清除此账号在这台电脑上记住的网页地址，不会关闭已经打开的网页。确认后保存本页的所有调整；取消则不保存任何调整。',
    ('clearBody', 'tw') =>
      '將清除此帳號在這台電腦上記住的網頁網址，不會關閉已開啟的網頁。確認後儲存本頁的所有調整；取消則不儲存任何調整。',
    ('clearBody', _) => 'This clears the page URL remembered for this account on this computer. Open pages stay open. Confirm to save all changes on this page, or cancel to save none.',
    ('clearSave', 'cn') => '清除记忆并保存',
    ('clearSave', 'tw') => '清除記憶並儲存',
    ('clearSave', _) => 'Clear memory and save',
    ('cancel', 'cn') => '取消',
    ('cancel', 'tw') => '取消',
    ('cancel', _) => 'Cancel',
    ('resetPending', 'cn') => '默认目录（保存后恢复）',
    ('resetPending', 'tw') => '預設目錄（儲存後恢復）',
    ('resetPending', _) => 'Default folder (restored when saved)',
    ('readFailed', 'cn') => '暂时无法读取这项设置，请重新读取。',
    ('readFailed', 'tw') => '暫時無法讀取這項設定，請重新讀取。',
    ('readFailed', _) => 'Could not read this setting. Try reloading.',
    _ => key,
  };
}

/// Controlled editors: changes belong to the page draft and its single save bar.
class MenuAdditionalShortcutEditor extends StatelessWidget {
  const MenuAdditionalShortcutEditor({super.key, required this.draft});
  final MenuAdditionalSettingsDraft draft;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      String t(String key) => AppStrings.of(context).text('menu.shortcut.$key');
      final value = draft.shortcut;
      return Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OverlaySettingsHelp(t('hint')),
            const SizedBox(height: 12),
            if (value != null) ...[
              AbsorbPointer(
                absorbing: draft.busy,
                child: ExcludeFocus(
                  excluding: draft.busy,
                  child: OverlayWorkspaceHotkeyCard(
                    embedded: true,
                    hotkey: OverlayWorkspaceHotkey(
                      binding: value.binding,
                      enabled: value.enabled,
                      runtimeState: draft.shortcutDirty
                          ? 'pending'
                          : value.state,
                    ),
                    defaultBinding: 'Alt+M',
                    enabledLabel: t('enabled'),
                    onBindingChanged: (binding) =>
                        draft.changeShortcut(binding: binding),
                    onEnabledChanged: (enabled) =>
                        draft.changeShortcut(enabled: enabled),
                  ),
                ),
              ),
              SwitchListTile(
                key: const Key('menu-shortcut-close'),
                contentPadding: EdgeInsets.zero,
                title: Text(t('close')),
                value: value.closeWithHotkey,
                onChanged: draft.busy
                    ? null
                    : (close) => draft.changeShortcut(closeWithHotkey: close),
              ),
              if (draft.shortcutDirty) OverlaySettingsHelp(t('dirty')),
            ] else
              _AdditionalLoading(draft: draft),
          ],
        ),
      );
    },
  );
}

class MenuAdditionalResumeEditor extends StatelessWidget {
  const MenuAdditionalResumeEditor({super.key, required this.draft});
  final MenuAdditionalSettingsDraft draft;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      String t(String key) =>
          AppStrings.of(context).text('menu.browser.resume.$key');
      final value = draft.resume;
      return Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('title'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            OverlaySettingsHelp(t('privacy')),
            if (value != null) ...[
              SwitchListTile(
                key: const Key('menu-browser-resume-toggle'),
                contentPadding: EdgeInsets.zero,
                title: Text(t('enabled')),
                value: value.enabled,
                onChanged: draft.busy ? null : draft.changeResume,
              ),
              OverlaySettingsHelp(t('hint')),
              if (draft.resumeDirty) ...[
                const SizedBox(height: 8),
                OverlaySettingsHelp(
                  AppStrings.of(context).text('menu.shortcut.dirty'),
                ),
              ],
            ] else
              _AdditionalLoading(draft: draft),
          ],
        ),
      );
    },
  );
}

class MenuAdditionalDirectoryEditor extends StatelessWidget {
  const MenuAdditionalDirectoryEditor({super.key, required this.draft});
  final MenuAdditionalSettingsDraft draft;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      String t(String key) =>
          AppStrings.of(context).text('menu.screenshot.directory.$key');
      final value = draft.directory;
      return Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('title'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            OverlaySettingsHelp(t('hint')),
            const SizedBox(height: 12),
            if (value != null) ...[
              Text(
                draft.resetPending
                    ? _copy(context, 'resetPending')
                    : t(value.isDefault ? 'default' : 'custom'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              if (!draft.resetPending)
                SelectableText(
                  value.directory,
                  key: const Key('menu-screenshot-directory-path'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('menu-screenshot-directory-choose'),
                    onPressed: draft.busy || !draft.canChooseDirectory
                        ? null
                        : draft.chooseDirectory,
                    child: Text(t('choose')),
                  ),
                  TextButton(
                    key: const Key('menu-screenshot-directory-reset'),
                    onPressed:
                        draft.busy || value.isDefault || draft.resetPending
                        ? null
                        : draft.resetDirectory,
                    child: Text(t('reset')),
                  ),
                  OutlinedButton(
                    key: const Key('menu-screenshot-directory-open'),
                    onPressed: draft.busy || draft.directoryDirty
                        ? null
                        : draft.openDirectory,
                    child: Text(t('open')),
                  ),
                ],
              ),
              if (draft.directoryDirty) ...[
                const SizedBox(height: 8),
                OverlaySettingsHelp(
                  AppStrings.of(context).text('menu.shortcut.dirty'),
                ),
              ],
            ] else
              _AdditionalLoading(draft: draft),
            const SizedBox(height: 8),
            OverlaySettingsHelp(t('privacy')),
          ],
        ),
      );
    },
  );
}

class _AdditionalLoading extends StatelessWidget {
  const _AdditionalLoading({required this.draft});
  final MenuAdditionalSettingsDraft draft;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      OverlaySettingsHelp(
        draft.busy
            ? AppStrings.of(context).text('menu.shortcut.busy')
            : _copy(context, 'readFailed'),
      ),
      if (!draft.busy)
        TextButton(
          onPressed: draft.dirty ? null : draft.reload,
          child: Text(AppStrings.of(context).text('menu.shortcut.reload')),
        ),
    ],
  );
}
