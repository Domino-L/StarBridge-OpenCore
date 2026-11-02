import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/social_windows/window_message_health.dart';

const _now = 1800000000000;
Map<String, Object?> _packet({
  int opening = 1,
  String scope = 'fixture',
  int revision = 1,
  bool healthy = true,
  int sent = _now,
}) => {
  'opening': opening,
  'scope': scope,
  'revision': revision,
  'healthy': healthy,
  'leaseMilliseconds': 3000,
  'sentAtUtcMilliseconds': sent,
};

void main() {
  testWidgets('duplicate or stale health never extends its original deadline', (
    t,
  ) async {
    final health = WindowMessageHealth(utcNowMilliseconds: () => _now)
      ..bind(1, 'fixture');
    expect(health.accept(_packet()), true);
    await t.pump(const Duration(seconds: 2));
    expect(health.accept(_packet()), false);
    await t.pump(const Duration(milliseconds: 1100));
    expect(health.healthy, false);
    expect(health.accept(_packet(revision: 0)), false);
    expect(health.healthy, false);
    health.dispose();
  });

  testWidgets('a delayed fresh revision receives only its remaining lease', (
    t,
  ) async {
    final health = WindowMessageHealth(utcNowMilliseconds: () => _now)
      ..bind(1, 'fixture');
    expect(health.accept(_packet(sent: _now - 2000)), true);
    await t.pump(const Duration(milliseconds: 1100));
    expect(health.healthy, false);
    expect(health.accept(_packet(revision: 2, sent: _now - 3000)), false);
    expect(health.accept(_packet(revision: 3, sent: _now + 1)), false);
    expect(health.healthy, false);
    health.dispose();
  });

  testWidgets('changing window opening or scope immediately retires health', (
    t,
  ) async {
    final health = WindowMessageHealth(utcNowMilliseconds: () => _now)
      ..bind(1, 'fixture');
    expect(health.accept(_packet()), true);
    health.bind(2, 'fixture');
    expect(health.healthy, false);
    expect(health.accept(_packet(revision: 2)), false);
    expect(health.accept(_packet(opening: 2, revision: 0)), true);
    health.bind(2, 'new-context');
    expect(health.healthy, false);
    expect(health.accept(_packet(opening: 2, revision: 2)), false);
    expect(
      health.accept(_packet(opening: 2, scope: 'new-context', revision: 0)),
      true,
    );
    health.dispose();
    expect(health.healthy, false);
    expect(
      health.accept(_packet(opening: 2, scope: 'new-context', revision: 1)),
      false,
    );
  });

  testWidgets('unhealthy current metadata withdraws a former healthy lease', (
    t,
  ) async {
    final health = WindowMessageHealth(utcNowMilliseconds: () => _now)
      ..bind(1, 'fixture');
    expect(health.accept(_packet()), true);
    expect(health.accept(_packet(revision: 2, healthy: false)), true);
    expect(health.healthy, false);
    expect(health.accept(_packet()), false);
    expect(health.healthy, false);
    health.dispose();
  });

  final invalid = <String, Object?>{
    'missing': null,
    'extra': {..._packet(), 'extra': 'unrelated'},
    'wrong healthy type': {..._packet(), 'healthy': 1},
    'negative revision': {..._packet(), 'revision': -1},
    'wrong timestamp type': {
      ..._packet(),
      'sentAtUtcMilliseconds': 'untrusted',
    },
    'extended duration': {..._packet(), 'leaseMilliseconds': 3001},
    'retired scope': _packet(scope: 'retired'),
    'retired opening': _packet(opening: 2),
  };
  for (final entry in invalid.entries) {
    test('invalid health metadata cannot suppress fallback: ${entry.key}', () {
      final health = WindowMessageHealth(utcNowMilliseconds: () => _now)
        ..bind(1, 'fixture');
      expect(health.accept(entry.value), false);
      expect(health.healthy, false);
      health.dispose();
    });
  }
}
