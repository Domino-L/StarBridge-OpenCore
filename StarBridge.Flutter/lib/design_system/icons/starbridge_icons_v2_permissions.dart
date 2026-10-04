import 'package:flutter/material.dart';

import 'starbridge_icons_v2_pen.dart';
import 'starbridge_icons_v2_spec.dart';

final List<IconSpec> permissionsIconsV2 = [
  // 组织与权限 -------------------------------------------------------------
  IconSpec('role', '身份组', iconGroups[2], ['Std.badge'], (g) {
    g.p([4.5, 10.5, 12, 5, 19.5, 10.5]);
    g.p([4.5, 16, 12, 10.5, 19.5, 16]);
    g.l(7, 20, 17, 20);
  }, note: '军衔章'),
  IconSpec('verified', '权限包', iconGroups[2], ['Std.verifiedUser'], (g) {
    paintIconShield(g);
    g.p([8.4, 12, 11, 14.6, 15.8, 9.6]);
  }),
  IconSpec('admin', '管理权限', iconGroups[2], ['Std.adminPanelSettings'], (g) {
    paintIconShield(g);
    g.p([8.2, 11, 12, 8, 15.8, 11]);
    if (g.fine) g.p([8.2, 15, 12, 12, 15.8, 15]);
  }, note: '盾 + 军衔（指挥权）'),
  IconSpec('privacy', '隐私', iconGroups[2], ['SB.privacy'], (g) {
    paintIconShield(g);
    g.circle(12, 10, 1.8);
    g.l(12, 12, 12, 15);
  }),
  IconSpec('transfer', '转让', iconGroups[2], ['Std.swapHoriz'], (g) {
    g.arrow(3.5, 8, 20.5, 8);
    g.arrow(20.5, 16, 3.5, 16);
  }),
  IconSpec('copy', '复制', iconGroups[2], ['Std.copy'], paintIconCopyBase),
  IconSpec('copyAll', '复制识别码', iconGroups[2], ['Std.copyAll'], (g) {
    paintIconCopyBase(g);
    if (g.fine) {
      g.l(11.5, 13.5, 17, 13.5);
      g.l(11.5, 17, 15, 17);
    }
  }),
  IconSpec('visibility', '可见性', iconGroups[2], ['Std.visibility'], (g) {
    g.path(
      Path()
        ..moveTo(2.5, 12)
        ..quadraticBezierTo(12, 2.5, 21.5, 12)
        ..quadraticBezierTo(12, 21.5, 2.5, 12)
        ..close(),
    );
    g.circle(12, 12, 3.2);
  }, note: '生命体：保留曲线'),
];
