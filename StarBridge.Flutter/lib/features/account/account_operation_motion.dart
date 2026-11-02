import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'account_models.dart';
import 'account_module.dart';

// Presentation provenance only. Never persisted or read by the auth owner.
final _origins = Expando<_Origin>();

class _Origin {
  _Origin(this.operation, this.source);
  final AccountOperation operation;
  final InteractionSource source;
}

Future<AccountActionResult> runAccountMotionCommand(
  AccountModule module,
  AccountOperation operation,
  InteractionSource source,
  Future<AccountActionResult> Function() command,
) async {
  final origin = _Origin(operation, source);
  _origins[module] = origin;
  try {
    return await command();
  } finally {
    if (identical(_origins[module], origin)) _origins[module] = null;
  }
}

InteractionSource accountOperationSource(
  BuildContext context,
  AccountModule? module,
) {
  final origin = module == null ? null : _origins[module];
  if (origin != null &&
      origin.operation == module!.projection.value.operation) {
    return origin.source;
  }
  return resolveStarBridgeInitialReadSource(
    context,
    InteractionSource.programmatic,
  );
}

class AccountOperationWaiting extends StatelessWidget {
  const AccountOperationWaiting({this.module, super.key});
  final AccountModule? module;
  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) {
        final data = InteractionScope.of(context),
            source = accountOperationSource(context, module);
        return InteractionScope(
          data: data.copyWith(
            reduceMotion:
                data.reduceMotion || source == InteractionSource.keyboard,
          ),
          child: const SuiteProgressBar(
            value: null,
            phase: ProgressPhase.running,
          ),
        );
      },
    ),
  );
}
