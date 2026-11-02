import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

class _Owner extends ChangeNotifier {
  bool busy = false;
  int phase = 0;
  bool get observed => hasListeners;
  void emit() => notifyListeners();
}

void main() {
  test('3fv binding default keeps original busy-edge behavior', () {
    final owner = _Owner();
    final binding = SocialReadActivityBinding(
      owner,
      () => owner.busy,
      initialRead: true,
    );
    runStarBridgeSynchronousActivation(InteractionSource.pointer, () {
      owner.busy = true;
      owner.phase++;
      owner.emit();
    });
    expect(binding.revision, 1);
    expect(binding.source, InteractionSource.pointer);
    expect(binding.opening, isTrue);
    runStarBridgeSynchronousActivation(InteractionSource.keyboard, () {
      owner.phase++;
      owner.emit();
    });
    expect(binding.revision, 1);
    expect(binding.source, InteractionSource.pointer);
    owner.busy = false;
    owner.emit();
    runStarBridgeSynchronousActivation(InteractionSource.keyboard, () {
      owner.busy = true;
      owner.emit();
    });
    expect(binding.revision, 2);
    expect(binding.source, InteractionSource.keyboard);
    expect(binding.opening, isFalse);
    binding.dispose();
    expect(owner.observed, isFalse);
    owner.dispose();
  });

  test('3fv optional identity distinguishes replacement from unrelated busy notification', () {
    final owner = _Owner();
    final binding = SocialReadActivityBinding(
      owner,
      () => owner.busy,
      initialRead: true,
      phaseIdentity: () => owner.busy ? owner.phase : null,
    );
    runStarBridgeSynchronousActivation(InteractionSource.pointer, () {
      owner.busy = true;
      owner.phase = 1;
      owner.emit();
    });
    runStarBridgeSynchronousActivation(InteractionSource.keyboard, owner.emit);
    expect(binding.revision, 1);
    expect(binding.source, InteractionSource.pointer);
    runStarBridgeSynchronousActivation(InteractionSource.keyboard, () {
      owner.phase = 2;
      owner.emit();
    });
    expect(binding.revision, 2);
    expect(binding.source, InteractionSource.keyboard);
    expect(binding.opening, isFalse);
    owner.emit();
    expect(binding.revision, 2);
    owner.busy = false;
    owner.emit();
    owner.busy = true;
    owner.phase = 3;
    owner.emit();
    expect(binding.revision, 3);
    expect(binding.source, InteractionSource.programmatic);
    binding.dispose();
    owner.dispose();
  });

  test('3fv identity observation detaches without owning or notifying borrowed owner', () {
    final owner = _Owner()
      ..busy = true
      ..phase = 5;
    var identityReads = 0;
    final binding = SocialReadActivityBinding(
      owner,
      () => owner.busy,
      initialRead: false,
      phaseIdentity: () {
        identityReads++;
        return owner.phase;
      },
    );
    expect(identityReads, 1);
    expect(binding.opening, isFalse);
    expect(binding.source, InteractionSource.programmatic);
    binding.dispose();
    owner.phase++;
    owner.emit();
    expect(identityReads, 1);
    expect(binding.revision, 1);
    expect(owner.observed, isFalse);
    owner.dispose();
  });
}
