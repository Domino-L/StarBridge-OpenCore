import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/faded_name_tip.dart';

const _longName = '很长很长很长很长很长很长很长很长的舰船名称';
const _tip = Key('faded-name-tip');

Future<void> _pumpLabel(WidgetTester tester, Widget label) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 300),
      ),
    ),
    builder: (context, child) => FadedNameTip(child: child!),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 80, height: 20, child: label),
      ),
    ),
  ),
);

Future<TestGesture> _rest(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(700, 500));
  addTearDown(mouse.removePointer);
  await tester.pump();
  await mouse.moveTo(at);
  await tester.pump(const Duration(milliseconds: 400));
  return mouse;
}

Widget _faded(String text) =>
    Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.fade);

void main() {
  testWidgets('淡出被截断的文字：停留后显示全名，移开就消失', (tester) async {
    await _pumpLabel(tester, _faded(_longName));
    final mouse = await _rest(tester, const Offset(20, 10));
    expect(find.byKey(_tip), findsOneWidget);
    expect(find.text(_longName), findsNWidgets(2));
    await mouse.moveTo(const Offset(700, 500));
    await tester.pump();
    expect(find.byKey(_tip), findsNothing);
  });

  testWidgets('还没停够时不显示', (tester) async {
    await _pumpLabel(tester, _faded(_longName));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(const Offset(20, 10));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(_tip), findsNothing);
  });

  testWidgets('放得下的文字不显示', (tester) async {
    await _pumpLabel(tester, _faded('短名'));
    await _rest(tester, const Offset(10, 7));
    expect(find.byKey(_tip), findsNothing);
  });

  testWidgets('省略号的多行正文不显示', (tester) async {
    await _pumpLabel(
      tester,
      const Text(_longName, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    await _rest(tester, const Offset(20, 10));
    expect(find.byKey(_tip), findsNothing);
  });

  testWidgets('按下鼠标或键盘都会收起', (tester) async {
    await _pumpLabel(tester, _faded(_longName));
    final mouse = await _rest(tester, const Offset(20, 10));
    expect(find.byKey(_tip), findsOneWidget);
    await mouse.down(const Offset(20, 10));
    await tester.pump();
    expect(find.byKey(_tip), findsNothing);
    await mouse.up();
    await mouse.moveTo(const Offset(25, 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(_tip), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.byKey(_tip), findsNothing);
  });

  testWidgets('提示不挡点击，也不进读屏', (tester) async {
    var taps = 0;
    await _pumpLabel(
      tester,
      GestureDetector(onTap: () => taps++, child: _faded(_longName)),
    );
    final semantics = tester.ensureSemantics();
    final mouse = await _rest(tester, const Offset(20, 10));
    expect(find.byKey(_tip), findsOneWidget);
    final tipBox = tester.getRect(find.byKey(_tip));
    expect(tipBox.top, greaterThan(19));
    expect(
      find.ancestor(of: find.byKey(_tip), matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    expect(
      find.ancestor(
        of: find.byKey(_tip),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
    await mouse.down(const Offset(20, 10));
    await mouse.up();
    await tester.pump();
    expect(taps, 1);
    semantics.dispose();
  });
}
