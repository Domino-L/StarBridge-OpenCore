import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'community_chat_port.dart';

/// The same real >=16px intersection as visible read receipts.
/// Cache extent mounting is not evidence of visible residency.
List<CommunityChatMessage> visibleCommunityChatMessages(
  List<CommunityChatMessage> messages,
  Map<String, GlobalKey> keys,
) {
  final result = <CommunityChatMessage>[];
  for (final message in messages) {
    final element = keys[message.messageRef]?.currentContext;
    final box = element?.findRenderObject();
    final viewport = element?.findAncestorRenderObjectOfType<RenderViewport>();
    if (box is! RenderBox ||
        viewport == null ||
        !box.attached ||
        !box.hasSize) {
      continue;
    }
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
    if (bounds.overlaps(visible) && bounds.intersect(visible).height >= 16) {
      result.add(message);
    }
  }
  return result;
}
