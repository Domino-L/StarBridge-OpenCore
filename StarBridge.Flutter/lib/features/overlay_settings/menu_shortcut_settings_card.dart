import 'package:flutter/material.dart';

import 'overlay_settings_help.dart';

import '../../app/localization/app_strings.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/window/menu_shortcut_settings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_hotkey_card.dart';
import 'overlay_workspace_models.dart';

class MenuShortcutSettingsCard extends StatefulWidget {
  const MenuShortcutSettingsCard({
    required this.port,
    this.embedded = false,
    super.key,
  });
  final MenuShortcutSettingsPort port;
  final bool embedded;
  @override
  State<MenuShortcutSettingsCard> createState() =>
      _MenuShortcutSettingsCardState();
}

class _MenuShortcutSettingsCardState extends State<MenuShortcutSettingsCard> {
  MenuShortcutSettings? _saved;
  String _binding = 'Alt+M', _error = '';
  bool _enabled = true, _close = true, _busy = true, _dirty = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MenuShortcutSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.port != widget.port) {
      _saved = null;
      _dirty = false;
      _load();
    }
  }

  Future<void> _load({bool save = false}) async {
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final value = save
          ? await widget.port.saveShortcut(
              MenuShortcutSettings(
                _saved!.revision,
                _binding,
                _enabled,
                _close,
                _saved!.state,
              ),
            )
          : await widget.port.readShortcut();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _saved = value;
        if (!_dirty || save) {
          _binding = value.binding;
          _enabled = value.enabled;
          _close = value.closeWithHotkey;
          _dirty = false;
        }
      });
    } on Object catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _error = error is BridgeClientException
              ? error.code
              : 'menuHotkey.unavailable';
        });
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  void _change(VoidCallback change) => setState(() {
    change();
    _dirty = true;
    _error = '';
  });
  String _stateKey(String state) => switch (state) {
    'registered' => 'ready',
    'disabled' => 'disabled',
    'conflictWithInformation' => 'conflict',
    'modifierRequired' || 'reserved' || 'invalid' => 'invalid',
    _ => 'unavailable',
  };
  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.of(context).text('menu.shortcut.$key');
    final error = _error == 'menuPreferences.revision_conflict'
        ? 'changed'
        : _stateKey(_error.replaceFirst('menuHotkey.', ''));
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          Text(t('title'), style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: context.tokens.space.sm),
        OverlaySettingsHelp(t('hint')),
        if (_saved != null) ...[
          SizedBox(height: context.tokens.space.md),
          AbsorbPointer(
            absorbing: _busy,
            child: ExcludeFocus(
              excluding: _busy,
              child: OverlayWorkspaceHotkeyCard(
                embedded: widget.embedded,
                hotkey: OverlayWorkspaceHotkey(
                  binding: _binding,
                  enabled: _enabled,
                  runtimeState: _dirty ? 'pending' : _saved!.state,
                ),
                defaultBinding: 'Alt+M',
                enabledLabel: t('enabled'),
                onBindingChanged: (v) => _change(() => _binding = v),
                onEnabledChanged: (v) => _change(() => _enabled = v),
              ),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('close')),
              value: _close,
              onChanged: _busy ? null : (v) => _change(() => _close = v),
            ),
          ),
          Text(
            t(_dirty ? 'dirty' : _stateKey(_saved!.state)),
            key: const Key('menu-shortcut-state'),
          ),
        ],
        if (_error.isNotEmpty)
          Text(t(error), key: const Key('menu-shortcut-error')),
        SizedBox(height: context.tokens.space.sm),
        Wrap(
          spacing: context.tokens.space.sm,
          children: [
            FilledButton(
              key: const Key('menu-shortcut-save'),
              onPressed: _saved == null || _busy || !_dirty
                  ? null
                  : () => _load(save: true),
              child: Text(t(_busy ? 'busy' : 'save')),
            ),
            TextButton(
              key: const Key('menu-shortcut-reload'),
              onPressed: _busy ? null : _load,
              child: Text(t('reload')),
            ),
          ],
        ),
      ],
    );
    return widget.embedded
        ? content
        : StarBridgeSurface(role: SurfaceRole.panel, child: content);
  }
}
