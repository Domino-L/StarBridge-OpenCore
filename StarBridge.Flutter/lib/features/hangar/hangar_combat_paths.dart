import 'dart:ui';

// Exact 32x32 paths: approved small/medium V8, large/capital V2.
// Mechanically expanded M/L/H/V/Z from the original design handoff, not redrawn.
// Order: hull, port, starboard, ammunition, rectangular drive.
final Map<String, List<Path>> hangarCombatPaths = {
  'small': [
    // M16 3 19 11v12l-3 3-3-3V11Zm-1 8v5h2v-5Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(16, 3)
      ..lineTo(19, 11)
      ..lineTo(19, 23)
      ..lineTo(16, 26)
      ..lineTo(13, 23)
      ..lineTo(13, 11)
      ..close()
      ..moveTo(15, 11)
      ..lineTo(15, 16)
      ..lineTo(17, 16)
      ..lineTo(17, 11)
      ..close(),
    // M11 12 5 18 3 25l8-3Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(11, 12)
      ..lineTo(5, 18)
      ..lineTo(3, 25)
      ..lineTo(11, 22)
      ..close(),
    // M21 12l6 6 2 7-8-3Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(21, 12)
      ..lineTo(27, 18)
      ..lineTo(29, 25)
      ..lineTo(21, 22)
      ..close(),
    // M8 3.5 9.5 5.5v6h-3v-6Z M24 3.5l1.5 2v6h-3v-6Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(8, 3.5)
      ..lineTo(9.5, 5.5)
      ..lineTo(9.5, 11.5)
      ..lineTo(6.5, 11.5)
      ..lineTo(6.5, 5.5)
      ..close()
      ..moveTo(24, 3.5)
      ..lineTo(25.5, 5.5)
      ..lineTo(25.5, 11.5)
      ..lineTo(22.5, 11.5)
      ..lineTo(22.5, 5.5)
      ..close(),
    // M14 28h4v2h-4Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(14, 28)
      ..lineTo(18, 28)
      ..lineTo(18, 30)
      ..lineTo(14, 30)
      ..close(),
  ],
  'medium': [
    // M16 2 20 9v14l-4 6-4-6V9Zm-1 7v5h2V9Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(16, 2)
      ..lineTo(20, 9)
      ..lineTo(20, 23)
      ..lineTo(16, 29)
      ..lineTo(12, 23)
      ..lineTo(12, 9)
      ..close()
      ..moveTo(15, 9)
      ..lineTo(15, 14)
      ..lineTo(17, 14)
      ..lineTo(17, 9)
      ..close(),
    // M9 8v15l-6 5V17l3-3V8Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(9, 8)
      ..lineTo(9, 23)
      ..lineTo(3, 28)
      ..lineTo(3, 17)
      ..lineTo(6, 14)
      ..lineTo(6, 8)
      ..close(),
    // M23 8v15l6 5V17l-3-3V8Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(23, 8)
      ..lineTo(23, 23)
      ..lineTo(29, 28)
      ..lineTo(29, 17)
      ..lineTo(26, 14)
      ..lineTo(26, 8)
      ..close(),
    // M7.5 0 9 1.75V6H6V1.75Z M24.5 0 26 1.75V6h-3V1.75Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(7.5, 0)
      ..lineTo(9, 1.75)
      ..lineTo(9, 6)
      ..lineTo(6, 6)
      ..lineTo(6, 1.75)
      ..close()
      ..moveTo(24.5, 0)
      ..lineTo(26, 1.75)
      ..lineTo(26, 6)
      ..lineTo(23, 6)
      ..lineTo(23, 1.75)
      ..close(),
    // M7 29h3v2H7Zm15 0h3v2h-3Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(7, 29)
      ..lineTo(10, 29)
      ..lineTo(10, 31)
      ..lineTo(7, 31)
      ..close()
      ..moveTo(22, 29)
      ..lineTo(25, 29)
      ..lineTo(25, 31)
      ..lineTo(22, 31)
      ..close(),
  ],
  'large': [
    // M16 1 23 23l-3 4h-8l-3-4Zm-1.5 15v6h3v-6Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(16, 1)
      ..lineTo(23, 23)
      ..lineTo(20, 27)
      ..lineTo(12, 27)
      ..lineTo(9, 23)
      ..close()
      ..moveTo(14.5, 16)
      ..lineTo(14.5, 22)
      ..lineTo(17.5, 22)
      ..lineTo(17.5, 16)
      ..close(),
    // M3 15h4v12H3l-2-3 2-4Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(3, 15)
      ..lineTo(7, 15)
      ..lineTo(7, 27)
      ..lineTo(3, 27)
      ..lineTo(1, 24)
      ..lineTo(3, 20)
      ..close(),
    // M29 15h-4v12h4l2-3-2-4Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(29, 15)
      ..lineTo(25, 15)
      ..lineTo(25, 27)
      ..lineTo(29, 27)
      ..lineTo(31, 24)
      ..lineTo(29, 20)
      ..close(),
    // M5 6 7 8v5H3V8Z M27 6l2 2v5h-4V8Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(5, 6)
      ..lineTo(7, 8)
      ..lineTo(7, 13)
      ..lineTo(3, 13)
      ..lineTo(3, 8)
      ..close()
      ..moveTo(27, 6)
      ..lineTo(29, 8)
      ..lineTo(29, 13)
      ..lineTo(25, 13)
      ..lineTo(25, 8)
      ..close(),
    // M3 29h4v2H3Zm22 0h4v2h-4Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(3, 29)
      ..lineTo(7, 29)
      ..lineTo(7, 31)
      ..lineTo(3, 31)
      ..close()
      ..moveTo(25, 29)
      ..lineTo(29, 29)
      ..lineTo(29, 31)
      ..lineTo(25, 31)
      ..close(),
  ],
  'capital': [
    // M14 1h4l5 8v15l-3 4h-8l-3-4V9Zm.5 8v11l1.5 2 1.5-2V9Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(14, 1)
      ..lineTo(18, 1)
      ..lineTo(23, 9)
      ..lineTo(23, 24)
      ..lineTo(20, 28)
      ..lineTo(12, 28)
      ..lineTo(9, 24)
      ..lineTo(9, 9)
      ..close()
      ..moveTo(14.5, 9)
      ..lineTo(14.5, 20)
      ..lineTo(16, 22)
      ..lineTo(17.5, 20)
      ..lineTo(17.5, 9)
      ..close(),
    // M2 10h5v7H1v-4Z M1 19h6v9H4l-3-3Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(2, 10)
      ..lineTo(7, 10)
      ..lineTo(7, 17)
      ..lineTo(1, 17)
      ..lineTo(1, 13)
      ..close()
      ..moveTo(1, 19)
      ..lineTo(7, 19)
      ..lineTo(7, 28)
      ..lineTo(4, 28)
      ..lineTo(1, 25)
      ..close(),
    // M30 10h-5v7h6v-4Z M31 19h-6v9h3l3-3Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(30, 10)
      ..lineTo(25, 10)
      ..lineTo(25, 17)
      ..lineTo(31, 17)
      ..lineTo(31, 13)
      ..close()
      ..moveTo(31, 19)
      ..lineTo(25, 19)
      ..lineTo(25, 28)
      ..lineTo(28, 28)
      ..lineTo(31, 25)
      ..close(),
    // M4.5 0 7 2.5V8H2V2.5Z M27.5 0 30 2.5V8h-5V2.5Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(4.5, 0)
      ..lineTo(7, 2.5)
      ..lineTo(7, 8)
      ..lineTo(2, 8)
      ..lineTo(2, 2.5)
      ..close()
      ..moveTo(27.5, 0)
      ..lineTo(30, 2.5)
      ..lineTo(30, 8)
      ..lineTo(25, 8)
      ..lineTo(25, 2.5)
      ..close(),
    // M4 30h3v2H4Zm10 0h4v2h-4Zm11 0h3v2h-3Z
    Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(4, 30)
      ..lineTo(7, 30)
      ..lineTo(7, 32)
      ..lineTo(4, 32)
      ..close()
      ..moveTo(14, 30)
      ..lineTo(18, 30)
      ..lineTo(18, 32)
      ..lineTo(14, 32)
      ..close()
      ..moveTo(25, 30)
      ..lineTo(28, 30)
      ..lineTo(28, 32)
      ..lineTo(25, 32)
      ..close(),
  ],
};
