import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_wheel_gate.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_screen_switch.dart';
import 'package:starbridge_flutter/features/common/organization_workspace_frame.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_overview_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/shared/remote_image.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';

import '../../support/remote_image_fixture.dart';
import '../friends/social_layout_test.dart' show loadFonts, size;
import '../../_support/development_fixture_path.dart';

const _base = 'https://holo.example.test';
final _capture = Platform.environment['STARBRIDGE_CAPTURE_HOLO'] == '1';

/// Serves fixture images by file name.
class _Client implements HttpClient {
  _Client(this.images);
  final Map<String, List<int>> images;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async =>
      _Request(images[uri.pathSegments.last]);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.bytes);
  final List<int>? bytes;
  @override
  Future<HttpClientResponse> close() async => _Response(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes);
  final List<int>? bytes;
  @override
  final HttpHeaders headers = _Headers();
  @override
  int get statusCode => bytes == null ? 404 : 200;
  @override
  int get contentLength => bytes?.length ?? 0;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes ?? const <int>[]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers extends Fake implements HttpHeaders {
  @override
  List<String>? operator [](String name) => null;
  @override
  String? value(String name) => null;
}

OfficialFleetSnapshot _fleet({required bool banner}) =>
    OfficialFleetSnapshot.available(
      fleet: OfficialFleetSummary(
        sourceRef: 'officialFleet:7',
        sid: banner ? 'TEST' : 'DMNPZ',
        name: banner ? 'Test Squadron' : 'Domino Pizza',
        officialRankName: 'Master',
        officialRankValue: 5,
        // DMNPZ mirrors production: no membership logo, only the public one.
        logoUrl: banner ? '$_base/logo.png' : null,
        profile: OfficialFleetProfileDetails(
          bannerUrl: banner ? '$_base/banner.png' : null,
          backgroundUrl: banner ? '$_base/background.jpg' : null,
          logoUrl: banner ? null : '$_base/logo.png',
          memberCount: banner ? 31640 : 1,
        ),
      ),
      freshness: OfficialFleetFreshness.live,
      resourceVersion: 3,
      observedAtUtc: DateTime.utc(2026, 10, 21, 12),
      profileReadState: OfficialFleetProfileReadState.available,
      profileObservedAtUtc: DateTime.utc(2026, 10, 21, 12),
    );

Future<List<int>> _png(Color top, Color bottom, int width, int height) async {
  final recorder = ui.PictureRecorder();
  final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  Canvas(recorder).drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [top, bottom],
      ).createShader(rect),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<Map<String, List<int>>> _images() async {
  // Captures use the preview assets; tests use generated images.
  final previews = developmentFixturePath('StarBridge-DesignPreviews/MainFleetBanner');
  if (_capture && File('$previews/assets/banner-custom.png').existsSync()) {
    return {
      'banner.png': File('$previews/assets/banner-custom.png')
          .readAsBytesSync(),
      'logo.png': File('$previews/assets/logo-custom.png').readAsBytesSync(),
      // Stand-in for an RSI page background (a different artwork).
      'background.jpg': File('$previews/assets/banner-default.jpg')
          .readAsBytesSync(),
    };
  }
  return {
    'banner.png': await _png(
      const Color(0xFF3A2A1C),
      const Color(0xFFE08A3A),
      900,
      300,
    ),
    'logo.png': await _png(
      const Color(0xFF1C6FB0),
      const Color(0xFF7FD0FF),
      64,
      64,
    ),
    'background.jpg': await _png(
      const Color(0xFF203040),
      const Color(0xFF506070),
      960,
      540,
    ),
  };
}

