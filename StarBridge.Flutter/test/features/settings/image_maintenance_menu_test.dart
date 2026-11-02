import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/product_features.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

import '../communities/bridge_communities_test.dart' show CommunityHarness;
import '../../app/menu_overlay/menu_directory_logos_test.dart'
    show MembersOnlyPort;

class MenuMaintenanceHost extends CommunityHarness implements NativeHostLease {
  MenuMaintenanceHost() : super(capabilities: ['diagnostics.clearImageCache']);
  final _terminated = Completer<NativeHostTermination>();
  @override
  Future<NativeHostTermination> get terminated => _terminated.future;
  bool _closed = false;
  Completer<void>? clearGate;
  bool failClear = false;
  @override
  Future<void> reply(BridgeEnvelope request) async {
    final clear = request.name == 'diagnostics.clearImageCache';
    if (clear) await clearGate?.future;
    final failed = clear ? failClear : request.name != 'account.getCurrent';
    return connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        status: failed ? 'error' : 'ok',
        error: failed
            ? const BridgeErrorBody(
                code: 'diagnostics.unavailable',
                message: 'Unavailable',
                retryable: false,
              )
            : null,
        payload: request.name == 'account.getCurrent'
            ? {'schemaVersion': 1, 'state': 'signedOut'}
            : {'schemaVersion': 1, 'count': 0},
      ),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starbridge/menu-primary');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  test(
    'production composition maintenance retires an existing menu organization logo without creating or showing a window',
    () async {
      final host = MenuMaintenanceHost();
      final prefs = InMemoryAppPreferences();
      final app = AppComposition.forConnectedProduct(
        nativeHost: host,
        preferences: prefs,
        menuLifetime: MenuWindowLifetime(),
        windowChrome: InMemoryWindowChrome(),
      );
      final menu =
          app.overlaySettings.menuPreview! as MethodChannelMenuPreviewWindow;
      final port = MembersOnlyPort();
      MenuOrganizationsSession? lease;
      final loaded = Completer<void>();
      final nativeCalls = <MethodCall>[];
      final preview = Completer<int>();
      menu.features['organizations'] = (publish) =>
          lease = MenuOrganizationsSession(port, (view) {
            publish(view);
            if ((view['organization'] as Map?)?['logo'] != null &&
                !loaded.isCompleted) {
              loaded.complete();
            }
          });
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add(call);
        if (call.method == 'imageMaintenance') {
          return {
            'schemaVersion': 1,
            'resourceEpoch': (call.arguments as Map)['resourceEpoch'],
            'enginePresent': true,
          };
        }
        if (call.method == 'preview') {
          preview.complete((call.arguments as Map)['request'] as int);
        }
        return call.method == 'preview' ? 9 : null;
      });
      Future<void> event(String method, Map<String, Object?> value) =>
          messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, value),
            ),
            (_) {},
          );
      try {
        final opening = menu.openLive(
          contextLabel: 'Fixture',
          returnLabel: 'Back',
          settingsLabel: 'Settings',
        );
        await event('state', {
          'request': await preview.future,
          'state': 'visible',
        });
        expect(await opening, isTrue);
        await event('featureVisible', {
          'opening': 9,
          'tool': 'organizations',
          'visible': true,
        });
        await loaded.future.timeout(const Duration(seconds: 4));
        final before = lease!.currentView;
        final account = lease!.accountEpoch;
        final scope = before['scope'];
        nativeCalls.clear();
        expect(await app.imageMaintenance.clear(), 0);
        final after = lease!.currentView;
        expect((after['organization'] as Map)['logo'] == null, isTrue);
        expect(
          (after['organization'] as Map)['title'],
          (before['organization'] as Map)['title'],
        );
        expect(after['scope'], scope);
        expect(lease!.accountEpoch, account);
        expect(
          nativeCalls.any(
            (call) =>
                const ['preview', 'show', 'prewarm'].contains(call.method),
          ),
          isFalse,
        );
      } finally {
        app.dispose();
        await Future<void>.delayed(Duration.zero);
        await host.close();
        prefs.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
    skip: !menuOverlayEnabled
        ? 'Requires actual menu-enabled product profile'
        : false,
  );
}
