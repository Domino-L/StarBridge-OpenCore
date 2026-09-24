import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/app/localization/local_privacy_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';
import 'package:starbridge_flutter/features/settings/settings_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('confidence choice reuses draft, discard and confirmed save', (
    tester,
  ) async {
    viewport(tester, const Size(1440, 1100));
    final p = ConfidencePrivacy();
    final c = LocalPrivacyController(p);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
    await tester.pumpAndSettle();
    expect(c.draft!.effectiveHideLowConfidenceLocation, isTrue);
    expect(c.draft!.toJson().containsKey('hideLowConfidenceLocation'), isFalse);
    await tester.tap(find.byKey(const Key('privacy-location-confidence')));
    await tester.pumpAndSettle();
    expect(c.draft!.effectiveHideLowConfidenceLocation, isFalse);
    expect(p.writes, 0);
    c.discard();
    await tester.pumpAndSettle();
    expect(c.draft!.effectiveHideLowConfidenceLocation, isTrue);
    await tester.tap(find.byKey(const Key('privacy-location-confidence')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy-save')));
    await tester.pumpAndSettle();
    expect(p.snapshot.settings!.hideLowConfidenceLocation, isFalse);
    expect(
      LocalPrivacySettings.fromJson(p.snapshot.settings!.toJson())
          .hideLowConfidenceLocation,
      isFalse,
    );
    expect(c.dirty, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'saving the master switch applies sharing without a second control',
    (tester) async {
      viewport(tester, const Size(1440, 1100));
      final p = PublishingPrivacy();
      final c = LocalPrivacyController(p);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
      await tester.pumpAndSettle();
      expect(p.actions.where((a) => a != 'status'), isEmpty);
      expect(find.byKey(const Key('privacy-stop-publication')), findsNothing);
      await tester.tap(find.byKey(const Key('privacy-save')));
      await tester.pumpAndSettle();
      expect(p.actions.where((a) => a == 'apply'), hasLength(1));
      expect(c.publicationView.state, 'applied');
      expect(find.byKey(const Key('privacy-apply-publication')), findsNothing);
      if (const bool.fromEnvironment('CAPTURE_PRIVACY')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/privacy-publication-page.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      c.edit(c.draft!.copyWith(roomFields: 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy-stop-publication')), findsNothing);
      c.edit(c.draft!.copyWith(publicationEnabled: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy-save')));
      await tester.pumpAndSettle();
      expect(c.publicationView.state, 'withdrawalPending');
      expect(c.dirty, false);
      expect(p.writes, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'normal connected settings entry uses scoped privacy Bridge and leave guard',
    (tester) async {
      viewport(tester, const Size(1440, 1000));
      final host = PrivacyHost();
      final preferences = InMemoryAppPreferences();
      final composition = AppComposition.forConnectedProduct(
        nativeHost: host,
        preferences: preferences,
        windowChrome: InMemoryWindowChrome(),
      );
      var disposed = false;
      void disposeComposition() {
        if (disposed) return;
        disposed = true;
        composition.dispose();
        preferences.dispose();
      }

      addTearDown(disposeComposition);
      final feature = composition.features.byRoute('/settings');
      expect(feature.confirmLeave, isNotNull);
      await tester.pumpWidget(app(Builder(builder: feature.buildDestination)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-section-syncPrivacy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('local-privacy-page')), findsOneWidget);
      expect(
        host.requests
            .where((r) => r.name == 'privacy.localRead')
            .single
            .accountContext
            ?.subject,
        'privacy-fixture',
      );
      await tester.tap(find.byKey(const Key('privacy-save')));
      await tester.pumpAndSettle();
      expect(
        host.requests.where((r) => r.name == 'privacy.localSave').length,
        1,
      );
      expect(find.text('所有更改已保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      disposeComposition();
      await tester.pump();
    },
  );
  setUpAll(() async {
    for (final entry in const {
      'Source Sans 3': 'SourceSans3VF-Upright.ttf',
      'Source Han Sans CN': 'SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load('assets/fonts/${entry.value}'))).load();
    }
  });
  test('defaults are not saved until explicit save; independent axes and groups survive', () async {
    final p = MemoryPrivacy();
    final c = LocalPrivacyController(p);
    addTearDown(c.dispose);
    await c.refresh();
    expect(c.hasSaved, false);
    expect(c.dirty, false);
    expect(p.writes, 0);
    c.edit(c.draft!.copyWith(fleetFields: 1, roomFields: 4));
    expect(await c.save(), true);
    expect(p.snapshot.settings!.fleetFields, 1);
    expect(p.snapshot.settings!.roomFields, 4);
    await c.refresh();
    expect(c.dirty, false);
    expect(c.draft!.roomFields, 4);
  });
  test(
    'save failure retains draft and conflict remains reloadable after discard',
    () async {
      final p = MemoryPrivacy();
      final c = LocalPrivacyController(p);
      addTearDown(c.dispose);
      await c.refresh();
      c.edit(c.draft!.copyWith(roomFields: 0));
      p.failure = const BridgeClientException('privacy_local.write_failed');
      expect(await c.save(), false);
      expect(c.dirty, true);
      expect(c.draft!.roomFields, 0);
      p.failure = const BridgeClientException('privacy_local.conflict');
      expect(await c.save(), false);
      expect(c.needsReload, true);
      c.discard();
      expect(c.errorKey, 'privacy.local.conflict');
      expect(c.canSave, false);
      p.failure = null;
      await c.refresh();
      expect(c.canSave, true);
    },
  );
  test(
    'account invalidation clears dirty draft and rejects a late save response',
    () async {
      final p = MemoryPrivacy();
      final c = LocalPrivacyController(p);
      addTearDown(c.dispose);
      await c.refresh();
      c.edit(c.draft!.copyWith(roomFields: 0));
      p.pendingSave = Completer<LocalPrivacySnapshot>();
      final saving = c.save();
      p.events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(c.draft, isNull);
      expect(c.hasSaved, false);
      p.pendingSave!.complete(
        LocalPrivacySnapshot(
          revision: 1,
          settings: LocalPrivacySettings.editorDefaults,
        ),
      );
      expect(await saving, false);
      expect(c.draft, isNull);
    },
  );
  test(
    'unrelated edits preserve existing custom audience references',
    () async {
      final p = MemoryPrivacy()
        ..snapshot = LocalPrivacySnapshot(
          revision: 2,
          settings: LocalPrivacySettings(
            publicationEnabled: true,
            fleetFields: 63,
            fleetAdministratorsCanView: false,
            fleetAllMembersCanView: false,
            fleetVisibilityGroupIds: ['preserved-group'],
            roomFields: 63,
            roomAllMembersCanView: true,
          ),
        );
      final c = LocalPrivacyController(p);
      addTearDown(c.dispose);
      await c.refresh();
      c.edit(c.draft!.copyWith(roomFields: 0));
      await c.save();
      expect(p.snapshot.settings!.fleetVisibilityGroupIds, ['preserved-group']);
    },
  );
  testWidgets(
    'real page separates room and closed main fleet, preserving off choices',
    (tester) async {
      viewport(tester, const Size(1440, 1100));
      final p = MemoryPrivacy();
      final c = LocalPrivacyController(p);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
      await tester.pumpAndSettle();
      expect(find.text('主舰队'), findsOneWidget);
      expect(find.text('房间'), findsOneWidget);
      expect(find.text('当前连接尚未启用对外共享'), findsOneWidget);
      expect(p.writes, 0);
      final roomShip = find.byKey(const Key('privacy-scope-room-field-ship'));
      await tester.ensureVisible(roomShip);
      await tester.tap(roomShip);
      await tester.pumpAndSettle();
      expect(c.draft!.fleetFields & 2, 0);
      expect(c.draft!.roomFields & 2, 0);
      final fleetShip = find.byKey(
        const Key('privacy-scope-official-fleet-field-ship'),
      );
      expect(tester.widget<InkWell>(fleetShip).onTap, isNull);
      final publication = find.byKey(const Key('privacy-publication'));
      await tester.ensureVisible(publication);
      await tester.tap(publication);
      await tester.pumpAndSettle();
      expect(tester.widget<InkWell>(fleetShip).onTap, isNull);
      await tester.tap(publication);
      await tester.pumpAndSettle();
      expect(c.draft!.roomFields & 2, 0);
      await tester.tap(find.byKey(const Key('privacy-save')));
      await tester.pumpAndSettle();
      expect(p.writes, 1);
      expect(find.text('已保存到本机 · 尚未对外生效'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PRIVACY')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/privacy-page.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
  for (final size in [
    const Size(420, 850),
    const Size(760, 850),
    const Size(1440, 1000),
  ]) {
    testWidgets(
      'settings navigation protects dirty privacy at width ${size.width}',
      (tester) async {
        viewport(tester, size);
        final c = LocalPrivacyController(MemoryPrivacy());
        addTearDown(c.dispose);
        await c.refresh();
        await tester.pumpWidget(
          app(
            SettingsPage(
              initialSection: SettingsSection.syncPrivacy,
              accountAndIdentityBuilder: (_) =>
                  const Text('account destination'),
              generalDataBuilder: (_) => const Text('general destination'),
              syncPrivacyBuilder: (_) => LocalPrivacyPage(controller: c),
              notificationsBuilder: (_) =>
                  const Text('notifications destination'),
              confirmPrivacyLeave: (context) =>
                  confirmLocalPrivacyLeave(context, c),
            ),
          ),
        );
        await tester.pumpAndSettle();
        c.edit(c.draft!.copyWith(roomFields: 0));
        await tester.pumpAndSettle();
        Future<void> navigate() async {
          if (size.width < 600) {
            await tester.tap(find.byKey(const Key('settings-section-picker')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('常规与数据').last);
          } else {
            await tester.tap(
              find.byKey(const Key('settings-section-generalData')),
            );
          }
          await tester.pumpAndSettle();
        }

        await navigate();
        expect(find.byKey(const Key('privacy-leave-dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('privacy-leave-cancel')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('local-privacy-page')), findsOneWidget);
        expect(c.dirty, true);
        await navigate();
        await tester.tap(find.byKey(const Key('privacy-leave-discard')));
        await tester.pumpAndSettle();
        expect(find.text('general destination'), findsOneWidget);
        expect(c.dirty, false);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final locale in AppStrings.supportedLocales) {
    testWidgets('privacy fits narrow layout and large text in $locale', (
      tester,
    ) async {
      viewport(tester, const Size(430, 900));
      final c = LocalPrivacyController(PublishingPrivacy());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        app(LocalPrivacyPage(controller: c), locale: locale, textScale: 1.6),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('privacy-scope-room-field-server')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final key in simplifiedLocalPrivacyStrings.keys) {
        expect(AppStrings.resolve(locale).text(key), isNot(key));
      }
    });
  }
  testWidgets(
    'failed leave-save stays in editor and an old dialog cannot save a new account',
    (tester) async {
      final p = MemoryPrivacy();
      final c = LocalPrivacyController(p);
      addTearDown(c.dispose);
      await c.refresh();
      Future<bool>? result;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => result = confirmLocalPrivacyLeave(context, c),
              child: const Text('leave'),
            ),
          ),
        ),
      );
      c.edit(c.draft!.copyWith(roomFields: 0));
      p.failure = const BridgeClientException('privacy_local.write_failed');
      await tester.pumpAndSettle();
      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy-leave-save')));
      await tester.pumpAndSettle();
      expect(await result, false);
      expect(c.dirty, true);
      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      p.events.add(null);
      await tester.pump();
      p.failure = null;
      await c.refresh();
      final writes = p.writes;
      await tester.tap(find.byKey(const Key('privacy-leave-save')));
      await tester.pumpAndSettle();
      expect(await result, false);
      expect(p.writes, writes);
    },
  );
}

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget app(
  Widget child, {
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1,
}) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: RepaintBoundary(
        key: const Key('capture'),
        child: Scaffold(body: child),
      ),
    ),
  );
}

class PrivacyHost implements NativeHostLease {
  PrivacyHost() {
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 7)
      ..acceptHostCapabilities(['privacy.local']);
    subscription = pair.host.incoming.listen((request) {
      requests.add(request);
      if (request.messageType != 'request') return;
      final allowed = const {
        'account.getCurrent',
        'privacy.localRead',
        'privacy.localSave',
      }.contains(request.name);
      if (request.name == 'privacy.localSave') {
        settings = request.payload['settings'];
        operation = request.payload['operationId'];
        revision++;
      }
      unawaited(
        pair.host.send(
          BridgeEnvelope.fromJson({
            'protocolVersion': 1,
            'messageType': 'response',
            'name': request.name,
            'correlationId': request.correlationId,
            'sessionGeneration': 7,
            'status': allowed ? 'ok' : 'error',
            if (!allowed)
              'error': {
                'code': 'host.capability_missing',
                'message': 'fixture',
                'retryable': false,
              },
            'accountContext': {
              'environment': 'test',
              'authority': 'fixture',
              'subject': 'privacy-fixture',
            },
            'payload': request.name == 'account.getCurrent'
                ? {'schemaVersion': 1, 'state': 'signedIn'}
                : {
                    'schemaVersion': 1,
                    'revision': revision,
                    'settings': settings,
                    'operationId': operation,
                    'savedAt': revision == 0 ? null : '2026-01-01T00:00:00Z',
                    'publicationAvailable': false,
                  },
          }),
        ),
      );
    });
  }
  final InMemoryBridgePair pair = InMemoryBridgeConnection.createPair();
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  Object? settings, operation;
  int revision = 0;
  @override
  late final BridgeClientSession session;
  @override
  Future<NativeHostTermination> get terminated =>
      Completer<NativeHostTermination>().future;
  @override
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}

class MemoryPrivacy implements LocalPrivacyPort {
  final events = StreamController<void>.broadcast();
  LocalPrivacySnapshot snapshot = const LocalPrivacySnapshot(revision: 0);
  Object? failure;
  int writes = 0;
  Completer<LocalPrivacySnapshot>? pendingSave;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<LocalPrivacySnapshot> read() async => snapshot;
  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) async {
    writes++;
    if (failure != null) throw failure!;
    if (pendingSave != null) return pendingSave!.future;
    return snapshot = LocalPrivacySnapshot(
      revision: snapshot.revision + 1,
      savedAt: DateTime.now(),
      settings: settings,
    );
  }

  @override
  Future<void> close() => events.close();
}

class ConfidencePrivacy extends MemoryPrivacy
    implements LocationConfidencePrivacyPort {
  @override
  bool get locationConfidenceSupported => true;
}

class PublishingPrivacy extends MemoryPrivacy
    implements PrivacyPublicationPort {
  final actions = <String>[];
  @override
  bool get publicationSupported => true;
  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async {
    actions.add(action);
    return PrivacyPublicationView(switch (action) {
      'apply' => 'applied',
      'stop' => 'withdrawalPending',
      _ => 'inactive',
    }, revision: revision);
  }
}
