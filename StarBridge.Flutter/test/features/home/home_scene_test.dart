import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/home/home_scene.dart';

void main() {
  test('pool contains exactly the approved scenes', () {
    expect(HomeScenes.values, [
      HomeScenes.orisonNight,
      HomeScenes.area18Dusk,
      HomeScenes.lorvilleSkyline,
      HomeScenes.lorvillePort,
    ]);
    expect(HomeScenes.values.map((scene) => scene.id).toSet(), hasLength(4));
    for (final scene in HomeScenes.values) {
      expect(scene.videoAsset, startsWith('assets/home-scenes/'));
      expect(scene.posterAsset, startsWith('assets/home-scenes/'));
      expect(scene.videoAsset, endsWith('-loop-v1.mp4'));
      expect(scene.posterAsset, endsWith('-poster-v1.jpg'));
    }
    expect(() => HomeScenes.values.clear(), throwsUnsupportedError);
  });

  test('one uniform draw reaches every scene without extra random draws', () {
    for (var index = 0; index < 4; index++) {
      final random = _IndexRandom(index);
      expect(HomeScenes.choose(random), same(HomeScenes.values[index]));
      expect(random.bounds, [4]);
    }
  });

  test('launch selection is stable across repeated page and account reads', () {
    final scene = HomeScenes.forLaunch;
    expect(HomeScenes.values, contains(scene));
    for (var read = 0; read < 100; read++) {
      expect(HomeScenes.forLaunch, same(scene));
    }
  });
}

class _IndexRandom implements Random {
  _IndexRandom(this.index);
  final int index;
  final bounds = <int>[];

  @override
  int nextInt(int max) {
    bounds.add(max);
    expect(index, lessThan(max));
    return index;
  }

  @override
  bool nextBool() => throw StateError('Unexpected random draw');
  @override
  double nextDouble() => throw StateError('Unexpected random draw');
}
