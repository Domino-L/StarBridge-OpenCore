import '../../app/localization/app_strings.dart';
import 'overlay_workspace_schema.dart';

String overlayWorkspaceFormatValue(
  OverlayWorkspaceFieldSpec spec,
  num value,
  AppStrings strings,
) {
  final number = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return switch (spec.unit) {
    OverlayWorkspaceUnit.seconds =>
      '$number ${strings.text('overlay.workspace.unit.seconds')}',
    OverlayWorkspaceUnit.percent => '${(value * 100).round()}%',
    OverlayWorkspaceUnit.pixels => '$number px',
    OverlayWorkspaceUnit.count =>
      '$number ${strings.text('overlay.workspace.unit.count')}',
    OverlayWorkspaceUnit.none => number,
  };
}
