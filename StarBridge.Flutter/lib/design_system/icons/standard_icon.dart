import 'package:flutter/material.dart';

import 'avionics_icon.dart';

/// Auxiliary semantics rendered by the approved StarBridge V2 catalog.
enum StandardIconSemantic {
  accountCircle,
  add,
  adminPanelSettings,
  alternateEmail,
  arrowBack,
  arrowDownward,
  arrowForward,
  attachFile,
  badge,
  brokenImage,
  campaign,
  chatBubble,
  checkCircle,
  chevronLeft,
  chevronRight,
  circle,
  circleOutline,
  close,
  copyAll,
  copy,
  dashboard,
  deleteForever,
  delete,
  edit,
  event,
  expandLess,
  expandMore,
  groupAdd,
  groups,
  history,
  hourglassTop,
  image,
  info,
  language,
  layers,
  logout,
  meetingRoom,
  moreHoriz,
  north,
  outbox,
  people,
  personAddAlt,
  person,
  personRemove,
  public,
  radioButtonChecked,
  radioButtonOff,
  radioButtonUnchecked,
  refresh,
  rocketLaunch,
  schedule,
  search,
  send,
  share,
  south,
  sportsEsports,
  swapHoriz,
  unfoldLess,
  unfoldMore,
  verifiedUser,
  visibility,
  warningAmber,
}

/// Owns glyph selection without leaking font/code-point details into features.
class StandardIcon extends StatelessWidget {
  const StandardIcon(
    this.semantic, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
  });
  final StandardIconSemantic semantic;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) => AvionicsIcon(
    'Std.${semantic.name}',
    size: size,
    color: color,
    semanticLabel: semanticLabel,
    textDirection: textDirection,
  );
}
