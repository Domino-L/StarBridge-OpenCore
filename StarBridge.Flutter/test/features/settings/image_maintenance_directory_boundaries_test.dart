import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import '../communities/community_offline_directory_test.dart'
    show OfflineDirectoryHost, offlineLogo;

class PendingDirectoryPort implements CommunitiesPort {
  final changes = StreamController<void>.broadcast();
  final pending = <Completer<CommunityDirectory>>[];
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) {
    final next = Completer<CommunityDirectory>();
    pending.add(next);
    return next.future;
  }

  @override
  Future<String> execute(String action, String targetRef) async => 'rejected';
  @override
  Future<void> close() => changes.close();
}

const card = CommunityCard(
  targetRef: 'a',
  organizationRef: 'stable',
  name: 'Organization',
  description: 'Description',
  tags: 'Exploration',
  systems: ['Pyro'],
  memberCount: 5,
  actions: ['leave'],
  relationship: 'member',
  logo: offlineLogo,
  logoDeferred: true,
);

void main() {
  test('selective purge retains selected organization, joined roles, filters and cursor metadata', () async {
    final port = PendingDirectoryPort();
    final model = CommunitiesModule(port);
    try {
      final reading = model.refresh(
        newView: 'discover',
        newQuery: 'explore',
        newFilters: '{"language":"zh"}',
      );
      port.pending.single.complete(
        const CommunityDirectory(
          'discover',
          'explore',
          [card],
          next: 'next-page',
          totalCount: 21,
        ),
      );
      await reading;
      final joined = model.refreshJoined();
      port.pending.last.complete(const CommunityDirectory('mine', '', [card]));
      await joined;
      model.open(model.directory!.items.single);
      model.beginImageMaintenance();
      model.endImageMaintenance();
      expect(model.selected!.logo, isNull);
      expect(model.joined.single.logo, isNull);
      expect(model.directory!.items.single.logo, isNull);
      expect(model.selected!.key, card.key);
      expect(model.joined.single.relationship, 'member');
      expect(model.joined.single.actions, ['leave']);
      expect(model.directory!.next, 'next-page');
      expect(model.directory!.totalCount, 21);
      expect(model.view, 'discover');
      expect(model.query, 'explore');
      expect(model.filters, '{"language":"zh"}');
      expect(model.accountRevision, 0);
      expect(
        port.pending,
        hasLength(2),
        reason: 'Purge cannot become an automatic business read.',
      );
    } finally {
      model.dispose();
      await port.close();
    }
  });
  for (final joined in [false, true]) {
    test(
      'late ${joined ? 'joined' : 'directory'} parent cannot restore retired inline logo',
      () async {
        final port = PendingDirectoryPort();
        final model = CommunitiesModule(port);
        try {
          final reading = joined ? model.refreshJoined() : model.refresh();
          expect(port.pending, hasLength(1));
          model.beginImageMaintenance();
          model.endImageMaintenance();
          port.pending.single.complete(
            CommunityDirectory(joined ? 'mine' : model.view, '', [card]),
          );
          await reading;
          final row = joined
              ? model.joined.single
              : model.directory!.items.single;
          expect(row.logo, isNull);
          expect(row.key, card.key);
          expect(row.description, card.description);
          expect(row.systems, card.systems);
          expect(row.actions, card.actions);
          expect(row.memberCount, card.memberCount);
          expect(row.relationship, card.relationship);
          if (!joined) {
            final fresh = model.refresh(reuseFresh: true);
            expect(
              port.pending,
              hasLength(2),
              reason: 'A retired parent read cannot renew the 10s freshness window.',
            );
            port.pending.last.complete(
              CommunityDirectory(model.view, '', [card]),
            );
            await fresh;
            expect(model.directory!.items.single.logo, offlineLogo);
          }
        } finally {
          model.dispose();
          await port.close();
        }
      },
    );
  }

  test('offline logo completion after purge is ignored; explicit reread can repopulate', () async {
    final host = await OfflineDirectoryHost.create();
    final model = CommunitiesModule(host.port);
    try {
      await model.refreshJoined();
      while (!host.seen.any(
        (r) => r.name == 'onboarding.mode.communityMedia',
      )) {
        await Future<void>.delayed(Duration.zero);
      }
      final time = model.joinedCachedAtUtc;
      model.beginImageMaintenance();
      model.endImageMaintenance();
      await host.releaseMedia();
      expect(model.joined.single.name, 'Retained Organization');
      expect(model.joined.single.logo, isNull);
      expect(model.joinedCachedAtUtc, time);
      expect(model.joinedError, isNull);
      await model.refreshJoined();
      await host.releaseMedia();
      expect(model.joined.single.logo, offlineLogo);
      expect(host.seen.any((r) => r.name == 'account.getCurrent'), isFalse);
    } finally {
      model.dispose();
      await host.close();
    }
  });

  test(
    'offline metadata read during purge skips optional image transport',
    () async {
      final host = await OfflineDirectoryHost.create();
      final model = CommunitiesModule(host.port);
      try {
        model.beginImageMaintenance();
        await model.refreshJoined();
        await host.releaseMedia();
        expect(model.joined.single.logo, isNull);
        expect(model.joined.single.name, 'Retained Organization');
        expect(
          host.seen.where((r) => r.name == 'onboarding.mode.communityMedia'),
          isEmpty,
        );
        model.endImageMaintenance();
        await model.refreshJoined();
        await host.releaseMedia();
        expect(model.joined.single.logo, offlineLogo);
      } finally {
        model.dispose();
        await host.close();
      }
    },
  );
}
