import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_composer.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';

void main() {
  testWidgets(
    'local typing survives late echoes; check does not advance revision',
    (tester) async {
      final actions =
          <({String action, String key, String text, int revision})>[];
      Future<void> subject({
        String draft = '',
        int revision = 0,
        String status = 'idle',
        bool locked = false,
        bool disconnected = false,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: MenuCommsComposer(
                  view: MenuCommsView(
                    'ready',
                    compose: true,
                    name: 'Fixture',
                    profileKey: 'c1',
                    canSend: true,
                    draft: draft,
                    draftRevision: revision,
                    delivery: status,
                    locked: locked,
                  ),
                  disconnected: disconnected,
                  onCompose: (action, key, text, version) => actions.add((
                    action: action,
                    key: key,
                    text: text,
                    revision: version,
                  )),
                ),
              ),
            ),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('menu-message-draft'));
      String text() => tester.widget<TextField>(field).controller!.text;
      await subject();
      await tester.enterText(field, 'hello\nworld');
      expect(actions.single.action, 'edit');
      await subject();
      expect(text(), 'hello\nworld');
      await tester.tap(find.byKey(const ValueKey('menu-message-send')));
      await tester.pump();
      expect(actions.last.action, 'send');
      expect(actions.last.revision, 2);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('menu-message-send')),
            )
            .onPressed,
        isNull,
      );
      await subject(
        draft: 'hello\nworld',
        revision: 3,
        status: 'unknown',
        locked: true,
      );
      await tester.tap(find.byKey(const ValueKey('menu-message-check')));
      expect(actions.last.action, 'check');
      expect(actions.last.revision, 3);
      await subject(revision: 4, status: 'sent');
      expect(text(), '');
      expect(find.text('已发送'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'bridge failure is visible, keeps unsaved text and does not allow a second send',
    (tester) async {
      var disconnected = false;
      late StateSetter update;
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return SingleChildScrollView(
                  child: MenuCommsComposer(
                    view: const MenuCommsView(
                      'ready',
                      compose: true,
                      name: 'Fixture',
                      profileKey: 'c1',
                      canSend: true,
                    ),
                    disconnected: disconnected,
                    onCompose: (action, key, text, revision) =>
                        actions.add(action),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('menu-message-draft'));
      await tester.enterText(field, 'draft');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('menu-message-send')));
      update(() => disconnected = true);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, 'draft');
      expect(tester.widget<TextField>(field).readOnly, false);
      expect(find.textContaining('通讯连接中断'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('menu-message-send')),
            )
            .onPressed,
        isNull,
      );
      expect(actions, ['edit', 'send']);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('input honors transport limit including surrogate pairs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuCommsComposer(
            view: const MenuCommsView(
              'ready',
              compose: true,
              name: 'Fixture',
              profileKey: 'c1',
            ),
            onCompose: (_, key, text, revision) {},
          ),
        ),
      ),
    );
    final field = find.byKey(const ValueKey('menu-message-draft'));
    await tester.enterText(field, '😀' * 500);
    expect(tester.widget<TextField>(field).controller!.text.length, 1000);
    await tester.enterText(field, '😀' * 501);
    expect(tester.widget<TextField>(field).controller!.text.length, 1000);
    await tester.pump(const Duration(seconds: 6));
    expect(find.textContaining('草稿暂未确认保存'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('menu-message-send')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
