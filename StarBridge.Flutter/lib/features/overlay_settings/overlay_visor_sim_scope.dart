import 'package:flutter/widgets.dart';

import 'overlay_visor_editor_content.dart';

/// What the layout editor's simplified visor panels show (11-12): the Host's
/// content, or samples until it answers. The canvas modules and the events
/// block read it; [simulate] off (the editor's "sample information" off) shows
/// the blocks' names instead.
class OverlayVisorSimScope extends InheritedWidget {
  const OverlayVisorSimScope({
    required this.content,
    required this.sampleLabel,
    required this.simulate,
    required super.child,
    super.key,
  });

  final OverlayVisorEditorContent content;

  /// "示例数据", shown beside a block's title when it shows samples.
  final String sampleLabel;
  final bool simulate;

  static OverlayVisorSimScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OverlayVisorSimScope>();

  @override
  bool updateShouldNotify(OverlayVisorSimScope oldWidget) =>
      content != oldWidget.content ||
      sampleLabel != oldWidget.sampleLabel ||
      simulate != oldWidget.simulate;
}
