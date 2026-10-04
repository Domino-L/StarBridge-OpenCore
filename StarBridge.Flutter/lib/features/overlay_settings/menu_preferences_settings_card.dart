import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../platform/window/menu_window_preferences.dart';

/// Shared explicit-save flow; editors own only a patch, not geometry or revision.
class MenuPreferencesSettingsCard<T extends Object> extends StatefulWidget {
  const MenuPreferencesSettingsCard({
    super.key,
    required this.port,
    required this.section,
    required this.read,
    required this.patch,
    required this.editor,
  });
  final MenuWindowPreferencesPort port;
  final String section;
  final T Function(Map<String, Object?>) read;
  final Map<String, Object?> Function(T) patch;
  final Widget Function(T, ValueChanged<T>) editor;
  @override
  State<MenuPreferencesSettingsCard<T>> createState() => _CardState<T>();
}

class _CardState<T extends Object>
    extends State<MenuPreferencesSettingsCard<T>> {
  MenuWindowPreferences? _saved;
  T? _draft;
  bool _busy = true, _dirty = false, _failed = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MenuPreferencesSettingsCard<T> old) {
    super.didUpdateWidget(old);
    if (old.port != widget.port) {
      _saved = null;
      _draft = null;
      _dirty = false;
      _load();
    }
  }

  Future<void> _load({bool save = false}) async {
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final next = save
          ? await widget.port.save(
              _saved!.withSettingsPatch(widget.patch(_draft!)),
            )
          : await widget.port.read();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _saved = next;
        if (save || !_dirty) {
          _draft = widget.read(next.settings);
          _dirty = false;
        }
      });
    } on Object {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String text(String key) =>
        AppStrings.of(context).text('menu.${widget.section}.$key');
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_draft case final draft?)
            ExcludeFocus(
              excluding: _busy,
              child: AbsorbPointer(
                absorbing: _busy,
                child: widget.editor(
                  draft,
                  (value) => setState(() {
                    _draft = value;
                    _dirty = true;
                    _failed = false;
                  }),
                ),
              ),
            ),
          if (_failed)
            Text(text('failed'), key: Key('menu-${widget.section}-error')),
          if (_saved != null) Text(text(_dirty ? 'dirty' : 'saved')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: Key('menu-${widget.section}-save'),
                onPressed: _busy || !_dirty || _saved == null
                    ? null
                    : () => _load(save: true),
                child: Text(text(_busy ? 'busy' : 'save')),
              ),
              TextButton(
                key: Key('menu-${widget.section}-reload'),
                onPressed: _busy ? null : _load,
                child: Text(text('reload')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
