import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

class Inbox extends NotificationInboxController {
  Inbox() : super(null) {
    ready = true;
    items = List.generate(
      20,
      (i) => InboxItem(
        i.toRadixString(16).padLeft(32, '0'),
        'room',
        'normal',
        'Invitation $i',
        'Read this invitation before deciding to join.',
        DateTime(2026),
        false,
        'room_invitations',
        '',
        true,
      ),
    );
  }
  final reads = <String>[];
  @override
  Future<bool> refresh({bool quiet = false, bool reuseFresh = false}) async =>
      true;
  @override
  Future<bool> markRead(List<InboxItem> selected) async {
    reads.addAll(selected.map((x) => x.reference));
    return false; // Failed receipts must not cause an automatic retry storm.
  }
}

Widget app(
  Inbox inbox, {
  bool active = true,
  void Function(String)? navigate,
}) => MaterialApp(
  theme: buildStarBridgeTheme(
    StyleRegistry()
        .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
        .tokens,
    const Locale('en'),
  ),
  home: Actions(
    actions: {
      OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
        onInvoke: (i) {
          navigate?.call(i.route);
          return null;
        },
      ),
    },
    child: NativeViewportScope(
      active: active,
      child: Scaffold(body: NotificationInboxPage(controller: inbox)),
    ),
  ),
);

void main() {
  testWidgets('covered notifications are not read until the dialog closes', (
    tester,
  ) async {
    final inbox = Inbox();
    addTearDown(inbox.dispose);
    await tester.pumpWidget(app(inbox));
    final context = tester.element(find.byType(NotificationInboxPage));
    final dialog = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('cover')),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(inbox.reads, isEmpty);
    Navigator.of(context).pop();
    await dialog;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(inbox.reads, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('immediate action click records the clicked notification', (
    tester,
  ) async {
    final inbox = Inbox();
    addTearDown(inbox.dispose);
    await tester.pumpWidget(app(inbox));
    expect(inbox.reads, isEmpty);
    await tester.tap(find.text('Open related page').first);
    expect(inbox.reads, [inbox.items.first.reference]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only visible active inbox rows are read, without retry loops', (
    tester,
  ) async {
    final inbox = Inbox();
    addTearDown(inbox.dispose);
    await tester.pumpWidget(app(inbox, active: false));
    await tester.pump(const Duration(seconds: 2));
    expect(inbox.reads, isEmpty);
    await tester.pumpWidget(app(inbox));
    await tester.pump(const Duration(seconds: 1));
    expect(inbox.reads, contains(inbox.items.first.reference));
    expect(inbox.reads, isNot(contains(inbox.items.last.reference)));
    final count = inbox.reads.length;
    await tester.pump(const Duration(seconds: 5));
    expect(inbox.reads.length, count);
    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(inbox.reads.length, greaterThan(count));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('room invitation action targets invitations, not room search', (
    tester,
  ) async {
    final inbox = Inbox();
    addTearDown(inbox.dispose);
    String? route;
    await tester.pumpWidget(app(inbox, navigate: (value) => route = value));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open related page').first);
    expect(route, '/rooms/invitations');
    await tester.pumpWidget(const SizedBox());
  });
}
