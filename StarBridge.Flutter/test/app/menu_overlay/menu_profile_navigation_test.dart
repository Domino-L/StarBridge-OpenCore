import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_profile_navigation.dart';
import 'package:starbridge_flutter/platform/window/menu_preview_window_port.dart';
import 'package:starbridge_flutter/platform/window/menu_feature_lease.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';

class Targets implements MenuFriendsReadLease, MenuProfileTargets {
  bool visible = false, authorized = true;
  @override
  void show(bool value) => visible = value;
  @override
  void dispose() => visible = false;
  @override
  MenuProfileTarget? profileTarget(String key) =>
      key == 'f1' && visible && authorized
      ? MenuProfileTarget(
          source: 'friend',
          reference: 'private-ref',
          query: 'fixture',
          isCurrent: () => visible && authorized,
          isAccountCurrent: () => authorized,
        )
      : null;
}

class Profiles implements MenuProfilesReadLease {
  final opened = <String>[];
  int hidden = 0, refreshed = 0, closed = 0;
  @override
  void open(String window, MenuProfileTarget target) {
    expect(target.reference, 'private-ref');
    opened.add(window);
  }

  @override
  void refresh(String window) => refreshed++;
  @override
  void closeWindow(String window) => closed++;
  @override
  void hide() => hidden++;
  @override
  void dispose() {}
}

class OrganizationTargets extends Targets implements MenuFeatureLease {
  @override
  void act(String key, String value) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starbridge/menu-primary');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> event(String method, Object data) =>
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, data)),
        (_) {},
      );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final source in ['organizations', 'organizationChat']) {
    test(
      '$source profile source requires an open authorized feature lease',
      () async {
        final targets = OrganizationTargets(), profiles = Profiles();
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'preview' ? 9 : null,
        );
        final window = MethodChannelMenuPreviewWindow(
          friends: (_) => Targets(),
          features: {source: (_) => targets},
          profiles: (_) => profiles,
        );
        final opening = window.openLive(
          contextLabel: 'Fixture',
          returnLabel: 'Back',
          settingsLabel: 'Settings',
        );
        await Future<void>.delayed(Duration.zero);
        await event('state', 'visible');
        expect(await opening, true);
        final request = {
          'opening': 9,
          'action': 'open',
          'window': 'p1',
          'source': source,
          'key': 'f1',
        };
        await event('profileAction', request);
        expect(profiles.opened, isEmpty);
        await event('featureVisible', {
          'opening': 9,
          'tool': source,
          'visible': true,
        });
        await event('profileAction', request);
        expect(profiles.opened, ['p1']);
        await event('featureVisible', {
          'opening': 9,
          'tool': source,
          'visible': false,
        });
        await event('profileAction', {...request, 'window': 'p2'});
        expect(profiles.opened, ['p1']);
        window.dispose();
      },
    );
  }
  test('profile window resolves only a current key and never sends a ref or handoff to native', () async {
    final targets = Targets(), calls = <MethodCall>[];
    final profiles = Profiles();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'preview' => 5,
        'handoffProfile' => true,
        _ => null,
      };
    });
    final window = MethodChannelMenuPreviewWindow(
      friends: (_) => targets,
      profiles: (_) => profiles,
    );
    final opening = window.openLive(
      contextLabel: 'Fixture',
      returnLabel: 'Back',
      settingsLabel: 'Settings',
    );
    await Future<void>.delayed(Duration.zero);
    await event('state', 'visible');
    expect(await opening, true);
    await event('friendsVisible', {'opening': 5, 'visible': true});
    for (final request in [
      {'opening': 4, 'source': 'friends', 'key': 'f1'},
      {'opening': 5, 'source': 'comms', 'key': 'f1'},
      {'opening': 5, 'source': 'friends', 'key': 'private-ref'},
    ]) {
      await event('profileAction', {
        ...request,
        'action': 'open',
        'window': 'p1',
      });
    }
    expect(profiles.opened, isEmpty);
    await event('profileAction', {
      'opening': 5,
      'action': 'open',
      'window': 'p1',
      'source': 'friends',
      'key': 'f1',
    });
    expect(profiles.opened, ['p1']);
    expect(calls.where((c) => c.method == 'handoffProfile'), isEmpty);
    await event('profileAction', {
      'opening': 5,
      'action': 'refresh',
      'window': 'p1',
    });
    await event('profileAction', {
      'opening': 5,
      'action': 'close',
      'window': 'p1',
    });
    expect(profiles.refreshed, 1);
    expect(profiles.closed, 1);
    expect(calls.toString(), isNot(contains('private-ref')));
    await event('state', 'hidden');
    await event('profileAction', {
      'opening': 5,
      'source': 'friends',
      'key': 'f1',
    });
    expect(profiles.opened, ['p1']);
    expect(profiles.hidden, 1);
    window.dispose();
  });

  test('revoked and malformed targets never start a profile lease', () async {
    final targets = Targets(), calls = <MethodCall>[];
    final profiles = Profiles();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'preview' ? 8 : null;
    });
    final window = MethodChannelMenuPreviewWindow(
      friends: (_) => targets,
      profiles: (_) => profiles,
    );
    final opening = window.openLive(
      contextLabel: 'Fixture',
      returnLabel: 'Back',
      settingsLabel: 'Settings',
    );
    await Future<void>.delayed(Duration.zero);
    await event('state', 'visible');
    expect(await opening, true);
    await event('friendsVisible', {'opening': 8, 'visible': true});
    await event('profileAction', {
      'opening': 8,
      'action': 'open',
      'window': 'private-ref',
      'source': 'friends',
      'key': 'f1',
    });
    targets.authorized = false;
    await event('profileAction', {
      'opening': 8,
      'action': 'open',
      'window': 'p1',
      'source': 'friends',
      'key': 'f1',
    });
    expect(profiles.opened, isEmpty);
    expect(calls.where((c) => c.method == 'handoffProfile'), isEmpty);
    expect((calls.last.arguments as Map)['payload'], contains('unavailable'));
    window.dispose();
  });
}
