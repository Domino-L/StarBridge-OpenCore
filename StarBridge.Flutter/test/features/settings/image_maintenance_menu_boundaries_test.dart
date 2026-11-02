import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/product_features.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import 'image_maintenance_menu_test.dart' show MenuMaintenanceHost;
import '../../app/menu_overlay/menu_directory_logos_test.dart'
    show MembersOnlyPort;

class HeldDirectoryPort extends MembersOnlyPort {
  final arrived = Completer<void>();
  Completer<void>? gate;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    if (!arrived.isCompleted) arrived.complete();
    await gate?.future;
    return super.read(view: view, query: query, after: after, filters: filters);
  }
}

class MenuMaintenanceScene {
  MenuMaintenanceScene([MembersOnlyPort? source])
    : port = source ?? MembersOnlyPort() {
    app = AppComposition.forConnectedProduct(
      nativeHost: host,
      preferences: prefs,
      menuLifetime: MenuWindowLifetime(),
      windowChrome: InMemoryWindowChrome(),
    );
    menu = app.overlaySettings.menuPreview! as MethodChannelMenuPreviewWindow;
    menu.features['organizations'] = (publish) {
      created++;
      return lease = MenuOrganizationsSession(port, (view) {
        publish(view);
      });
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'imageMaintenance') {
        if (retirementReply != null) return retirementReply!(call);
        return {
          'schemaVersion': 1,
          'resourceEpoch': (call.arguments as Map)['resourceEpoch'],
          'enginePresent': true,
        };
      }
      if (call.method == 'featureView') {
        events.add(
          Map<String, Object?>.from(
            jsonDecode((call.arguments as Map)['payload'] as String) as Map,
          ),
        );
      }
      if (call.method == 'preview' && !preview.isCompleted) {
        preview.complete((call.arguments as Map)['request'] as int);
      }
      return call.method == 'preview' ? 9 : null;
    });
  }
  static const channel = MethodChannel('starbridge/menu-primary');
  static final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final host = MenuMaintenanceHost();
  final prefs = InMemoryAppPreferences();
  final MembersOnlyPort port;
  late final AppComposition app;
  late final MethodChannelMenuPreviewWindow menu;
  MenuOrganizationsSession? lease;
  final calls = <MethodCall>[];
  final events = StreamController<Map<String, Object?>>.broadcast();
  final preview = Completer<int>();
  int created = 0;
  Future<Object?> Function(MethodCall)? retirementReply;
  Future<void> event(String method, Map<String, Object?> data) =>
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, data)),
        (_) {},
      );
  Future<void> open() async {
    final opening = menu.openLive(
      contextLabel: 'Fixture',
      returnLabel: 'Back',
      settingsLabel: 'Settings',
    );
    await event('state', {'request': await preview.future, 'state': 'visible'});
    if (!await opening) throw StateError('Mock opening failed');
  }

  Future<void> show(bool value) => event('featureVisible', {
    'opening': 9,
    'tool': 'organizations',
    'visible': value,
  });
  Future<Map<String, Object?>> waitFor(
    bool Function(Map<String, Object?>) predicate,
  ) {
    final current = lease?.currentView;
    if (current != null && predicate(current)) return Future.value(current);
    return events.stream
        .firstWhere(predicate)
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            throw StateError(
              'Menu wait failed: state=${lease?.currentView['state']}, logo=${hasLogo(lease?.currentView ?? {})}, directoryReads=${port.source.directoryReads}, workspaceReads=${port.source.workspaceReads}',
            );
          },
        );
  }

  static bool hasLogo(Map<String, Object?> view) =>
      (view['organization'] as Map?)?['logo'] != null;
  bool get windowTouched => calls.any(
    (call) => const ['preview', 'show', 'prewarm'].contains(call.method),
  );
  Future<void> close() async {
    if (host.clearGate case final gate? when !gate.isCompleted) gate.complete();
    if (port case final HeldDirectoryPort source) {
      if (source.gate case final gate? when !gate.isCompleted) gate.complete();
    }
    app.dispose();
    await Future<void>.delayed(Duration.zero);
    if (lease == null) await port.close();
    await host.close();
    prefs.dispose();
    await events.close();
    messenger.setMockMethodCallHandler(channel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(
    'real menu-enabled composition image maintenance',
    () {
      test(
        'uncreated menu sessions stay uncreated with no window request',
        () async {
          final scene = MenuMaintenanceScene();
          try {
            expect(await scene.app.imageMaintenance.clear(), 0);
            expect(scene.created, 0);
            expect(scene.windowTouched, isFalse);
          } finally {
            await scene.close();
          }
        },
      );
      test('hidden retained session clears all organization chrome without business reads or grants reset', () async {
        final scene = MenuMaintenanceScene();
        try {
          await scene.open();
          await scene.show(true);
          await scene.waitFor(MenuMaintenanceScene.hasLogo);
          await scene.show(false);
          final before = scene.lease!.currentView;
          final reads =
              scene.port.source.directoryReads +
              scene.port.source.workspaceReads;
          scene.calls.clear();
          await scene.app.imageMaintenance.clear();
          final after = scene.lease!.currentView;
          expect(MenuMaintenanceScene.hasLogo(after), isFalse);
          expect(
            (after['organization'] as Map)['navigation'],
            everyElement(containsPair('avatar', null)),
          );
          expect(after['scope'], before['scope']);
          expect(after['state'], before['state']);
          expect(scene.lease!.visible, isFalse);
          expect(
            scene.port.source.directoryReads + scene.port.source.workspaceReads,
            reads,
          );
          expect(scene.windowTouched, isFalse);
          expect(
            scene.calls.where((call) => call.method == 'featureView'),
            isEmpty,
            reason: 'Primary hidden state is covered here; independent renderer memory remains a separate acceptance item.',
          );
        } finally {
          await scene.close();
        }
      });
      for (final failed in [false, true]) {
        test(
          'new session inherits pause and resumes explicitly after Native ${failed ? 'failure' : 'success'}',
          () async {
            final scene = MenuMaintenanceScene();
            try {
              await scene.open();
              scene.host.clearGate = Completer<void>();
              scene.host.failClear = failed;
              scene.calls.clear();
              Object? error;
              final clearing = scene.app.imageMaintenance.clear().then<int?>(
                (value) => value,
                onError: (Object e) {
                  error = e;
                  return null;
                },
              );
              await scene.show(true);
              await scene.waitFor(
                (view) =>
                    view['state'] == 'ready' && view['readFeedback'] == null,
              );
              expect(scene.created, 1);
              expect(
                MenuMaintenanceScene.hasLogo(scene.lease!.currentView),
                isFalse,
              );
              expect(scene.windowTouched, isFalse);
              scene.host.clearGate!.complete();
              await clearing;
              expect(error != null, failed);
              expect(
                scene.host.requests.where(
                  (r) => r.name == 'diagnostics.clearImageCache',
                ),
                hasLength(1),
              );
              await scene.lease!.refresh(silent: true);
              await scene.waitFor(MenuMaintenanceScene.hasLogo);
            } finally {
              await scene.close();
            }
          },
        );
      }
      test(
        'old parent directory metadata cannot refill logo after maintenance',
        () async {
          final port = HeldDirectoryPort()..gate = Completer<void>();
          final scene = MenuMaintenanceScene(port);
          try {
            await scene.open();
            await scene.show(true);
            await port.arrived.future;
            await scene.app.imageMaintenance.clear();
            port.gate!.complete();
            await scene.waitFor(
              (view) =>
                  view['state'] == 'ready' && view['readFeedback'] == null,
            );
            expect(
              MenuMaintenanceScene.hasLogo(scene.lease!.currentView),
              isFalse,
            );
            expect(
              (scene.lease!.currentView['organization'] as Map)['navigation'],
              everyElement(containsPair('avatar', null)),
            );
            port.gate = null;
            await scene.lease!.refresh(silent: true);
            await scene.waitFor(MenuMaintenanceScene.hasLogo);
          } finally {
            await scene.close();
          }
        },
      );
    },
    skip: !menuOverlayEnabled
        ? 'Requires actual menu-enabled product profile'
        : false,
  );
}
