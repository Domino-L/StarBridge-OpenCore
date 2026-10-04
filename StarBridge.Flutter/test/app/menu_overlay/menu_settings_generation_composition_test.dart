import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/composition/overlay_settings_composition.dart';
import 'package:starbridge_flutter/app/product_features.dart';
import 'package:starbridge_flutter/features/overlay_settings/in_memory_overlay_settings_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'composed menu settings acquire current ports after account restore',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 0,
      );
      session.acceptHostCapabilities(const [
        'menuBrowserResume.read',
        'menuBrowserResume.update',
        'menuBrowserResume.remember',
        'menuScreenshotDirectory.read',
        'menuScreenshotDirectory.choose',
        'menuScreenshotDirectory.reset',
        'menuScreenshotDirectory.open',
      ]);
      final requests = <BridgeEnvelope>[];
      final subscription = pair.host.incoming.listen((request) async {
        requests.add(request);
        if (request.name == 'bridge.cancel') return;
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: request.name == 'menuBrowserResume.read'
                ? const {
                    'schemaVersion': 1,
                    'revision': 0,
                    'enabled': false,
                    'url': null,
                  }
                : const {
                    'schemaVersion': 1,
                    'revision': 0,
                    'directory': r'C:\synthetic',
                    'isDefault': true,
                    'cancelled': false,
                    'opened': false,
                  },
          ),
        );
      });
      final app = AppComposition.forShellReview(
        windowChrome: InMemoryWindowChrome(),
      );
      final module = composeOverlaySettings(
        InMemoryOverlaySettingsAdapter(),
        menuLifetime: MenuWindowLifetime(),
        workspacePort: null,
        session: session,
        account: app.account,
        profile: app.personalProfile,
        rooms: app.partyRooms,
      );
      try {
        final preview = module.menuPreview! as MethodChannelMenuPreviewWindow;
        final oldResume = preview.browserResume!;
        final oldDirectory = preview.screenshotDirectory!;
        session.advanceGeneration(
          1,
        ); // The existing startup/account restore boundary.
        final resume = preview.browserResume!;
        final directory = preview.screenshotDirectory!;
        expect(
          (await resume.read()).enabled,
          false,
          reason: 'the settings switch must load after restore',
        );
        expect(
          (await directory.read()).directory,
          r'C:\synthetic',
          reason: 'directory buttons need a confirmed snapshot',
        );
        expect(identical(resume, preview.browserResume), isTrue);
        expect(identical(directory, preview.screenshotDirectory), isTrue);
        await expectLater(
          oldResume.read(),
          throwsA(isA<BridgeClientException>()),
        );
        await expectLater(
          oldDirectory.read(),
          throwsA(isA<BridgeClientException>()),
        );
        expect(
          requests
              .where((r) => r.name.startsWith('menu'))
              .every((r) => r.sessionGeneration == 1),
          isTrue,
        );
      } finally {
        module.dispose();
        app.dispose();
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    },
    skip: !menuOverlayEnabled ? 'requires menu overlay build gate' : false,
  );
}
