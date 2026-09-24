import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

const member = CommunityCard(
  targetRef: 'member-target',
  organizationRef: 'organization-a',
  name: 'Organization A',
  relationship: 'member',
  actions: ['leave'],
);

class LeavePort implements CommunitiesPort {
  final changes = StreamController<void>.broadcast(sync: true);
  List<CommunityCard> cards = [member];
  String status = 'accepted';
  int writes = 0;
  bool failReads = false;
  Completer<String>? pendingWrite;
  Completer<CommunityDirectory>? pendingRead;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    if (failReads) throw const CommunityFailure('unavailable');
    if (pendingRead != null) return pendingRead!.future;
    return CommunityDirectory(view, query, cards);
  }

  @override
  Future<String> execute(String action, String targetRef) async {
    expect(action, 'leave');
    expect(targetRef, member.targetRef);
    writes++;
    final result = pendingWrite == null ? status : await pendingWrite!.future;
    if (result == 'accepted') cards = [];
    return result;
  }

  @override
  Future<void> close() => changes.close();
}

void main() {
  test('Cancelled chat draft guard prevents ordinary exit', () async {
    final port = LeavePort();
    final model = CommunitiesModule(port);
    await model.refresh();
    model.open(member);
    model.confirmWorkspaceLeave = () async => false;
    await model.execute(member, 'leave');
    expect(port.writes, 0);
    expect(model.selected, member);
    expect(model.joined.single, member);
    model.dispose();
  });

  test('Account change while confirming cannot submit old exit', () async {
    final port = LeavePort();
    final model = CommunitiesModule(port);
    final confirm = Completer<bool>();
    model.confirmWorkspaceLeave = () => confirm.future;
    final leaving = model.execute(member, 'leave');
    port.changes.add(null);
    confirm.complete(true);
    await leaving;
    expect(port.writes, 0);
    expect(model.joined, isEmpty);
    model.dispose();
  });

  test(
    'Confirmed exit clears workspace and shortcut even when refresh fails',
    () async {
      final port = LeavePort();
      final model = CommunitiesModule(port);
      await model.refresh();
      model.open(member);
      port.failReads = true;
      await model.execute(member, 'leave');
      expect(port.writes, 1);
      expect(model.message, 'done.leave');
      expect(model.selected, isNull);
      expect(model.joined, isEmpty);
      expect(model.directory, isNull);
      model.dispose();
    },
  );

  test('Unknown exit stays unknown and refresh does not replay', () async {
    final port = LeavePort()..status = 'unknown';
    final model = CommunitiesModule(port);
    await model.execute(member, 'leave');
    expect(model.message, 'outcomeUnknown');
    expect(model.selected, isNull);
    expect(port.writes, 1);
    await model.refreshJoined();
    expect(port.writes, 1);
    model.dispose();
  });

  test('Late exit response cannot change the next account', () async {
    final port = LeavePort()..pendingWrite = Completer<String>();
    final model = CommunitiesModule(port);
    final leaving = model.execute(member, 'leave');
    await Future<void>.delayed(Duration.zero);
    expect(port.writes, 1);
    port.changes.add(null);
    port.pendingWrite!.complete('accepted');
    await leaving;
    expect(model.message, isNull);
    expect(model.error, 'identityUnavailable');
    expect(model.joined, isEmpty);
    model.dispose();
  });

  test(
    'A joined read started before exit cannot restore the old shortcut',
    () async {
      final port = LeavePort()..pendingRead = Completer<CommunityDirectory>();
      final oldRead = port.pendingRead!;
      final model = CommunitiesModule(port);
      final reading = model.refreshJoined();
      port.pendingRead = null;
      await model.execute(member, 'leave');
      oldRead.complete(const CommunityDirectory('mine', '', [member]));
      await reading;
      expect(model.joined, isEmpty);
      expect(port.writes, 1);
      model.dispose();
    },
  );
}
