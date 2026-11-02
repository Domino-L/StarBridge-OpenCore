import '../../app/localization/app_strings.dart';
import 'overlay_workspace_models.dart';

/// The built-in first plan is stored as 默认预设 until the user renames it.
/// Until then it is shown in the reader's language, and saving the shown
/// name unchanged keeps the stored one so it keeps following the language.
extension OverlayPresetName on OverlayWorkspacePreset {
  static const builtInId = 'preset1', builtInName = '默认预设';

  bool get hasBuiltInName => id == builtInId && name == builtInName;

  String shownName(AppStrings strings) => hasBuiltInName
      ? strings.text('overlay.workspace.defaultPresetName')
      : name;

  String savedName(String text, AppStrings strings) =>
      hasBuiltInName && text == shownName(strings) ? name : text;
}
