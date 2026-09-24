import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/example_community_workspace.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';

import '../../features/communities/community_chat_test.dart' show chatPage;

import '../../features/communities/community_chat_media_cache_test.dart'
    show MediaPort;
import 'menu_chat_continuity_test.dart' show Archive;
import 'menu_chat_media_test.dart' show photo;

class PhotoPort extends MediaPort
    implements CommunitiesPort, CommunityWorkspacePort {
  PhotoPort() {
    ownAvatarImageData = photo;
  }
  final workspaceGate = Completer<void>();
  int workspaceReads = 0, directoryReads = 0;
  bool failChat = false;
  Completer<void>? chatGate;
  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async {
    await chatGate?.future;
    if (failChat) throw const CommunityFailure('unavailable');
    return CommunityChatPage.parse({
      ...chatPage(),
      if (after > 0) ...{
        'messages': [],
        'oldestSequence': 0,
        'hasOlder': false,
      },
    });
  }

  final card = CommunityCard(
    targetRef: 'a' * 32,
    name: 'Fixture organization',
    logo: photo,
  );
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    directoryReads++;
    return CommunityDirectory(view, query, [card]);
  }

  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async {
    workspaceReads++;
    await workspaceGate.future;
    return exampleCommunityWorkspace(card, query, offset);
  }

  @override
  Future<Map<String, Object?>> readChatDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version,
  ) async {
    calls.add(messageRef);
    await gate?.future;
    final bytes = utf8.encode(
      jsonEncode({'avatarImageData': photo, 'attachment': null}),
    );
    return {
      'schemaVersion': 1,
      'targetRef': targetRef,
      'messageRef': messageRef,
      'offset': 0,
      'next': null,
      'totalBytes': bytes.length,
      'version': sha256.convert(bytes).toString(),
      'data': base64Encode(bytes),
    };
  }

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) async => throw StateError('Unused');
  @override
  Future<String> execute(String action, String targetRef) async =>
      throw StateError('No writes');
  @override
  Future<void> close() => changes.close();
}

