import 'package:flutter/widgets.dart';

import '../../shared/guide/guide_empty_state.dart';
import '../../shared/guide/guide_scope.dart';

/// Never-saved hangar: the guided empty state. The first-read tour starts
/// when the reader actually opens (`hangar.readerOpened`), not on a click.
Widget hangarGuideEmpty(VoidCallback? onRead) => GuideEmptyState(
  'hangar',
  onPrimary: onRead,
  primaryAnchor: (button) => GuideAnchor(id: 'hangar.read', child: button),
);
