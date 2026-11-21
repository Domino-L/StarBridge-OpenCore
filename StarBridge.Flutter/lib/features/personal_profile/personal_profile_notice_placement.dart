import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Room the floating Fan Kit notice needs beside the page column (button and
/// gap at normal text size).
const double _floatingNoticeMargin = 220;

/// Decides where the Fan Kit notice goes. It floats in the wallpaper margin
/// only when there is one; otherwise it would cover the page (build 65,
/// a half-width window) and goes under the page instead. Measuring here, in
/// an empty box over the page, keeps the page itself out of the decision so
/// a page transition repaints nothing more than before.
class ProfileNoticeRoom extends StatefulWidget {
  const ProfileNoticeRoom({
    required this.floats,
    required this.columnMaxWidth,
    required this.sidePadding,
    super.key,
  });

  /// Null until measured; true floats, false follows the page.
  final ValueNotifier<bool?> floats;
  final double columnMaxWidth;
  final double sidePadding;

  @override
  State<ProfileNoticeRoom> createState() => _ProfileNoticeRoomState();
}

class _ProfileNoticeRoomState extends State<ProfileNoticeRoom> {
  // The same measuring widget across page rebuilds (the page rebuilds every
  // frame of its entry animation): it measures again only when the width
  // or text size changes, and a relayout would repaint the page each frame.
  Widget? _measure;

  @override
  void didUpdateWidget(ProfileNoticeRoom old) {
    super.didUpdateWidget(old);
    if (old.floats != widget.floats ||
        old.columnMaxWidth != widget.columnMaxWidth ||
        old.sidePadding != widget.sidePadding) {
      _measure = null;
    }
  }

  @override
  Widget build(BuildContext context) => _measure ??= LayoutBuilder(
    builder: (context, box) {
      final column = math.min(
        box.maxWidth - 2 * widget.sidePadding,
        widget.columnMaxWidth,
      );
      final needed =
          _floatingNoticeMargin * MediaQuery.textScalerOf(context).scale(1);
      final next = (box.maxWidth - column) / 2 >= needed;
      final floats = widget.floats;
      if (floats.value != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) floats.value = next;
        });
      }
      return const SizedBox.shrink();
    },
  );
}

/// One of the notice's two places; shows [child] only when it is the
/// measured one.
class ProfileNoticeSlot extends StatelessWidget {
  const ProfileNoticeSlot({
    required this.floats,
    required this.floating,
    required this.child,
    super.key,
  });

  final ValueListenable<bool?> floats;
  final bool floating;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool?>(
    valueListenable: floats,
    builder: (context, value, _) =>
        value == floating ? child : const SizedBox.shrink(),
  );
}