Future<OfficialFleetModule> _pump(
  WidgetTester tester, {
  required Size window,
  bool banner = true,
  bool light = false,
  bool reduceMotion = false,
  bool settle = true,
  double textScale = 1,
  Locale locale = const Locale('zh', 'CN'),
  OfficialFleetModule? reuse,
  List<OfficialFleetMember>? members,
}) async {
  size(tester, window);
  final images = <String, List<int>>{};
  final loader = RemoteImageLoader(
    mode: ImageMode(),
    createClient: () => _Client(images),
  );
  addTearDown(loader.dispose);
  await tester.runAsync(() async {
    images.addAll(await _images());
    for (final name in images.keys) {
      await loader.load(
        '$_base/$name',
        kind: RemoteImageResourceKind.organization,
      );
    }
  });
  final module =
      reuse ??
      createOfficialFleetModule(
        InMemoryOfficialFleetAdapter(initial: _fleet(banner: banner)),
        banner
            ? InMemoryOfficialFleetOverviewAdapter.forReview()
            : UnavailableOfficialFleetOverviewAdapter(),
        members == null
            ? InMemoryOfficialFleetMembersAdapter.forReview()
            : InMemoryOfficialFleetMembersAdapter(members),
        UnavailableOfficialFleetShipsAdapter(),
      );
  if (reuse == null) {
    addTearDown(module.dispose);
    await module.initialize();
  }
  final theme = buildStarBridgeTheme(
    FutureRestraintStyle.resolve(
      light ? AppearanceMode.light : AppearanceMode.dark,
    ),
    locale,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where(
            (e) => e is! StarBridgeInteractionTheme,
          ),
          StarBridgeInteractionTheme(reduceMotion: reduceMotion),
        ],
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: window,
          textScaler: TextScaler.linear(textScale),
        ),
        child: RepaintBoundary(
          key: const Key('holo-capture'),
          child: RemoteImageScope(
            loader: loader,
            child: Scaffold(body: OfficialFleetPage(module: module)),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return module;
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = tester.renderObject(
      find.byKey(const Key('holo-capture')),
    ) as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/reviews').create(recursive: true);
    await File('build/reviews/holo-$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!_capture) return;
    await loadFonts();
    await (FontLoader('Source Code Pro')
          ..addFont(rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf')))
        .load();
  });

  testWidgets('wide header shows the uncovered 3:1 banner and the old data', (
    tester,
  ) async {
    // 1280x860 window minus the 196 navigation rail and the 56 title bar.
    await _pump(tester, window: const Size(1084, 804));
    final banner = tester.getRect(
      find.byKey(const Key('official-fleet-holo-banner')),
    );
    expect(banner.left, 0, reason: 'The banner is full-bleed.');
    expect(banner.top, 0);
    expect(banner.width, 1084);
    expect(banner.height, closeTo(1084 / 3, .5));
    expect(find.text('Test Squadron'), findsOneWidget);
    expect(find.text('我的官网职位 · Master · 5★'), findsOneWidget);
    expect(find.text('1286'), findsOneWidget);
    // Complete roster rows replace the old overview's stale runtime counts.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // The header shows the announcement; a tall broadcast tile may too.
    expect(
      find.descendant(
        of: find.byKey(const Key('official-fleet-context-header')),
        matching: find.text('本周联合训练安排'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('official-fleet-header-collapse')),
      findsOneWidget,
    );
    // Top screen: the section rail, no section content yet.
    expect(
      find.byKey(const Key('official-fleet-section-rail')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('official-fleet-members')), findsNothing);
    expect(tester.takeException(), isNull);
    await _shot(tester, 'dark-1084');
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('official-fleet-members')), findsOneWidget);
    expect(
      find.byKey(const Key('official-fleet-header-compact')),
      findsOneWidget,
    );
  });

  testWidgets('collapse keeps the data and returning does not replay entry', (
    tester,
  ) async {
    await _pump(tester, window: const Size(1084, 804));
    await tester.tap(find.byKey(const Key('official-fleet-header-collapse')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('official-fleet-header-compact')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('official-fleet-holo-banner')), findsNothing);
    expect(find.text('我的官网职位 · Master · 5★'), findsOneWidget);
    await _shot(tester, 'dark-1084-collapsed');
    await tester.tap(find.byKey(const Key('official-fleet-header-expand')));
    await tester.pump();
    final slab = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Test Squadron'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(slab.opacity, 1, reason: 'The entry animation plays only once.');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('short windows keep the top screen and its rail reachable', (
    tester,
  ) async {
    await _pump(tester, window: const Size(1084, 600));
    expect(find.byKey(const Key('official-fleet-holo-banner')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('official-fleet-header-compact')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('official-fleet-members')), findsOneWidget);
    await tester.tap(find.byKey(const Key('official-fleet-header-expand')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('official-fleet-holo-banner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wheel scrolls the header away and back without a button', (
    tester,
  ) async {
    // One member: the list itself cannot scroll, the header still can.
    await _pump(tester, window: const Size(1084, 804), banner: false);
    final banner = find.byKey(const Key('official-fleet-holo-banner'));
    // No overview source yet: no "unavailable" line under the name.
    expect(
      find.descendant(
        of: find.byKey(const Key('official-fleet-context-header')),
        matching: find.text('暂不可用'),
      ),
      findsNothing,
    );
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(banner)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    expect(
      find.byKey(const Key('official-fleet-header-compact')),
      findsOneWidget,
    );
    // Switching tabs keeps it slim for the rest of this visit.
    await tester.tap(find.byKey(const Key('official-fleet-tab-ships')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    final list = tester.getCenter(
      find.byKey(const Key('official-fleet-members')),
    );
    await tester.sendEventToBinding(mouse.hover(list));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
    await tester.pumpAndSettle();
    expect(banner, findsNothing, reason: 'One notch is not enough');
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
    await tester.pumpAndSettle();
    expect(banner, findsOneWidget, reason: 'Up at the top brings it back');
    // A touchpad swipe works the same way.
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(banner)));
    final pad = TestPointer(2, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pad.panZoomStart(tester.getCenter(banner)));
    await tester.sendEventToBinding(
      pad.panZoomUpdate(tester.getCenter(banner), pan: const Offset(0, -40)),
    );
    await tester.sendEventToBinding(pad.panZoomEnd());
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a membership logo the public RSI logo is shown', (
    tester,
  ) async {
    await _pump(tester, window: const Size(1084, 804), banner: false);
    final emblem = find.descendant(
      of: find.byKey(const Key('official-fleet-logo')),
      matching: find.byType(RemoteImage),
    );
    expect(emblem, findsOneWidget);
    expect(tester.widget<RemoteImage>(emblem).source, '$_base/logo.png');
    expect(find.text('DM'), findsNothing);
  });

  testWidgets('reduced motion shows the final state on the first frame', (
    tester,
  ) async {
    await _pump(
      tester,
      window: const Size(1084, 804),
      reduceMotion: true,
      settle: false,
    );
    await tester.pump();
    for (final opacity in tester.widgetList<Opacity>(
      find.descendant(
        of: find.byKey(const Key('official-fleet-context-header')),
        matching: find.byType(Opacity),
      ),
    )) {
      expect(opacity.opacity, anyOf(1, .62, .6), reason: 'no entry fades');
    }
    await tester.pumpAndSettle();
  });

  for (final fixture in [
    (const Size(1084, 804), true, false, 1.0, 'light-1084'),
    // 1280x800 window: the header still fits above a usable member list.
    (const Size(1084, 744), true, false, 1.0, 'dark-1084x744'),
    (const Size(1084, 804), false, false, 1.0, 'dark-1084-nobanner'),
    (const Size(704, 844), true, false, 1.0, 'dark-704'),
    (const Size(760, 720), true, false, 1.5, 'dark-760-x1.5'),
    (const Size(480, 720), true, true, 1.5, 'light-480-x1.5'),
    // 2560x1440 fullscreen at 125% and 100% scaling, minus navigation.
    (const Size(1852, 1040), true, false, 1.0, 'dark-2k-125'),
    (const Size(2364, 1336), true, false, 1.0, 'dark-2k-100'),
  ]) {
    testWidgets('header lays out at ${fixture.$5}', (tester) async {
      await _pump(
        tester,
        window: fixture.$1,
        banner: fixture.$2,
        light: fixture.$5.startsWith('light'),
        textScale: fixture.$4,
      );
      // Top screen: cramped windows clip the header, never overflow.
      expect(
        find.byKey(const Key('official-fleet-context-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('official-fleet-section-rail')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _shot(tester, fixture.$5);
      await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('official-fleet-members')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shot(tester, '${fixture.$5}-detail');
    });
  }

  testWidgets('the organization background sits dimmed behind the page', (
    tester,
  ) async {
    await _pump(tester, window: const Size(1084, 804));
    expect(find.byKey(const Key('official-fleet-backdrop')), findsOneWidget);
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();
    // Lower screen: the work surface sits over the art with thinner glass.
    expect(
      tester
          .widget<OrganizationWorkspaceBackdrop>(
            find.ancestor(
              of: find.byType(OrganizationWorkspaceSurface),
              matching: find.byType(OrganizationWorkspaceBackdrop),
            ),
          )
          .active,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    // Without a background the page keeps its plain ground.
    await _pump(tester, window: const Size(1084, 804), banner: false);
    expect(find.byKey(const Key('official-fleet-backdrop')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entering a section shrinks the deck instead of cutting', (
    tester,
  ) async {
    await _pump(tester, window: const Size(2364, 1336));
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pump();
    await tester.pump(OfficialFleetScreenSwitch.duration ~/ 2);
    // Mid-switch both screens are on stage under the shrinking deck.
    expect(
      find.byKey(const ValueKey('official-fleet-upper-screen')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('official-fleet-lower-screen')),
      findsOneWidget,
    );
    // User report 2026-10-27: no blur inside the fading upper screen.
    expect(find.byType(BackdropFilter), findsNothing);
    await _shot(tester, 'switch-mid');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('official-fleet-upper-screen')),
      findsNothing,
    );
    expect(find.byKey(const Key('official-fleet-members')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _shot(tester, 'switch-end');
  });

  // Performance (user 10-24: "所有操作都卡顿，动效"): on Impeller a filter or
  // offscreen layer is recomputed on every frame anything moves. At rest the
  // shell keeps only the title glass blur, and at most the mirror fade masks.
  testWidgets('the settled title glass keeps its frosted blur', (tester) async {
    // User report 2026-10-25 ("左侧怎么成纯透明了", then the earlier look as
    // the reference): only the blur hides the banner and its mirror.
    await _pump(tester, window: const Size(1084, 804));
    final glass = tester.widgetList<BackdropFilter>(
      find.byType(BackdropFilter),
    );
    expect(glass, hasLength(1));
    expect(glass.single.filter, ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8));
  });

  testWidgets('settled screens keep only the title glass blur', (tester) async {
    Map<String, int> count() {
      final layers = tester.layers;
      return {
        'backdrop': layers.whereType<BackdropFilterLayer>().length,
        'imageFilter': layers.whereType<ImageFilterLayer>().length,
        'shaderMask': layers.whereType<ShaderMaskLayer>().length,
      };
    }

    await _pump(tester, window: const Size(2364, 1336));
    final upper = count();
    expect(upper['backdrop'], 1, reason: 'upper: $upper');
    expect(upper['imageFilter'], 0, reason: 'upper: $upper');
    expect(upper['shaderMask'], lessThanOrEqualTo(1), reason: 'upper: $upper');
    expect(
      find.byType(RepaintBoundary),
      findsWidgets,
      reason: 'static decorations are isolated from moving content',
    );
    await tester.tap(find.byKey(const Key('official-fleet-tab-members')));
    await tester.pumpAndSettle();
    final lower = count();
    expect(lower['backdrop'], 0, reason: 'lower: $lower');
    expect(lower['imageFilter'], 0, reason: 'lower: $lower');
    expect(lower['shaderMask'], lessThanOrEqualTo(1), reason: 'lower: $lower');
  });

  testWidgets('only a screen tall enough grows the rail into preview tiles', (
    tester,
  ) async {
    // 2560x1440 at 100%: the whole banner and room to spare below it.
    await _pump(tester, window: const Size(2364, 1336));
    final rail = find.byKey(const Key('official-fleet-section-rail'));
    expect(tester.getSize(rail).height, greaterThan(180));
    expect(
      find.byKey(const Key('official-fleet-tile-members')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('official-fleet-tile-broadcast')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    // A 1280x800 window keeps the plain 96px rail without previews.
    await _pump(tester, window: const Size(1084, 744));
    expect(tester.getSize(rail).height, 96);
    expect(find.byKey(const Key('official-fleet-tile-members')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ships tile only says none for a real zero', (tester) async {
    const none = '还没有成员把舰船共享给主舰队';
    const browse = '进入浏览全部共享舰船';
    const window = Size(2364, 1336);
    // Real builds have no overview metrics: the count is unknown.
    await _pump(tester, window: window, banner: false);
    expect(find.text(browse), findsOneWidget);
    expect(find.text(none), findsNothing);
    // Some shared ships.
    await _pump(tester, window: window);
    expect(find.text(browse), findsOneWidget);
    expect(find.text(none), findsNothing);
    // A known zero.
    final zero = createOfficialFleetModule(
      InMemoryOfficialFleetAdapter(initial: _fleet(banner: true)),
      InMemoryOfficialFleetOverviewAdapter(
        snapshot: OfficialFleetOverviewSnapshot.available(
          announcement: null,
          metrics: const OfficialFleetOverviewMetrics(
            officialMemberCount: 2,
            visibleOnlineCount: 1,
            visibleInGameCount: 0,
            sharedRequestableShipCount: 0,
          ),
          tasks: const [],
          observedAtUtc: DateTime.utc(2026, 9, 1, 12, 30),
        ),
      ),
      InMemoryOfficialFleetMembersAdapter.forReview(),
      UnavailableOfficialFleetShipsAdapter(),
    );
    addTearDown(zero.dispose);
    await zero.initialize();
    await _pump(tester, window: window, reuse: zero);
    expect(find.text(none), findsOneWidget);
    expect(find.text(browse), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large windows show the whole 3:1 banner, small ones crop', (
    tester,
  ) async {
    double banner() => tester
        .getSize(find.byKey(const Key('official-fleet-holo-banner')))
        .height;
    await _pump(tester, window: const Size(1852, 1040));
    expect(banner(), closeTo(1852 / 3, .5), reason: '2K: the whole RSI banner');
    await _pump(tester, window: const Size(1084, 744));
    expect(
      banner(),
      lessThan(1084 / 3),
      reason: 'small window keeps its work surface',
    );
  });

  testWidgets(
    'the first visit of the day gets the full entry, later ones the quick one',
    (tester) async {
      double slab() => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.text('Test Squadron'),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      final module = await _pump(
        tester,
        window: const Size(1084, 804),
        settle: false,
      );
      await tester.pump(); // the entry ticker starts on the first frame
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        slab(),
        lessThan(1),
        reason: 'Full entry: the slab is still arriving at 0.6 s',
      );
      await tester.pump(const Duration(milliseconds: 1850));
      expect(slab(), 1, reason: 'Full entry has settled just after 2.4 s');
      await tester.pumpWidget(const SizedBox());
      // Same client run, same day: the module remembers the first visit.
      await _pump(
        tester,
        window: const Size(1084, 804),
        settle: false,
        reuse: module,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(slab(), lessThan(1), reason: 'Quick entry still moves');
      await tester.pump(const Duration(milliseconds: 320));
      expect(slab(), 1, reason: 'Quick entry has settled just after 0.42 s');
      expect(
        find.byKey(const Key('official-fleet-holo-banner')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('entry animation frames', (tester) async {
    if (!_capture) return;
    OfficialFleetModule? module;
    Future<void> frames(String name, List<int> times) async {
      module = await _pump(
        tester,
        window: const Size(1084, 804),
        settle: false,
        reuse: module,
      );
      var elapsed = 0;
      for (final at in times) {
        await tester.pump(Duration(milliseconds: at - elapsed));
        elapsed = at;
        await _shot(tester, '$name-${at.toString().padLeft(4, '0')}');
      }
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }

    await frames('full', [for (var at = 0; at <= 2500; at += 16) at]);
    await frames('quick', [for (var at = 0; at <= 520; at += 16) at]);
  });

  // 2026-10-24: blank parts of a screen hit-test through to the backdrop. The
  // switch's wheel listener must still receive the wheel there.
  group('wheel on blank parts of a screen', () {
    testWidgets('a wheel down on blank upper screen goes to the lower one', (
      tester,
    ) async {
      await _pump(tester, window: const Size(1084, 804));
      final at = blankPoint(
        tester,
        find.byKey(const ValueKey('official-fleet-upper-screen')),
      );
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(at));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('official-fleet-header-compact')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('up in the list scrolls it; only the top returns upward', (
      tester,
    ) async {
      await _pump(
        tester,
        window: const Size(1084, 804),
        members: [for (var i = 0; i < 40; i++) _crew('Pilot${i + 10}')],
      );
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.hover(
          blankPoint(
            tester,
            find.byKey(const ValueKey('official-fleet-upper-screen')),
          ),
        ),
      );
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pumpAndSettle();
      final list = find.byKey(const Key('official-fleet-members'));
      final compact = find.byKey(const Key('official-fleet-header-compact'));
      expect(compact, findsOneWidget);
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find.ancestor(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      final middle = Offset(
        tester.getCenter(list).dx,
        tester.getTopLeft(compact).dy + 300,
      );
      await tester.sendEventToBinding(mouse.hover(middle));
      for (var i = 0; i < 3; i++) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
        await tester.pumpAndSettle();
      }
      expect(position().pixels, greaterThan(200));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
      await tester.pumpAndSettle();
      expect(compact, findsOneWidget, reason: 'Not at the top: list only');
      expect(position().pixels, greaterThan(0));
      var ups = 0;
      var wheelTime = Duration.zero;
      OfficialFleetWheelGate.debugNow = () => wheelTime;
      addTearDown(() => OfficialFleetWheelGate.debugNow = null);
      while (compact.evaluate().isNotEmpty && ups < 20) {
        wheelTime += const Duration(milliseconds: 500);
        expect(position().pixels, greaterThanOrEqualTo(0));
        final atTop = position().pixels == 0;
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
        await tester.pumpAndSettle();
        ups++;
        if (compact.evaluate().isEmpty) {
          expect(atTop, isTrue, reason: 'Switched before the list top');
        }
      }
      expect(compact, findsNothing, reason: 'Up at the top returns');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('upper screen buttons still take clicks', (tester) async {
      await _pump(tester, window: const Size(1084, 804));
      await tester.tap(find.byKey(const Key('official-fleet-open-details')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('official-fleet-details-dialog')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// A point on [screen] that no widget inside it claims.
Offset blankPoint(WidgetTester tester, Finder screen) {
  final box = tester.renderObject(screen);
  final rect = tester.getRect(screen);
  for (var y = rect.top + 8; y < rect.bottom - 8; y += 10) {
    for (var x = rect.left + 8; x < rect.right - 8; x += 10) {
      final result = HitTestResult();
      tester.binding.hitTestInView(result, Offset(x, y), tester.view.viewId);
      if (!result.path.any((entry) => identical(entry.target, box))) {
        return Offset(x, y);
      }
    }
  }
  fail('Every point of the screen is claimed by a widget.');
}

OfficialFleetMember _crew(String name) => OfficialFleetMember(
  memberRef: name.padRight(64, '0').substring(0, 64),
  callsign: name,
  gameId: name,
  officialRankName: null,
  officialRankValue: null,
  presence: OfficialFleetMemberPresence.online,
  server: const OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
  ship: const OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
  location: const OfficialFleetMemberField(
    OfficialFleetMemberFieldState.notShared,
  ),
  starBridgeConnected: true,
  identityState: OfficialFleetMemberIdentityState.starBridge,
  sharingPaused: false,
);
