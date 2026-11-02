import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import 'overlay_settings_command_feedback.dart';

import '../../app/localization/app_strings.dart';
import '../../platform/window/menu_preview_window_port.dart';
import '../../platform/window/menu_window_preferences.dart';
import '../../platform/window/menu_shortcut_settings.dart';
import '../../platform/window/menu_browser_resume.dart';
import '../../platform/window/menu_screenshot_directory.dart';
import '../../platform/window/method_channel_menu_preview_window.dart';
import 'menu_settings_draft.dart';
import 'menu_additional_settings_draft.dart';
import 'menu_additional_settings_editors.dart';
import 'menu_settings_workspace.dart';
import 'menu_shortcut_settings_card.dart';
import 'menu_shortcut_summary_state.dart';
import 'overlay_shortcut_summary.dart';
import 'menu_browser_resume_card.dart';
import 'menu_screenshot_directory_card.dart';

class MenuOverlaySettings extends StatefulWidget {
  const MenuOverlaySettings({required this.preview, this.draft, super.key});
  final MenuPreviewWindowPort? preview;
  final MenuSettingsDraft? draft;
  @override
  State<MenuOverlaySettings> createState() => _MenuOverlaySettingsState();
}

class _MenuOverlaySettingsState extends State<MenuOverlaySettings> {
  bool _opening = false, _failed = false;
  int _openEpoch = 0;
  Object _openOwner = Object();
  MenuSettingsDraft? _owned;
  MenuShortcutSummaryState? _shortcuts;
  MenuSettingsDraft? get draft => widget.draft ?? _owned;
  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    if (widget.draft == null) {
      if (widget.preview case MenuWindowPreferencesProvider provider) {
        final port = provider.menuPreferences;
        if (port != null) _owned = MenuSettingsDraft(port);
      }
    }
    if (draft case final value?) {
      if (value.additional == null) {
        value.attachAdditional(
          MenuAdditionalSettingsDraft(
            shortcutPort: switch (widget.preview) {
              MenuShortcutSettingsProvider p => p.shortcutSettings,
              _ => null,
            },
            resumePort: switch (widget.preview) {
              MenuBrowserResumeProvider p => p.browserResume,
              _ => null,
            },
            directoryPort: switch (widget.preview) {
              MenuScreenshotDirectoryProvider p => p.screenshotDirectory,
              _ => null,
            },
          ),
        );
        value.additional!.reload();
      }
      return;
    }
    if (widget.preview case MenuShortcutSettingsProvider provider) {
      final port = provider.shortcutSettings;
      if (port != null) {
        _shortcuts = MenuShortcutSummaryState(port);
        _shortcuts!.readShortcut().then<void>((_) {}, onError: (Object _) {});
      }
    }
  }

  @override
  void didUpdateWidget(MenuOverlaySettings old) {
    super.didUpdateWidget(old);
    if (!identical(old.preview, widget.preview) ||
        !identical(old.draft, widget.draft)) {
      ++_openEpoch;
      _openOwner = Object();
      _opening = _failed = false;
      _owned?.dispose();
      _shortcuts?.dispose();
      _shortcuts = null;
      _owned = null;
      _bind();
    }
  }

  @override
  void dispose() {
    _owned?.dispose();
    _shortcuts?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final port = widget.preview;
    if (port is! MenuLiveWindowPort || !port.liveAvailable || _opening) return;
    final epoch = ++_openEpoch, owner = widget.draft;
    final strings = AppStrings.of(context);
    setState(() {
      _opening = true;
      _failed = false;
    });
    var shown = false;
    try {
      shown = await port.openLive(
        contextLabel: strings.text('overlay.sections.menu'),
        returnLabel: strings.text('overlay.menu.return'),
        settingsLabel: strings.text('overlay.sections.menu'),
      );
    } on Object {
      shown = false;
    }
    if (mounted &&
        epoch == _openEpoch &&
        identical(port, widget.preview) &&
        identical(owner, widget.draft)) {
      setState(() {
        _opening = false;
        _failed = !shown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context), port = widget.preview;
    final available = port is MenuLiveWindowPort && port.liveAvailable;
    final shortcuts = _shortcuts;
    final resume = switch (port) {
      MenuBrowserResumeProvider p => p.browserResume,
      _ => null,
    };
    final directory = switch (port) {
      MenuScreenshotDirectoryProvider p => p.screenshotDirectory,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                strings.text('overlay.sections.menu'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (shortcuts != null)
                    ListenableBuilder(
                      listenable: shortcuts,
                      builder: (context, _) => OverlayShortcutSummary(
                        key: const Key('menu-header-shortcut'),
                        binding: shortcuts.value?.binding,
                        enabled: shortcuts.value?.enabled ?? true,
                        state: shortcuts.value?.state ?? 'unavailable',
                      ),
                    ),
                  if (draft?.additional case final extra?)
                    ListenableBuilder(
                      listenable: extra,
                      builder: (context, _) => OverlayShortcutSummary(
                        key: const Key('menu-header-shortcut'),
                        binding: extra.savedShortcut?.binding,
                        enabled: extra.savedShortcut?.enabled ?? true,
                        state: extra.savedShortcut?.state ?? 'unavailable',
                      ),
                    ),
                  OverlaySettingsCommandFeedback(
                    owner: _openOwner,
                    builder: (context, run, source) => StarBridgeActionButton(
                      kind: StarBridgeActionKind.primary,
                      controlKey: const Key('menu-overlay-open-live'),
                      nativeStyle: _opening
                          ? const ButtonStyle(animationDuration: Duration.zero)
                          : null,
                      onActivate: available && !_opening
                          ? (origin) => run(origin, _open)
                          : null,
                      child: _opening
                          ? OverlaySettingsCommandWait(
                              label: strings.text('overlay.menu.opening'),
                              source: source(),
                            )
                          : Text(strings.text('menu.product.open')),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            strings.text('menu.product.closeHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_failed || !available)
            Text(
              strings.text(
                _failed ? 'overlay.menu.failed' : 'menu.product.unavailable',
              ),
              key: const Key('menu-overlay-open-failed'),
            ),
          const SizedBox(height: 12),
          if (draft case final value?)
            Expanded(
              child: MenuSettingsWorkspace(
                draft: value,
                shortcuts: value.additional?.shortcutPort == null
                    ? null
                    : MenuAdditionalShortcutEditor(draft: value.additional!),
                browserResume: value.additional?.resumePort == null
                    ? null
                    : MenuAdditionalResumeEditor(draft: value.additional!),
                screenshotDirectory: value.additional?.directoryPort == null
                    ? null
                    : MenuAdditionalDirectoryEditor(draft: value.additional!),
                execHangar: switch (widget.preview) {
                  MethodChannelMenuPreviewWindow window =>
                    window.execHangarProvider,
                  _ => null,
                },
              ),
            ),
          if (draft == null)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (shortcuts != null)
                      MenuShortcutSettingsCard(port: shortcuts),
                    if (resume != null) MenuBrowserResumeCard(port: resume),
                    if (directory != null)
                      MenuScreenshotDirectoryCard(port: directory),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
