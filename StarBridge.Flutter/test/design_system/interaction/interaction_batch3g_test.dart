import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/product_features.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_surface_app.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_surface_app_frame.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/communities/community_section_navigation.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/platform/window/menu_interaction_presentation.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';

import '../../app/menu_overlay/menu_overlay_surface_app_test.dart'
    show snapshot, push, channel;
import 'interaction_preferences_test.dart' show MemoryStore;

const primary = MethodChannel('starbridge/menu-primary');

class ObservedPresentation extends ValueNotifier<MenuInteractionPresentation> {
  ObservedPresentation(super.value);
  bool get observed => hasListeners;
}

Future<void> incoming(
  WidgetTester t,
  MethodChannel target,
  String method,
  Object? args,
) async {
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    target.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
}

Future<void> twoFrames(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

MenuInteractionPresentation presentation(
  MenuInteractionStyle style, {
  bool reduce = false,
}) => MenuInteractionPresentation(style: style, reduceMotion: reduce);

Future<bool> open(MethodChannelMenuPreviewWindow window) => window.open(
  contextLabel: 'Context',
  returnLabel: 'Return',
  settingsLabel: 'Settings',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(primary, null);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('display envelope strictly validates schema, style, bool and size', () {
    for (final style in MenuInteractionStyle.values) {
      for (final reduce in [false, true]) {
        final original = presentation(style, reduce: reduce);
        final decoded = MenuInteractionPresentation.parse(original.encode())!;
        expect(decoded.style, style);
        expect(decoded.reduceMotion, reduce);
        expect(utf8.encode(original.encode()).length, lessThanOrEqualTo(128));
      }
    }
    for (final invalid in [
      null,
      {},
      '',
      '[1]',
      'null',
      '{',
      jsonEncode({'schemaVersion': 2, 'style': 'rail', 'reduceMotion': false}),
      jsonEncode({
        'schemaVersion': 1,
        'style': 'unknown',
        'reduceMotion': false,
      }),
      jsonEncode({'schemaVersion': 1, 'style': 'rail', 'reduceMotion': 0}),
      jsonEncode({
        'schemaVersion': 1,
        'style': 'rail',
        'reduceMotion': false,
        'account': 'forbidden',
      }),
      ' ' * 129,
    ]) {
      expect(MenuInteractionPresentation.parse(invalid), isNull);
    }
  });

  test(
    'feed borrows one subscription, filters unrelated updates and retires',
    () {
      final changes = ChangeNotifier();
      var value = presentation(MenuInteractionStyle.rail);
      final feed = MenuInteractionFeed(changes: changes, read: () => value);
      final sent = <String>[];
      var current = true;
      void start() => feed.start(isCurrent: () => current, publish: sent.add);
      for (var i = 0; i < 20; i++) {
        start();
        feed.stop();
      }
      sent.clear();
      start();
      changes.notifyListeners();
      expect(sent.length, 1);
      value = presentation(MenuInteractionStyle.scan);
      changes.notifyListeners();
      expect(sent.length, 2);
      current = false;
      value = presentation(MenuInteractionStyle.glow);
      changes.notifyListeners();
      expect(sent.length, 2);
      feed.stop();
      current = true;
      changes.notifyListeners();
      expect(sent.length, 2);
      start();
      expect(
        MenuInteractionPresentation.parse(sent.last)!.style,
        MenuInteractionStyle.glow,
      );
      feed.stop();
      changes.dispose();
    },
  );

  test(
    'real composition uses the global owner, not menu layout preferences',
    () async {
      final preferences = InMemoryAppPreferences();
      final app = AppComposition.forShellReview(
        preferences: preferences,
        windowChrome: InMemoryWindowChrome(),
      );
      try {
        final window =
            app.overlaySettings.menuPreview! as MethodChannelMenuPreviewWindow;
        final feed = window.interaction!;
        final sent = <String>[];
        feed.start(isCurrent: () => true, publish: sent.add);
        for (final style in InteractionStyle.values) {
          await preferences.setInteractionStyle(style);
          expect(feed.read().style.name, style.name);
        }
        await preferences.setMotionPreference(MotionPreference.reduce);
        expect(feed.read().reduceMotion, true);
        final count = sent.length;
        await preferences.setLocale(const Locale('en'));
        expect(
          sent.length,
          count + 1,
          reason: 'the open menu follows the app language live',
        );
        final last = MenuInteractionPresentation.parse(sent.last)!;
        expect(last.language, 'en');
        expect(last.reduceMotion, true);
        await preferences.setLocale(const Locale('en'));
        expect(sent.length, count + 1);
        feed.stop();
      } finally {
        app.dispose();
      }
    },
    skip: !menuOverlayEnabled ? 'requires menu overlay build gate' : false,
  );

  for (final early in [false, true]) {
    testWidgets(
      'primary sends current selection and live updates, early ack=$early',
      (t) async {
        final changes = ObservedPresentation(
          presentation(MenuInteractionStyle.rail),
        );
        final calls = <MethodCall>[];
        int request = 0;
        Future<void> state(String value) =>
            incoming(t, primary, 'state', {'request': request, 'state': value});
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(primary, (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'preview') {
            request = (call.arguments as Map)['request'] as int;
            changes.value = presentation(MenuInteractionStyle.scan);
            if (early) await state('visible');
            return request + 10;
          }
          return null;
        });
        final window = MethodChannelMenuPreviewWindow(
          lifetime: MenuWindowLifetime(),
          interaction: MenuInteractionFeed(
            changes: changes,
            read: () => changes.value,
          ),
        );
        final pending = open(window);
        await t.pump();
        if (!early) await state('visible');
        expect(await pending, true);
        expect(
          MenuInteractionPresentation.parse(
            (calls.firstWhere((c) => c.method == 'preview').arguments
                as Map)['interactionPresentation'],
          )!.style,
          MenuInteractionStyle.rail,
        );
        await t.pump();
        final updates = calls
            .where((c) => c.method == 'interactionPresentation')
            .toList();
        expect(
          MenuInteractionPresentation.parse(
            (updates.last.arguments as Map)['payload'],
          )!.style,
          MenuInteractionStyle.scan,
          reason: 'preparation must not lose a settings change',
        );
        changes.value = presentation(MenuInteractionStyle.glow, reduce: true);
        await t.pump();
        expect(
          calls.where((c) => c.method == 'interactionPresentation').length,
          updates.length + 1,
        );
        await state('hidden');
        await t.pump();
        final hiddenCount = calls.length;
        changes.value = presentation(MenuInteractionStyle.standard);
        await t.pump();
        expect(calls.length, hiddenCount);
        final reopened = open(window);
        await t.pump();
        await state('visible');
        expect(await reopened, true);
        await t.pump();
        window.dispose();
        await t.pump();
        expect(changes.observed, false);
        changes.dispose();
      },
    );
  }

  testWidgets('replaced owner cannot forward or detach the new style feed', (
    t,
  ) async {
    final changes = ObservedPresentation(
      presentation(MenuInteractionStyle.rail),
    );
    final lifetime = MenuWindowLifetime();
    final calls = <MethodCall>[];
    int request = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(primary, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'preview') {
        request = (call.arguments as Map)['request'] as int;
        return request + 10;
      }
      return null;
    });
    MethodChannelMenuPreviewWindow create() => MethodChannelMenuPreviewWindow(
      lifetime: lifetime,
      interaction: MenuInteractionFeed(
        changes: changes,
        read: () => changes.value,
      ),
    );
    Future<void> show(MethodChannelMenuPreviewWindow window) async {
      final pending = open(window);
      await t.pump();
      await incoming(t, primary, 'state', {
        'request': request,
        'state': 'visible',
      });
      expect(await pending, true);
      await t.pump();
    }

    final old = create();
    await show(old);
    final oldRequest = request;
    final next = create();
    await show(next);
    old.dispose();
    await t.pump();
    calls.clear();
    await incoming(t, primary, 'state', {
      'request': oldRequest,
      'state': 'hidden',
    });
    changes.value = presentation(MenuInteractionStyle.glow);
    await t.pump();
    expect(calls.where((c) => c.method == 'interactionPresentation').length, 1);
    expect((calls.single.arguments as Map)['opening'], request + 10);
    next.dispose();
    await t.pump();
    expect(changes.observed, false);
    changes.dispose();
  });

  testWidgets('late transport failure cannot retire a reopened feed', (
    t,
  ) async {
    final changes = ObservedPresentation(
      presentation(MenuInteractionStyle.rail),
    );
    final feed = MenuInteractionFeed(
      changes: changes,
      read: () => changes.value,
    );
    final pending = Completer<void>();
    var count = 0, reject = false;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(primary, (
      call,
    ) async {
      if (call.method != 'interactionPresentation') return null;
      count++;
      if (count == 1) await pending.future;
      if (reject) throw PlatformException(code: 'menu.unavailable');
      return null;
    });
    feed.startForOpening(primary, 1, isCurrent: () => true);
    await t.pump();
    feed.stop();
    feed.startForOpening(primary, 2, isCurrent: () => true);
    await t.pump();
    pending.completeError(PlatformException(code: 'menu.unavailable'));
    await t.pump();
    expect(changes.observed, true);
    reject = true;
    changes.value = presentation(MenuInteractionStyle.scan);
    await t.pump();
    expect(changes.observed, false);
    final stopped = count;
    changes.value = presentation(MenuInteractionStyle.glow);
    await t.pump();
    expect(count, stopped);
    changes.dispose();
  });

  testWidgets('hide before delayed preview reply does not subscribe again', (
    t,
  ) async {
    final changes = ObservedPresentation(
      presentation(MenuInteractionStyle.rail),
    );
    final reply = Completer<int>();
    var request = 0;
    final methods = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(primary, (
      call,
    ) async {
      methods.add(call.method);
      if (call.method == 'preview') {
        request = (call.arguments as Map)['request'] as int;
        return reply.future;
      }
      return null;
    });
    final window = MethodChannelMenuPreviewWindow(
      lifetime: MenuWindowLifetime(),
      interaction: MenuInteractionFeed(
        changes: changes,
        read: () => changes.value,
      ),
    );
    final pending = open(window);
    await t.pump();
    await incoming(t, primary, 'state', {
      'request': request,
      'state': 'visible',
    });
    await incoming(t, primary, 'state', {
      'request': request,
      'state': 'hidden',
    });
    reply.complete(7);
    await pending;
    await t.pump();
    expect(changes.observed, false);
    changes.value = presentation(MenuInteractionStyle.scan);
    await t.pump();
    expect(
      methods.where((method) => method == 'interactionPresentation'),
      isEmpty,
    );
    window.dispose();
    await t.pump();
    changes.dispose();
  });

  for (final style in MenuInteractionStyle.values) {
    test(
      '$style menu follows failed-save rollback and confirmed reopen',
      () async {
        final store = MemoryStore()..pending = Completer();
        final owner = AppPreferencesModule();
        await owner.attachStore(store);
        final app = AppComposition.forTest(
          preferences: owner,
          windowChrome: InMemoryWindowChrome(),
        );
        try {
          final window =
              app.overlaySettings.menuPreview!
                  as MethodChannelMenuPreviewWindow;
          final feed = window.interaction!;
          final sent = <String>[];
          feed.start(isCurrent: () => true, publish: sent.add);
          final pending = owner.setInteractionStyle(
            InteractionStyle.values.byName(style.name),
          );
          expect(feed.read().style, style);
          expect(
            owner.projection.value.confirmed!.interactionStyle,
            InteractionStyle.standard,
          );
          store.pending!.completeError(
            const AppPreferencesStoreException(
              AppPreferencesFailure.saveFailed,
            ),
          );
          expect(await pending, false);
          expect(feed.read().style, MenuInteractionStyle.standard);
          feed.stop();
          owner.detachStore();
          store.pending = null;
          await owner.attachStore(store);
          expect(
            await owner.setInteractionStyle(
              InteractionStyle.values.byName(style.name),
            ),
            true,
          );
          owner.detachStore();
          await owner.attachStore(store);
          expect(feed.read().style, style);
          expect(store.writes, 2, reason: 'menu feed never writes preferences');
        } finally {
          app.dispose();
          owner.dispose();
        }
      },
      skip: !menuOverlayEnabled ? 'requires menu overlay build gate' : false,
    );

    testWidgets(
      'actual surface receives $style and rejects stale/invalid messages',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(1280, 900);
        addTearDown(t.view.reset);
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => null,
        );
        await t.pumpWidget(const MenuOverlaySurfaceApp(workspacePreview: true));
        await t.pump();
        await push(t, {
          ...snapshot(4),
          'interactionPresentation': presentation(style).encode(),
        });
        await twoFrames(t);
        InteractionData effective() => resolveStarBridgeInteraction(
          t.element(
            find
                .descendant(
                  of: find.byType(MenuPresentation),
                  matching: find.byType(CallbackShortcuts),
                )
                .first,
          ),
        );
        expect(effective().suite.name, style.name);
        Future<void> update(
          Object? payload, {
          int opening = 4,
          int revision = 1,
        }) async {
          await incoming(t, channel, 'interactionPresentation', {
            'opening': opening,
            'revision': revision,
            'payload': payload,
          });
          await twoFrames(t);
        }

        await update(presentation(style, reduce: true).encode());
        expect(effective().reduceMotion, true);
        await update(
          presentation(MenuInteractionStyle.glow).encode(),
          opening: 3,
          revision: 50,
        );
        await update(
          presentation(MenuInteractionStyle.glow).encode(),
          revision: 0,
        );
        await update(
          '{"schemaVersion":1,"style":"bogus","reduceMotion":false}',
          revision: 90,
        );
        expect(effective().suite.name, style.name);
        expect(effective().reduceMotion, true);
        await update(presentation(style).encode(), revision: 2);
        expect(effective().reduceMotion, false);
        await push(t, snapshot(4, wanted: false));
        await update(
          presentation(MenuInteractionStyle.glow).encode(),
          revision: 99,
        );
        await push(t, snapshot(5));
        await twoFrames(t);
        expect(
          effective().suite,
          InteractionSuite.standard,
          reason: 'older sender has no retained previous opening style',
        );
        expect(effective().reduceMotion, false);
        await t.pumpWidget(const SizedBox());
        await t.pump();
      },
    );

    for (final guard in ['global', 'system', 'menu', 'safe']) {
      testWidgets(
        '$style menu combines $guard reduction without disabling interaction',
        (t) async {
          var calls = 0;
          final value = presentation(style, reduce: guard == 'global');
          await t.pumpWidget(
            MenuSurfaceAppFrame(
              observer: NavigatorObserver(),
              interaction: value,
              child: MediaQuery(
                data: MediaQueryData(disableAnimations: guard == 'system'),
                child: MenuPresentation(
                  safeMode: guard == 'safe',
                  reduceMotion: guard == 'menu',
                  child: Builder(
                    builder: (context) {
                      final data = resolveStarBridgeInteraction(context);
                      expect(data.suite.name, style.name);
                      expect(data.reduceMotion, true);
                      expect(InteractionScope.of(context).reduceMotion, true);
                      expect(TickerMode.valuesOf(context).enabled, true);
                      return Material(
                        child: Center(
                          child: CommunitySectionNavigation(
                            sections: const {'members': true, 'chat': true},
                            selected: 'members',
                            onSelected: (_) => calls++,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await t.pump();
          await t.tap(find.byKey(const ValueKey('community-section-chat')));
          expect(calls, 1);
          await t.pumpWidget(const SizedBox());
          await t.pump();
        },
      );
    }

    testWidgets(
      '$style open dialog follows menu frame update within two frames',
      (t) async {
        final settings = ValueNotifier(presentation(style));
        final observer = NavigatorObserver();
        await t.pumpWidget(
          ValueListenableBuilder<MenuInteractionPresentation>(
            valueListenable: settings,
            builder: (_, value, _) => MenuSurfaceAppFrame(
              observer: observer,
              interaction: value,
              child: MenuPresentation(
                safeMode: false,
                child: Builder(
                  builder: (context) => GestureDetector(
                    onTap: () => unawaited(
                      showStarBridgeDialog<void>(
                        context,
                        source: InteractionSource.pointer,
                        builder: (_) =>
                            const Dialog(child: Text('dialog body')),
                      ),
                    ),
                    child: const Text('open dialog'),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pump();
        await t.tap(find.text('open dialog'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 40));
        settings.value = presentation(MenuInteractionStyle.scan, reduce: true);
        await twoFrames(t);
        final context = t.element(find.text('dialog body'));
        expect(InteractionScope.of(context).suite, InteractionSuite.scan);
        expect(InteractionScope.of(context).reduceMotion, true);
        final route = ModalRoute.of(context)! as StarBridgeDialogRoute;
        expect(route.animation!.value, 1);
        dismissStarBridgeDialog(context, source: InteractionSource.keyboard);
        await twoFrames(t);
        expect(find.text('dialog body'), findsNothing);
        await t.pumpWidget(const SizedBox());
        await t.pump();
        settings.dispose();
      },
    );
  }
}
