import 'exec_hangar_motion_controls.dart';
import 'exec_hangar_waiting.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';

import '../../app/localization/app_strings.dart';
import '../../platform/window/menu_desktop_widgets.dart';
import '../../platform/window/menu_window_preferences.dart';

/// The pin is menu presentation only. Read before each CAS save to preserve
/// geometry and every other preference changed by the menu owner.
final class ExecHangarMenuWidgetButton extends StatefulWidget {
  const ExecHangarMenuWidgetButton({super.key, required this.port});
  final MenuWindowPreferencesPort port;
  @override
  State<ExecHangarMenuWidgetButton> createState() => _PinState();
}

class _PinState extends State<ExecHangarMenuWidgetButton> {
  bool? _pinned;
  bool _busy = true, _failed = false;
  InteractionSource _source = InteractionSource.programmatic;
  int _phase = 0;
  bool _opening = true, _saving = false;
  String t(String key) => AppStrings.of(context).text('execHangar.$key');
  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final saved = await widget.port.read();
      if (mounted) {
        setState(() {
          _pinned = MenuDesktopWidgets.parse(saved.settings['widgets'])!.hangar;
          _failed = false;
        });
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    _source = captureStarBridgeActivationSource()();
    _phase++;
    _opening = false;
    _saving = _pinned != null;
    if (_pinned == null) {
      setState(() => _busy = true);
      return _read();
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final saved = await widget.port.read();
      final widgets = MenuDesktopWidgets.parse(saved.settings['widgets'])!;
      final next = await widget.port.save(
        saved.withSettingsPatch({
          'widgets': widgets.copyWith(hangar: !_pinned!).toMap(),
        }),
      );
      if (mounted) {
        setState(
          () =>
              _pinned = MenuDesktopWidgets.parse(next.settings['widgets'])!
                  .hangar,
        );
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExecHangarMotionButton(
        OutlinedButton.icon(
          key: const Key('exec-pin-menu'),
          onPressed: _busy ? null : _toggle,
          icon: const StandardIcon(StandardIconSemantic.dashboard, size: 18),
          label: Text(
            t(
              _busy
                  ? _saving
                        ? 'widgetSaving'
                        : 'widgetLoading'
                  : _pinned == true
                  ? 'widgetRemove'
                  : 'widgetAdd',
            ),
          ),
        ),
      ),
      if (_busy)
        SizedBox(
          width: 260,
          child: ExecHangarWaiting(
            key: ValueKey(('pin', _phase)),
            source: _source,
            opening: _opening,
            label: t(_saving ? 'widgetSaving' : 'widgetLoading'),
          ),
        ),
      if (_failed)
        Text(
          t('widgetFailed'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
