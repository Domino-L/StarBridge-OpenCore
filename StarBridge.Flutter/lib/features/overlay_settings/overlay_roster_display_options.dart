import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';

/// Optional capability of a roster port: the member module's overflow display.
/// Ports without it keep the pin/exclude editor only.
abstract interface class OverlayRosterDisplayPort {
  Future<Map<String, Object?>> updateDisplay(
    int revision,
    OverlayRosterDisplay display,
  );
}

/// How the member module shows members that do not fit.
@immutable
final class OverlayRosterDisplay {
  const OverlayRosterDisplay({
    this.overflow = 'summary',
    this.rowLimit = 0,
    this.rotationIntervalSeconds = 10,
  });

  static const overflowModes = ['summary', 'rotate', 'truncate'];
  static const rowLimits = [0, 3, 4, 5, 6, 8, 10, 12];
  static const intervals = [5, 10, 15, 20, 30, 60];

  /// 'summary' shows "N more", 'rotate' pages through, 'truncate' shows the first rows.
  final String overflow;

  /// 0 fits as many rows as the module height allows.
  final int rowLimit;
  final int rotationIntervalSeconds;

  /// Null when the Host did not send display options or sent values it should not.
  static OverlayRosterDisplay? tryParse(Object? value) {
    if (value is! Map ||
        value.length != 3 ||
        !overflowModes.contains(value['overflow']) ||
        value['rowLimit'] is! int ||
        value['rotationIntervalSeconds'] is! int) {
      return null;
    }
    final rowLimit = value['rowLimit'] as int;
    final interval = value['rotationIntervalSeconds'] as int;
    if (rowLimit < 0 || rowLimit > 12 || interval < 5 || interval > 60) {
      return null;
    }
    return OverlayRosterDisplay(
      overflow: value['overflow'] as String,
      rowLimit: rowLimit,
      rotationIntervalSeconds: interval,
    );
  }

  Map<String, Object> toWire() => {
    'overflow': overflow,
    'rowLimit': rowLimit,
    'rotationIntervalSeconds': rotationIntervalSeconds,
  };

  OverlayRosterDisplay copyWith({
    String? overflow,
    int? rowLimit,
    int? rotationIntervalSeconds,
  }) => OverlayRosterDisplay(
    overflow: overflow ?? this.overflow,
    rowLimit: rowLimit ?? this.rowLimit,
    rotationIntervalSeconds:
        rotationIntervalSeconds ?? this.rotationIntervalSeconds,
  );
}

/// The three member-module display choices shown above the member list.
class OverlayRosterDisplayOptions extends StatelessWidget {
  const OverlayRosterDisplayOptions({
    required this.display,
    required this.copy,
    this.onChanged,
    super.key,
  });

  final OverlayRosterDisplay display;
  final String Function(String zh, String hant, String en) copy;

  /// Null while a request is in flight.
  final void Function(OverlayRosterDisplay next, InteractionSource source)?
  onChanged;

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    String seconds(int value) => copy('$value 秒', '$value 秒', '$value s');
    return Column(
      key: const Key('overlay-roster-display'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          context,
          copy('人数超出时', '人數超出時', 'When members overflow'),
          StarBridgeCompactSelect<String>(
            identity: 'overlay-roster-overflow',
            controlKey: const Key('overlay-roster-overflow'),
            semanticLabel: copy('人数超出时', '人數超出時', 'When members overflow'),
            value: display.overflow,
            options: [
              StarBridgeSelectOption(
                value: 'summary',
                label: copy('显示“另有 N 人”', '顯示「另有 N 人」', 'Show "N more"'),
              ),
              StarBridgeSelectOption(
                value: 'rotate',
                label: copy('轮换翻页', '輪換翻頁', 'Rotate pages'),
              ),
              StarBridgeSelectOption(
                value: 'truncate',
                label: copy('只显示前几位', '只顯示前幾位', 'Show the first rows'),
              ),
            ],
            onSelected: changed == null
                ? null
                : (value, source) =>
                      changed(display.copyWith(overflow: value), source),
          ),
        ),
        _row(
          context,
          copy('最多显示行数', '最多顯示行數', 'Rows at most'),
          StarBridgeCompactSelect<int>(
            identity: 'overlay-roster-rows',
            controlKey: const Key('overlay-roster-rows'),
            semanticLabel: copy('最多显示行数', '最多顯示行數', 'Rows at most'),
            value: display.rowLimit,
            options: [
              for (final rows in OverlayRosterDisplay.rowLimits)
                StarBridgeSelectOption(
                  value: rows,
                  label: rows == 0
                      ? copy('按模块高度', '依模組高度', 'Fit module height')
                      : copy('$rows 行', '$rows 行', '$rows rows'),
                ),
            ],
            onSelected: changed == null
                ? null
                : (value, source) =>
                      changed(display.copyWith(rowLimit: value), source),
          ),
        ),
        _row(
          context,
          copy('翻页间隔', '翻頁間隔', 'Page interval'),
          StarBridgeCompactSelect<int>(
            identity: 'overlay-roster-interval',
            controlKey: const Key('overlay-roster-interval'),
            semanticLabel: copy('翻页间隔', '翻頁間隔', 'Page interval'),
            value: display.rotationIntervalSeconds,
            options: [
              for (final value in OverlayRosterDisplay.intervals)
                StarBridgeSelectOption(value: value, label: seconds(value)),
            ],
            // Only meaningful while pages rotate.
            onSelected: changed == null || display.overflow != 'rotate'
                ? null
                : (value, source) => changed(
                    display.copyWith(rotationIntervalSeconds: value),
                    source,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String label, Widget control) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        control,
      ],
    ),
  );
}