class OwnArchive extends Archive {
  @override
  Future<List<Map<String, Object?>>> load(
    String kind,
    String reference,
  ) async => [
    {...(await super.load(kind, reference)).single, 'self': true},
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'own photo is visible on local messages even when the online read fails',
    () async {
      final port = PhotoPort()..failChat = true;
      final directory = Completer<MenuFeatureView>(),
          own = Completer<MenuFeatureView>();
      final session = MenuOrganizationsSession(
        port,
        (raw) {
          final view = MenuFeatureView.parse(raw);
          if (view.organization?.tab == 'directory' && !directory.isCompleted) {
            directory.complete(view);
          }
          if (view.rows.length == 1 &&
              view.rows.single.avatar != null &&
              !own.isCompleted) {
            own.complete(view);
          }
        },
        chatOnly: true,
        archive: OwnArchive(),
      );
      addTearDown(session.dispose);
      session.show(true);
      session.act(
        (await directory.future).channels.single.buttons.single.key,
        '',
      );
      final view = await own.future.timeout(const Duration(seconds: 3));
      expect(view.rows.single.detail, 'saved across restart');
      expect(view.rows.single.avatar, startsWith('data:image/png;base64,'));
      expect(port.workspaceReads, 0);
    },
  );
  test('late sender photo survives a quiet failed poll without restoring send grants', () async {
    final port = PhotoPort()..gate = Completer<void>();
    final directory = Completer<MenuFeatureView>(),
        ready = Completer<void>(),
        photoReady = Completer<MenuFeatureView>();
    final views = <MenuFeatureView>[];
    final session = MenuOrganizationsSession(port, (raw) {
      final view = MenuFeatureView.parse(raw);
      views.add(view);
      if (view.organization?.tab == 'directory' && !directory.isCompleted) {
        directory.complete(view);
      }
      if (view.rows.length == 2 && view.chat != null && !ready.isCompleted) {
        ready.complete();
      }
      if (view.rows.length == 2 &&
          view.rows.first.avatar != null &&
          !photoReady.isCompleted) {
        photoReady.complete(view);
      }
    }, chatOnly: true);
    addTearDown(session.dispose);
    session.show(true);
    session.act(
      (await directory.future).channels.single.buttons.single.key,
      '',
    );
    await ready.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    views.clear();
    port.failChat = true;
    await session.refresh(silent: true);
    expect(
      views.every((v) => !v.refreshing && !v.busy && v.notice.isEmpty),
      true,
    );
    port.gate!.complete();
    final result = await photoReady.future.timeout(const Duration(seconds: 3));
    expect(result.buttons, isEmpty);
    expect(result.rows.every((row) => row.avatar != null), true);
    expect(port.workspaceReads, 0);
  });
  test('cached header logo precedes network; sender media follows text without blocking', () async {
    final port = PhotoPort()..gate = Completer<void>();
    final directory = Completer<MenuFeatureView>(),
        cached = Completer<MenuFeatureView>(),
        online = Completer<MenuFeatureView>(),
        pictures = Completer<MenuFeatureView>();
    final session = MenuOrganizationsSession(
      port,
      (raw) {
        final view = MenuFeatureView.parse(raw);
        if (view.organization?.tab == 'directory' && !directory.isCompleted) {
          directory.complete(view);
        }
        if (view.rows.any((row) => row.detail == 'saved across restart') &&
            !cached.isCompleted) {
          cached.complete(view);
        }
        if (view.chat != null && view.rows.length == 2 && !online.isCompleted) {
          online.complete(view);
        }
        if (view.rows.isNotEmpty &&
            view.rows.every((r) => r.avatar != null) &&
            !pictures.isCompleted) {
          pictures.complete(view);
        }
      },
      chatOnly: true,
      archive: Archive(),
    );
    addTearDown(session.dispose);
    session.show(true);
    final list = await directory.future.timeout(const Duration(seconds: 5));
    session.act(list.channels.single.buttons.single.key, '');
    final local = await cached.future.timeout(const Duration(seconds: 5));
    expect(local.organization!.logo, list.channels.single.avatar);
    expect(local.organization!.logo, isNotNull);
    expect(local.refreshing, false);
    expect(local.notice, isEmpty);
    expect(local.chat!.receipts, isEmpty);
    port.workspaceGate.complete();
    final ready = await online.future.timeout(const Duration(seconds: 5));
    expect(ready.rows.length, 2);
    expect(port.workspaceReads, 0);
    expect(port.directoryReads, 1);
    expect(pictures.isCompleted, false);
    port.gate!.complete();
    final withPhotos = await pictures.future.timeout(
      const Duration(seconds: 5),
    );
    expect(
      withPhotos.rows.every(
        (r) => r.avatar!.startsWith('data:image/png;base64,'),
      ),
      true,
    );
    expect(withPhotos.organization!.logo, local.organization!.logo);
    expect(
      withPhotos.rows.map((r) => r.detail),
      ready.rows.map((r) => r.detail),
    );
  });
  test('late media cannot reopen a hidden conversation', () async {
    final port = PhotoPort()..gate = Completer<void>();
    port.workspaceGate.complete();
    final directory = Completer<MenuFeatureView>(), ready = Completer<void>();
    final views = <Map<String, Object?>>[];
    final session = MenuOrganizationsSession(port, (raw) {
      views.add(raw);
      final view = MenuFeatureView.parse(raw);
      if (view.organization?.tab == 'directory' && !directory.isCompleted) {
        directory.complete(view);
      }
      if (view.chat != null && !view.refreshing && !ready.isCompleted) {
        ready.complete();
      }
    }, chatOnly: true);
    addTearDown(session.dispose);
    session.show(true);
    session.act(
      (await directory.future).channels.single.buttons.single.key,
      '',
    );
    await ready.future.timeout(const Duration(seconds: 5));
    session.show(false);
    final count = views.length;
    port.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(views.length, count);
  });
}
