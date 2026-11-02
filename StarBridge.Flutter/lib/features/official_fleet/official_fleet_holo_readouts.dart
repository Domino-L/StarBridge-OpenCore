import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/organization_holo_deck.dart';
import '../communities/community_activity_time.dart';

/// One fact in the counters' language: a small label over a short value,
/// with a copy action for contacts. A value stays on one line while the
/// deck has the room and wraps between its phrases otherwise (user
/// 2026-10-29); the tooltip keeps the whole text reachable.
class OfficialFleetHoloReadout extends StatelessWidget {
  const OfficialFleetHoloReadout(this.item, {super.key, required this.label});

  final OrganizationHoloReadout item;
  final TextStyle? label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final copy = item.onCopy;
    final fact = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.label, style: label),
        const SizedBox(height: 5),
        Tooltip(
          message: item.value,
          child: Text(
            communityReadoutPhrases(item.value),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.3,
              color: item.muted
                  ? tokens.colors.textDisabled
                  : tokens.colors.textPrimary,
            ),
          ),
        ),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      // The copy action sits beside the fact, so a contact is no taller
      // than the other readouts.
      child: copy == null
          ? fact
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: fact),
                const SizedBox(width: 2),
                // Quiet beside the value (user 2026-10-29: the framed
                // square drew the eye); hover and focus bring it up.
                StarBridgeIconAction(
                  controlKey: item.copyKey,
                  label: item.copyLabel,
                  quiet: true,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: const EdgeInsets.all(6),
                  onActivate: (_) => copy(),
                  icon: const StandardIcon(StandardIconSemantic.copy, size: 16),
                ),
              ],
            ),
    );
  }
}

/// Paints [child] [lift] px higher and reports that much less height, so a
/// group can rise into the banner without leaving an empty band below it.
class OfficialFleetHoloLift extends SingleChildRenderObjectWidget {
  const OfficialFleetHoloLift({
    super.key,
    required this.lift,
    required super.child,
  });

  final double lift;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderOfficialFleetHoloLift(lift);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderOfficialFleetHoloLift renderObject,
  ) => renderObject.lift = lift;
}

class RenderOfficialFleetHoloLift extends RenderShiftedBox {
  RenderOfficialFleetHoloLift(this._lift) : super(null);

  double _lift;
  set lift(double value) {
    if (value == _lift) return;
    _lift = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.copyWith(minHeight: 0), parentUsesSize: true);
    (child.parentData! as BoxParentData).offset = Offset(0, -_lift);
    size = constraints.constrain(
      Size(child.size.width, math.max(0, child.size.height - _lift)),
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // The lifted top stays reachable: test the child, not only this box.
    final child = this.child;
    if (child == null) return false;
    final offset = (child.parentData! as BoxParentData).offset;
    final hit = result.addWithPaintOffset(
      offset: offset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
    if (hit) result.add(BoxHitTestEntry(this, position));
    return hit;
  }
}
