import 'dart:async';

import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';

import '../../features/account/account_models.dart';
import '../../features/account/account_operation_motion.dart';
import 'app_composition.dart';

/// UI provenance seam. Original account owner still performs every command.
extension AccountMenuMotion on AppComposition {
  void logoutFromMenu() =>
      unawaited(logoutWithMenuMotion(currentStarBridgeActivationSource));
  void resolveIssueFromMenu() =>
      unawaited(resolveIssueWithMenuMotion(currentStarBridgeActivationSource));
  Future<AccountActionResult> logoutWithMenuMotion(InteractionSource source) =>
      runAccountMotionCommand(
        account,
        AccountOperation.signingOut,
        source,
        account.logout,
      );
  Future<AccountActionResult> resolveIssueWithMenuMotion(
    InteractionSource source,
  ) => runAccountMotionCommand(
    account,
    account.projection.value.sessionState ==
            AccountSessionState.reauthorizationRequired
        ? AccountOperation.signingIn
        : AccountOperation.refreshing,
    source,
    resolveAccountIssue,
  );
}
