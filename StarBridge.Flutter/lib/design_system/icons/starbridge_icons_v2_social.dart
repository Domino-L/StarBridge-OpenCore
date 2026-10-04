import 'package:flutter/material.dart';

import 'starbridge_icons_v2_pen.dart';
import 'starbridge_icons_v2_spec.dart';

final List<IconSpec> socialIconsV2 = [
  // 社交与通讯 -------------------------------------------------------------
  IconSpec(
    'friends',
    '好友',
    iconGroups[1],
    ['SB.friends', 'Std.people', 'Menu.friends'],
    (g) {
      g.head(9, 7.8, 2.8);
      g.bust(9, 13.2, 6.2, 20);
      g.head(16.6, 6.8, 2.3);
      g.path(
        Path()
          ..moveTo(14.6, 12.2)
          ..cubicTo(15.2, 11.8, 15.9, 11.6, 16.6, 11.6)
          ..cubicTo(19.2, 11.6, 20.8, 13.6, 21, 17.4),
      );
    },
  ),
  IconSpec('person', '个人', iconGroups[1], ['Std.person', 'Menu.person'], (g) {
    g.head(12, 7.6, 3.4);
    g.bust(12, 13.8, 7, 20.5);
  }),
  IconSpec(
    'account',
    '账号',
    iconGroups[1],
    ['SB.account', 'Std.accountCircle'],
    (g) {
      g.oct(12, 12, 9.2);
      g.head(12, 9.6, 2.7);
      g.bust(12, 14.4, 4.6, 19.4);
    },
    note: '八角徽框',
  ),
  IconSpec('profile', '个人资料', iconGroups[1], ['SB.profile'], (g) {
    g.cut(3, 5, 21, 19);
    g.head(8.5, 10, 1.9);
    g.path(
      Path()
        ..moveTo(5.6, 15.6)
        ..cubicTo(6.1, 13.6, 7.2, 12.9, 8.5, 12.9)
        ..cubicTo(9.8, 12.9, 10.9, 13.6, 11.4, 15.6),
    );
    g.l(14, 10, 18, 10);
    if (g.fine) g.l(14, 14, 17, 14);
  }),
  IconSpec('publicProfile', '公开资料', iconGroups[1], ['SB.publicProfile'], (g) {
    g.head(8, 8.6, 2.7);
    g.bust(8, 14.2, 5, 20.5);
    g.p([14, 8, 16, 12, 14, 16]);
    g.p([17.5, 5.5, 20.5, 12, 17.5, 18.5]);
  }, note: '多面信号波'),
  IconSpec(
    'personAdd',
    '添加好友',
    iconGroups[1],
    ['Std.personAddAlt', 'Menu.addFriend'],
    (g) {
      paintIconPersonAt(g, 9);
      g.l(18.5, 5, 18.5, 11);
      g.l(15.5, 8, 21.5, 8);
    },
  ),
  IconSpec('personRemove', '移除成员', iconGroups[1], ['Std.personRemove'], (g) {
    paintIconPersonAt(g, 9);
    g.l(15.5, 8, 21.5, 8);
  }),
  IconSpec('groupAdd', '邀请加入', iconGroups[1], ['Std.groupAdd'], (g) {
    g.head(7, 9, 2.5);
    g.bust(7, 14.2, 4.8, 20.5);
    g.head(12.4, 8.2, 2.0);
    g.path(
      Path()
        ..moveTo(11, 13.1)
        ..cubicTo(11.4, 12.8, 11.9, 12.7, 12.4, 12.7)
        ..cubicTo(14.5, 12.7, 15.8, 14.4, 16, 17.8),
    );
    g.l(18.5, 3.5, 18.5, 9.5);
    g.l(15.5, 6.5, 21.5, 6.5);
  }),
  IconSpec(
    'messages',
    '通讯',
    iconGroups[1],
    ['SB.messages', 'Std.chatBubble', 'Menu.chat', 'Window.chat'],
    (g) {
      g.p([4, 4, 17, 4, 20, 7, 20, 16, 10, 16, 4, 21, 4, 4]);
      g.l(8, 8.5, 15, 8.5);
      if (g.fine) g.l(8, 12, 13, 12);
    },
    note: '切角气泡',
  ),
  IconSpec(
    'notifications',
    '通知',
    iconGroups[1],
    ['SB.notifications'],
    paintIconBell,
    note: '多面铃',
  ),
  IconSpec('reminder', '提醒', iconGroups[1], ['SB.reminder'], (g) {
    paintIconBell(g);
    if (g.fine) g.spark(19.6, 4.4, 2.5);
  }, note: '铃 + 星芒'),
  IconSpec('announcement', '公告', iconGroups[1], ['Std.campaign'], (g) {
    g.p([
      3.5,
      9.5,
      7.5,
      9.5,
      16.5,
      4.5,
      16.5,
      19.5,
      7.5,
      14.5,
      3.5,
      14.5,
    ], close: true);
    g.l(6.5, 14.5, 8, 20);
    if (g.fine) {
      g.l(19.5, 12, 21.5, 12);
      g.l(19.4, 8.2, 21, 7.2);
      g.l(19.4, 15.8, 21, 16.8);
    }
  }),
  IconSpec('mention', '联系方式', iconGroups[1], ['Std.alternateEmail'], (g) {
    g.oct(11.5, 12, 3.3);
    g.p([
      15,
      8.6,
      15,
      14.2,
      16.4,
      15.6,
      18.7,
      15.6,
      20.1,
      14,
      20.1,
      8.6,
      15.4,
      3.9,
      8.6,
      3.9,
      3.9,
      8.6,
      3.9,
      15.4,
      8.6,
      20.1,
      15.5,
      20.1,
    ]);
  }, note: '多面 @'),
  IconSpec('send', '发送', iconGroups[1], ['Std.send'], (g) {
    g.rot(-26, () {
      g.p([3.5, 4.8, 21, 12, 3.5, 19.2, 8, 12], close: true);
      if (g.fine) g.l(8, 12, 15, 12);
    });
  }, note: '沿航向角的飞镖'),
  IconSpec('attach', '附件', iconGroups[1], ['Std.attachFile'], (g) {
    g.rot(40, () {
      g.p([
        12,
        7.5,
        12,
        16,
        13.75,
        17.75,
        15.5,
        16,
        15.5,
        5,
        13.5,
        3,
        10.5,
        3,
        8.5,
        5,
        8.5,
        18.5,
        10.5,
        20.5,
      ]);
    });
  }),
  IconSpec('share', '分享', iconGroups[1], ['Std.share'], (g) {
    g.p([10.5, 4.5, 4, 4.5, 4, 20, 19.5, 20, 19.5, 13.5]);
    g.arrow(10, 14, 20.5, 3.5);
  }),
  IconSpec('invite', '已发邀请', iconGroups[1], ['Std.outbox'], (g) {
    g.p([3.5, 12.5, 3.5, 20.5, 20.5, 20.5, 20.5, 12.5]);
    g.arrow(12, 16.5, 12, 3.5);
  }),
];
