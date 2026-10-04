import '../../localization/app_strings.dart';
import 'shell_chrome_projection.dart';

/// Both toolbar and shell render the same choice, actual result and lifetime.
String overlaySourceLabel(OverlaySceneProjection view, AppStrings strings) {
  String label(String? id) {
    final option = view.optionById(id);
    return option?.label ??
        strings.text(option?.labelKey ?? 'overlay.source.title');
  }

  final selected = label(view.preferredSceneId);
  final resolved = view.preferredSceneId == 'auto' && view.actualSceneId != null
      ? '$selected · ${label(view.actualSceneId)}'
      : selected;
  return switch (view.selectionOrigin) {
    'preset' =>
      strings
          .text('overlay.source.boundLabel')
          .replaceAll('{source}', resolved),
    'temporary' =>
      strings
          .text('overlay.source.temporaryLabel')
          .replaceAll('{source}', resolved),
    _ => resolved,
  };
}

String overlaySourceHint(OverlaySceneProjection view) =>
    view.selectionOrigin == 'account'
    ? 'overlay.source.hint'
    : 'overlay.source.temporaryHint';

String overlaySourceOptionLabel(
  OverlaySceneProjection view,
  OverlaySceneOption option,
  AppStrings strings,
) {
  final label = option.label ?? strings.text(option.labelKey);
  return view.selectionOrigin != 'account' &&
          option.enabled &&
          option.id != 'resumeBinding'
      ? strings
            .text('overlay.source.switchTemporarily')
            .replaceAll('{source}', label)
      : label;
}
