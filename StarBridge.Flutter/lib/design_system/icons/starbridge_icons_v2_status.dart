import 'starbridge_icons_v2_spec.dart';

final List<IconSpec> statusIconsV2 = [
  // 状态与选择 -------------------------------------------------------------
  IconSpec('success', '成功', iconGroups[6], ['Std.checkCircle'], (g) {
    g.oct(12, 12, 9);
    g.p([7.5, 12.2, 10.6, 15.2, 16.5, 9.2]);
  }),
  IconSpec('connected', '已连接', iconGroups[6], ['SB.connected'], (g) {
    g.rot(-45, () {
      g.l(0.5, 12, 6, 12);
      g.rect(6, 7.6, 10.8, 16.4);
      g.l(10.8, 9.9, 13.2, 9.9);
      g.l(10.8, 14.1, 13.2, 14.1);
      g.rect(13.2, 7.6, 18, 16.4);
      g.l(18, 12, 23.5, 12);
    });
  }, note: '插头接合'),
  IconSpec('disconnected', '已断开', iconGroups[6], ['SB.disconnected'], (g) {
    g.rot(-45, () {
      g.l(0, 12, 4.5, 12);
      g.rect(4.5, 7.6, 9.3, 16.4);
      g.l(9.3, 9.9, 11.5, 9.9);
      g.l(9.3, 14.1, 11.5, 14.1);
      g.rect(14.7, 7.6, 19.5, 16.4);
      g.l(19.5, 12, 24, 12);
      if (g.fine) {
        g.l(13.1, 3.5, 13.1, 5.5);
        g.l(13.1, 18.5, 13.1, 20.5);
      }
    });
  }, note: '插头分离'),
  IconSpec(
    'pending',
    '等待中',
    iconGroups[6],
    ['SB.pending', 'Std.hourglassTop'],
    (g) {
      g.l(5.5, 3.5, 18.5, 3.5);
      g.l(5.5, 20.5, 18.5, 20.5);
      g.p([7.5, 3.5, 7.5, 7, 11, 12, 7.5, 17, 7.5, 20.5]);
      g.p([16.5, 3.5, 16.5, 7, 13, 12, 16.5, 17, 16.5, 20.5]);
      if (g.fine) g.fp([12, 16.2, 15, 19.4, 9, 19.4]);
    },
  ),
  IconSpec('info', '说明', iconGroups[6], ['Std.info'], (g) {
    g.oct(12, 12, 9);
    g.dot(12, 7.9, 1.35);
    g.l(12, 11, 12, 16.5);
  }),
  IconSpec('warning', '警告', iconGroups[6], ['SB.warning', 'Std.warningAmber'], (
    g,
  ) {
    g.p([12, 3.5, 21, 19.5, 3, 19.5], close: true);
    g.l(12, 9.5, 12, 13.5);
    g.dot(12, 16.6, 1.3);
  }),
  IconSpec('radioOn', '单选·选中', iconGroups[6], ['Std.radioButtonChecked'], (g) {
    g.dia(12, 12, 8.5);
    g.dia(12, 12, 3.8, filled: true);
  }),
  IconSpec('radioOff', '单选·未选', iconGroups[6], [
    'Std.radioButtonUnchecked',
    'Std.radioButtonOff',
  ], (g) => g.dia(12, 12, 8.5)),
  IconSpec('dotFilled', '状态点', iconGroups[6], [
    'Std.circle',
  ], (g) => g.dia(12, 12, 5.5, filled: true)),
  IconSpec('dotOutline', '空状态点', iconGroups[6], [
    'Std.circleOutline',
  ], (g) => g.dia(12, 12, 6.5)),
];
