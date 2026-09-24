import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/presence/manual_presence_widgets.dart';
import 'package:starbridge_flutter/app/shell/widgets/account_identity_button.dart';
import 'package:starbridge_flutter/app/shell/widgets/account_menu.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';

import '../tray_quick_panel_test.dart' show app;
import '../../features/friends/social_layout_test.dart' show loadFonts;

ManualPresenceSnapshot state(
  PresenceVisibility? mode, {
  Object scope = 1,
  bool writable = true,
  String automatic = 'presence.online',
}) => ManualPresenceSnapshot(
  scope: scope,
  confirmedMode: mode,
  canChange: writable,
  automaticKey: automatic,
);

void main() {
  setUpAll(loadFonts);
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final width in [260.0, 390.0]) {
      testWidgets('inline identity and lower status $locale at $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 120);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final source = ValueNotifier(state(PresenceVisibility.online));
        final control = ManualPresenceController(source: source);
        addTearDown(source.dispose);
        addTearDown(control.dispose);
        final capture = GlobalKey();
        final name = locale.languageCode == 'en' ? 'Example Captain' : '示例舰长';
        await tester.pumpWidget(
          app(
            RepaintBoundary(
              key: capture,
              child: AccountIdentityButton(
                avatar: const CircleAvatar(child: Text('A')),
                name: name,
                gameId: 'Captain-Test',
                presence: control,
                onPressed: () {},
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        final nameRect = tester.getRect(find.text(name));
        final idRect = tester.getRect(
          find.byKey(const Key('account-identity-handle')),
        );
        expect(idRect.left, greaterThan(nameRect.right));
        expect(idRect.center.dy, closeTo(nameRect.center.dy, 4));
        expect(
          tester.getRect(find.byKey(const Key('manual-presence-self'))).top,
          greaterThanOrEqualTo(nameRect.bottom),
        );
        expect(
          tester.getSize(find.byType(AccountIdentityButton)).width,
          lessThanOrEqualTo(width),
        );
        expect(tester.takeException(), isNull);
        if (locale.countryCode == 'CN' && width == 390) {
          final boundary =
              capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('build/account-identity-inline-preview.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('avatar menu opens and switches confirmed self status', (
    tester,
  ) async {
    final source = ValueNotifier(state(PresenceVisibility.online));
    final control = ManualPresenceController(
      source: source,
      write: (mode, _) async {
        source.value = state(mode);
      },
    );
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Localizations.override(
            context: context,
            delegates: const [AppStringsDelegate()],
            child: AccountMenu(
              destinations: const [],
              onIssueAction: () {},
              projection: const ShellChromeProjection(
                overlay: OverlaySceneProjection(
                  options: [],
                  preferredSceneId: null,
                  actualSceneId: null,
                  canChange: false,
                ),
                accountLabel: '测试舰长',
                presenceKey: 'presence.online',
                syncKey: 'sync.idle',
                friendAttentionCount: 0,
                notificationCount: 0,
                accountSignedIn: true,
              ),
              expanded: true,
              onSelect: (_) {},
              onLogin: () {},
              onLogout: () {},
              manualPresence: control,
              accountHandle: 'Captain-Test',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-identity-command')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manual-presence-invisible')), findsNothing);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('account-presence-menu'))),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const Key('manual-presence-invisible')),
      findsNothing,
      reason: 'Presence options open on click, not hover.',
    );
    await mouse.removePointer();
    await tester.tap(find.byKey(const Key('account-presence-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manual-presence-inGame')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manual-presence-invisible')), findsNothing);
    expect(find.byKey(const Key('account-presence-menu')), findsNothing);
    await tester.tap(find.byKey(const Key('account-identity-command')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manual-presence-invisible')), findsNothing);
    await tester.tap(find.byKey(const Key('account-presence-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manual-presence-invisible')), findsOneWidget);
    await tester.tap(find.byKey(const Key('manual-presence-invisible')));
    await tester.pumpAndSettle();
    expect(control.snapshot.selfKey, 'presence.invisible');
    expect(find.text('隐身'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    control.dispose();
    source.dispose();
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'manual options use state colors and game remains automatic $locale',
      (tester) async {
        final source = ValueNotifier(
          state(PresenceVisibility.online, automatic: 'presence.inGame'),
        );
        final control = ManualPresenceController(
          source: source,
          write: (mode, _) async {
            source.value = state(mode, automatic: 'presence.inGame');
          },
        );
        addTearDown(source.dispose);
        addTearDown(control.dispose);
        await tester.pumpWidget(
          app(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ManualPresenceBadge(controller: control),
                ManualPresenceChoices(controller: control),
              ],
            ),
            locale: locale,
          ),
        );
        final context = tester.element(find.byType(ManualPresenceChoices));
        final colors = context.tokens.colors;
        Color? dot(String mode) =>
            (tester
                        .widget<DecoratedBox>(
                          find.byKey(ValueKey('manual-presence-dot-$mode')),
                        )
                        .decoration
                    as BoxDecoration)
                .color;
        expect(dot('online'), colors.info);
        expect(dot('invisible'), colors.offline);
        expect(find.byType(MenuItemButton), findsNWidgets(2));
        expect(find.byKey(const Key('manual-presence-inGame')), findsNothing);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('manual-presence-self')))
              .style!
              .color,
          colors.success,
        );
        await tester.tap(find.byKey(const Key('manual-presence-invisible')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const Key('manual-presence-self')))
              .style!
              .color,
          colors.offline,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('invisible stays visible to self across game and disconnection', () {
    for (final automatic in [
      'presence.online',
      'presence.inGame',
      'presence.offline',
    ]) {
      expect(
        state(PresenceVisibility.invisible, automatic: automatic).selfKey,
        'presence.invisible',
      );
    }
    expect(state(null).selfKey, 'presence.unknown');
  });

  test(
    'pending selection does not claim invisible; duplicate writes guarded',
    () async {
      final source = ValueNotifier(state(PresenceVisibility.online));
      final done = Completer<void>();
      var calls = 0;
      final control = ManualPresenceController(
        source: source,
        write: (mode, scope) async {
          calls++;
          await done.future;
          source.value = state(mode);
        },
      );
      final write = control.select(PresenceVisibility.invisible);
      await control.select(PresenceVisibility.inGame);
      expect(calls, 1);
      expect(control.snapshot.selfKey, 'presence.online');
      done.complete();
      await write;
      expect(control.snapshot.selfKey, 'presence.invisible');
      expect(control.failed, false);
      control.dispose();
      source.dispose();
    },
  );

  test(
    'transport success without authoritative update is not success',
    () async {
      final source = ValueNotifier(state(PresenceVisibility.online));
      final control = ManualPresenceController(
        source: source,
        write: (_, _) async {},
      );
      await control.select(PresenceVisibility.invisible);
      expect(control.failed, true);
      expect(control.snapshot.selfKey, 'presence.online');
      control.dispose();
      source.dispose();
    },
  );

  test('write failure preserves confirmed mode and supports retry', () async {
    final source = ValueNotifier(state(PresenceVisibility.invisible));
    var fail = true;
    final control = ManualPresenceController(
      source: source,
      write: (mode, _) async {
        if (fail) throw StateError('private');
        source.value = state(mode);
      },
    );
    await control.select(PresenceVisibility.online);
    expect(control.failed, true);
    expect(control.snapshot.selfKey, 'presence.invisible');
    fail = false;
    await control.select(PresenceVisibility.online);
    expect(control.failed, false);
    expect(control.snapshot.selfKey, 'presence.online');
    control.dispose();
    source.dispose();
  });

  test('account generation change ignores stale completion feedback', () async {
    final source = ValueNotifier(state(PresenceVisibility.online));
    final done = Completer<void>();
    final control = ManualPresenceController(
      source: source,
      write: (_, scope) {
        expect(scope, 1);
        return done.future;
      },
    );
    final write = control.select(PresenceVisibility.invisible);
    source.value = state(null, scope: 2, writable: false);
    done.completeError(StateError('old account'));
    await write;
    expect(control.failed, false);
    expect(control.busy, false);
    expect(control.canChange, false);
    expect(control.snapshot.selfKey, 'presence.unknown');
    control.dispose();
    source.dispose();
  });

  testWidgets('wide identity, tray and selector share confirmed invisible', (
    tester,
  ) async {
    final source = ValueNotifier(state(PresenceVisibility.online));
    final control = ManualPresenceController(
      source: source,
      write: (mode, _) async {
        source.value = state(mode);
      },
    );
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: Column(
            children: [
              AccountIdentityButton(
                avatar: const CircleAvatar(child: Text('A')),
                name: '测试舰长',
                gameId: 'Captain-Test',
                onPressed: () {},
                presence: control,
              ),
              SizedBox(
                width: 300,
                child: ManualPresenceChoices(controller: control),
              ),
              TrayQuickPanel(
                state: const TrayQuickPanelState(),
                onDismiss: () {},
                manualPresence: control,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('@Captain-Test'), findsOneWidget);
    expect(
      tester.getSize(find.byType(AccountIdentityButton)).width,
      lessThanOrEqualTo(320),
    );
    expect(
      tester.getRect(find.text('@Captain-Test')).left,
      greaterThan(tester.getRect(find.text('测试舰长')).right),
    );
    await tester.tap(find.byKey(const Key('manual-presence-invisible')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manual-presence-self')), findsNWidgets(2));
    for (final text in tester.widgetList<Text>(
      find.byKey(const Key('manual-presence-self')),
    )) {
      expect(text.data, '隐身');
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    control.dispose();
    source.dispose();
  });

  testWidgets('identity width follows content and long text stays bounded', (
    tester,
  ) async {
    final source = ValueNotifier(state(PresenceVisibility.online));
    final control = ManualPresenceController(source: source);
    addTearDown(control.dispose);
    addTearDown(source.dispose);
    Future<double> widthFor(String name, String id) async {
      await tester.pumpWidget(
        app(
          Center(
            child: AccountIdentityButton(
              avatar: const Text('A'),
              name: name,
              gameId: id,
              presence: control,
              onPressed: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(const Key('account-identity-handle'))).left,
        greaterThan(tester.getRect(find.text(name)).right),
      );
      final status = find.byKey(const Key('manual-presence-self'));
      expect(
        tester.getRect(status).top,
        greaterThanOrEqualTo(tester.getRect(find.text(name)).bottom),
      );
      return tester.getSize(find.byType(AccountIdentityButton)).width;
    }

    final short = await widthFor('甲', 'A');
    final medium = await widthFor('测试舰长', 'Captain-Test');
    final long = await widthFor(
      'Long commander name ' * 20,
      'Long-Handle-' * 20,
    );
    expect(short, lessThan(medium));
    expect(medium, lessThanOrEqualTo(long));
    expect(long, lessThanOrEqualTo(320));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow trigger, missing game ID, no heavy border', (
    tester,
  ) async {
    final source = ValueNotifier(state(null, writable: false));
    final control = ManualPresenceController(source: source);
    await tester.pumpWidget(
      app(
        AccountIdentityButton(
          avatar: const Text('A'),
          name: '测试舰长',
          onPressed: () {},
          presence: control,
          compact: true,
        ),
      ),
    );
    expect(tester.getSize(find.byType(AccountIdentityButton)).width, 44);
    expect(find.byKey(const Key('account-identity-handle')), findsNothing);
    final button = tester.widget<TextButton>(
      find.byKey(const Key('account-identity-command')),
    );
    expect(button.style!.side!.resolve({}), BorderSide.none);
    await tester.pumpWidget(const SizedBox());
    control.dispose();
    source.dispose();
  });
}
