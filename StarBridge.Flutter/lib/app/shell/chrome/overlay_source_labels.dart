import '../../localization/app_strings.dart';
import 'shell_chrome_projection.dart';

/// Both toolbar and shell render the same choice, actual result and lifetime.
String overlaySourceLabel(OverlaySceneProjection view, AppStrings strings) {
  String label(String? id) {
    final option = view.optionById(id);
    return option == null
        ? strings.text('overlay.source.title')
        : overlaySourceOptionLabel(view, option, strings);
  }

  final selected = label(view.preferredSceneId);
  final resolved = view.preferredSceneId == 'auto' && view.actualSceneId != null
      ? '$selected · ${label(view.actualSceneId)}'
      : selected;
  // A session-only source can only be left over from an older build and is
  // cleared by the next selection, so it shows as a plain result.
  return view.selectionOrigin == 'preset'
      ? strings
            .text('overlay.source.planFixedLabel')
            .replaceAll('{source}', resolved)
      : resolved;
}

String overlaySourceHint(OverlaySceneProjection view) =>
    view.selectionOrigin == 'preset'
    ? 'overlay.source.planFixedHint'
    : 'overlay.source.hint';

String overlaySourceOptionLabel(
  OverlaySceneProjection view,
  OverlaySceneOption option,
  AppStrings strings,
) => option.id == 'fleet' && option.label != null
    // The main fleet is listed like an organization, marked by a short tag.
    ? '${option.label} · ${strings.text(option.labelKey)}'
    : option.label ?? strings.text(option.labelKey);
