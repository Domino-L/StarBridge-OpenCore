import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/account_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'account_staged_read_test.dart' show StagedProfileHost;

const _path = String.fromEnvironment('STARBRIDGE_STAGED_PROFILE_WIRE');
const _image = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB';

void main() {
  testWidgets(
    'avatar retry backoff signals idle work without starting IO and stops after four retries',
    (tester) async {
      final fixture = await tester.runAsync(
        () async =>
            jsonDecode(await File(_path).readAsString())
                as Map<String, dynamic>,
      );
      final h = StagedProfileHost(fixture!);
      h.session.acceptHostCapabilities([
        ...h.session.hostCapabilities,
        'account.avatar.read',
      ]);
      h.extraErrors['account.readAvatar'] = const BridgeErrorBody(
        code: 'personal_profile.read_transient',
        message: 'Synthetic outage',
        retryable: true,
      );
      try {
        await h.module.initialize();
        await h.preparation.prepareNextRead();
        await tester.pump();
        int count() =>
            h.names.where((name) => name == 'account.readAvatar').length;
        expect(count(), 1);
        for (final delay in [2, 5, 10, 30]) {
          final previous = count();
          await tester.pump(Duration(seconds: delay));
          expect(
            count(),
            previous,
            reason: 'A timer cannot initiate private IO',
          );
          await h.preparation.prepareNextRead();
          await tester.pump();
          expect(count(), previous + 1);
        }
        await tester.pump(const Duration(minutes: 1));
        await h.preparation.prepareNextRead();
        await tester.pump();
        expect(count(), 5);
        expect(h.module.projection.value.isSignedIn, isTrue);
      } finally {
        await tester.runAsync(h.close);
      }
    },
    skip: _path.isEmpty,
  );
  testWidgets(
    'avatar is displayed while profile and directory are held, and late profile cannot overwrite it',
    (tester) async {
      final fixture = await tester.runAsync(
        () async =>
            jsonDecode(await File(_path).readAsString())
                as Map<String, dynamic>,
      );
      final h = StagedProfileHost(fixture!);
      h.session.acceptHostCapabilities([
        ...h.session.hostCapabilities,
        'account.avatar.read',
      ]);
      h.extraReplies['account.readAvatar'] = {
        'schemaVersion': 1,
        'imageData': _image,
        'callSign': 'Current pilot',
      };
      h.hold.addAll([
        'profile.getDisplayData',
        'account.readAvatar',
        'profile.getTimeZoneDirectory',
      ]);
      final chrome = AccountShellChrome(
        base: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        account: h.module,
      );
      try {
        await h.module.initialize();
        expect(chrome.projection.value.connectionIssue, isNull);
        final profile = h.preparation.prepareNextRead();
        await tester.pump();
        expect(h.names, contains('account.readAvatar'));
        expect(h.names, contains('profile.getDisplayData'));
        expect(
          h.names.indexOf('account.readAvatar'),
          lessThan(h.names.indexOf('profile.getDisplayData')),
          reason: 'Native keeps its protected serialization; avatar must be admitted ahead of metadata, not merely sent concurrently.',
        );
        h.hold.remove('account.readAvatar');
        for (final request in h.held.remove('account.readAvatar')!) {
          h.reply(request);
        }
        await tester.pump();
        expect(h.module.projection.value.profile?.avatarImageData, _image);
        expect(h.module.projection.value.profile?.displayName, 'Current pilot');
        expect(
          h.module.projection.value.profileFreshness,
          AccountProfileFreshness.cached,
        );
        expect(h.module.projection.value.canEditPreferences, isFalse);
        h.hold.remove('profile.getDisplayData');
        for (final request in h.held.remove('profile.getDisplayData')!) {
          h.reply(request);
        }
        await tester.pump();
        await profile;
        expect(
          h.module.projection.value.profileFreshness,
          AccountProfileFreshness.live,
        );
        expect(h.module.projection.value.profile?.avatarImageData, _image);
        expect(h.module.projection.value.profile?.displayName, 'Current pilot');
        final directory = h.preparation.prepareNextRead();
        await tester.pump();
        await tester.pump(const Duration(seconds: 59));
        expect(h.module.projection.value.profile?.avatarImageData, _image);
        expect(chrome.projection.value.connectionIssue, isNull);
        h.preparation.cancelReadPreparation();
        await tester.pump();
        await directory;
      } finally {
        chrome.dispose();
        await tester.runAsync(h.close);
      }
    },
    skip: _path.isEmpty,
  );

  test(
    'an actual live refresh falling back to cache still reports failure',
    () async {
      final h = await StagedProfileHost.create();
      final chrome = AccountShellChrome(
        base: InMemoryShellChrome(
          initial: InMemoryShellChrome.connectedProjection,
        ),
        account: h.module,
      );
      addTearDown(() async {
        chrome.dispose();
        await h.close();
      });
      h.liveKey = 'cached';
      await h.module.initialize();
      expect(chrome.projection.value.connectionIssue, isNull);
      await h.preparation.prepareNextRead();
      expect(h.module.projection.value.failure, isNotNull);
      expect(
        chrome.projection.value.connectionIssue?.titleKey,
        'connection.account.cached.title',
      );
      expect(h.module.projection.value.canEditPreferences, isFalse);
    },
    skip: _path.isEmpty,
  );

  // User report 2026-10-20 ("进入后昵称晚出现"): device traces showed the first
  // call sign read cancelled in 40/40 samples and the name missing for 27-50 s.
  for (final interrupt in ['interaction', 'refresh']) {
    testWidgets(
      'a warm-up $interrupt does not drop the in-flight call sign read',
      (tester) async {
        final fixture = await tester.runAsync(
          () async =>
              jsonDecode(await File(_path).readAsString())
                  as Map<String, dynamic>,
        );
        final h = StagedProfileHost(fixture!);
        h.session.acceptHostCapabilities([
          ...h.session.hostCapabilities,
          'account.avatar.read',
        ]);
        h.extraReplies['account.readAvatar'] = {
          'schemaVersion': 1,
          'imageData': _image,
          'callSign': 'Current pilot',
        };
        h.hold.add('account.readAvatar');
        try {
          await h.module.initialize();
          final prepared = h.preparation.prepareNextRead();
          await tester.pump();
          expect(h.names, contains('account.readAvatar'));
          if (interrupt == 'interaction') {
            // SessionWarmup.deferForInteraction on any click or scroll.
            h.preparation.cancelReadPreparation();
          } else {
            await h.module.refresh();
          }
          await tester.pump();
          h.hold.remove('account.readAvatar');
          for (final request in h.held.remove('account.readAvatar')!) {
            h.reply(request);
          }
          await tester.pump();
          expect(
            h.module.projection.value.profile?.displayName,
            'Current pilot',
            reason: 'the call sign is shown without waiting for another read',
          );
          expect(
            h.names.where((name) => name == 'account.readAvatar').length,
            1,
          );
          h.preparation.cancelReadPreparation();
          await tester.pump();
          await prepared;
        } finally {
          await tester.runAsync(h.close);
        }
      },
      skip: _path.isEmpty,
    );
  }

  testWidgets(
    'hard profile denial cannot be undone by an earlier pending avatar',
    (tester) async {
      final fixture = await tester.runAsync(
        () async =>
            jsonDecode(await File(_path).readAsString())
                as Map<String, dynamic>,
      );
      final h = StagedProfileHost(fixture!);
      h.session.acceptHostCapabilities([
        ...h.session.hostCapabilities,
        'account.avatar.read',
      ]);
      h.liveKey = 'forbidden';
      h.hold.add('account.readAvatar');
      h.extraReplies['account.readAvatar'] = {
        'schemaVersion': 1,
        'imageData': _image,
        'callSign': 'Retired pilot',
      };
      try {
        await h.module.initialize();
        final profile = h.preparation.prepareNextRead();
        await tester.pump();
        await profile;
        expect(h.module.projection.value.profile, isNull);
        for (final request in h.held.remove('account.readAvatar')!) {
          h.reply(request);
        }
        await tester.pump();
        expect(h.module.projection.value.profile, isNull);
        await h.preparation.prepareNextRead();
        await tester.pump();
        expect(h.names.where((name) => name == 'account.readAvatar').length, 1);
        expect(h.module.projection.value.canEditPreferences, isFalse);
      } finally {
        await tester.runAsync(h.close);
      }
    },
    skip: _path.isEmpty,
  );
}
