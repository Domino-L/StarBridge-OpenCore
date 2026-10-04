import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_directory_logos.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';

import 'menu_channel_media_session_test.dart' show PhotoPort;
import 'menu_chat_media_test.dart' show photo;

class MembersOnlyPort implements CommunitiesPort, CommunityWorkspacePort {
  final source = PhotoPort()..workspaceGate.complete();
  @override
  Stream<void> get invalidations => source.invalidations;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) => source.read(view: view, query: query, after: after, filters: filters);
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) => source.readWorkspace(targetRef, query, offset);
  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) => source.readMedia(
    targetRef,
    kind,
    memberRef: memberRef,
    offset: offset,
    version: version,
  );
  @override
  Future<String> execute(String action, String targetRef) =>
      source.execute(action, targetRef);
  @override
  Future<void> close() => source.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('late logo updates members even without a cached chat view', () async {
    final port = MembersOnlyPort();
    final loaded = Completer<MenuFeatureView>();
    final session = MenuOrganizationsSession(port, (raw) {
      final view = MenuFeatureView.parse(raw);
      if (view.organization?.tab == 'members' &&
          view.organization?.logo != null &&
          !loaded.isCompleted) {
        loaded.complete(view);
      }
    })..show(true);
    addTearDown(session.dispose);
    final view = await loaded.future.timeout(const Duration(seconds: 3));
    expect(
      view.organization!.navigation.single.avatar,
      view.organization!.logo,
    );
  });
  test(
    'failed quiet logo decode never replaces the last authorized image',
    () async {
      var now = DateTime(2026);
      final updates = <String?>[];
      final loaded = Completer<void>();
      final port = PhotoPort();
      final logos = MenuDirectoryLogos(port, (_, image) {
        updates.add(image);
        if (!loaded.isCompleted) loaded.complete();
      }, now: () => now);
      addTearDown(logos.dispose);
      addTearDown(port.close);
      final valid = CommunityCard(
        targetRef: 'a' * 32,
        name: 'Fixture',
        logo: photo,
      );
      await logos.read(valid);
      await loaded.future.timeout(const Duration(seconds: 3));
      final image = updates.single;
      expect(image, isNotNull);
      now = now.add(const Duration(seconds: 31));
      final broken = CommunityCard(
        targetRef: valid.targetRef,
        name: 'Fixture',
        logo: 'data:image/png;base64,AAAA',
      );
      expect(await logos.read(broken), image);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(updates, [image]);
      expect(await logos.read(broken), image);
      expect(
        await logos.read(
          CommunityCard(targetRef: valid.targetRef, name: 'Fixture'),
        ),
        isNull,
      );
      expect(updates.last, isNull, reason: 'Explicit removal is authoritative');
      logos.clear();
      expect(await logos.read(broken), isNull);
    },
  );
}
