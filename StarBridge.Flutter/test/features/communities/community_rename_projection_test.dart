import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'community_navigation_cache_test.dart' show NavigationPort, card;

void main() {
  test(
    'late directory reply cannot resurrect the name from before rename',
    () async {
      final port = NavigationPort();
      final model = CommunitiesModule(port);
      addTearDown(model.dispose);
      await model.refresh();
      model.open(card);
      port.directoryRead = Completer<CommunityDirectory>();
      final reading = model.refresh(silent: true, preserveSelection: true);
      model.applyOrganizationName(card.key, 'A', '新名称');
      port.directoryRead!.complete(CommunityDirectory('mine', '', [card]));
      await reading;
      expect(model.directory!.items.single.name, '新名称');
      expect(model.joined.single.name, '新名称');
      expect(model.selected!.name, '新名称');
    },
  );
  test(
    'rename updates joined, selected and directory without another read',
    () async {
      final port = NavigationPort();
      final changes = <String>[];
      final model = CommunitiesModule(
        port,
        onOrganizationRenamed: (code, name) => changes.add('$code:$name'),
      );
      addTearDown(model.dispose);
      await model.refresh();
      model.open(card);
      final reads = port.directoryReads;
      model.applyOrganizationName(card.key, 'A', '新名称');
      expect(model.joined.single.name, '新名称');
      expect(model.directory!.items.single.name, '新名称');
      expect(model.selected!.name, '新名称');
      expect(model.selected!.targetRef, card.targetRef);
      expect(port.directoryReads, reads);
      expect(changes, ['A:新名称']);
    },
  );
}
