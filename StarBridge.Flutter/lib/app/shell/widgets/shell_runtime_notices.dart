import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../composition/app_composition.dart';
import '../../composition/handle_mismatch_banner.dart';
import '../../composition/official_fleet_rally_banner.dart';
import '../../runtime/example_scene_control.dart';
import '../../presence/manual_presence.dart';
import '../chrome/shell_chrome_projection.dart';
import 'connection_status_notice.dart';
import 'sharing_status_notice.dart';
import 'example_scene_notice.dart';

/// Original runtime summaries only; retry and navigation keep their owners.
List<Widget> shellRuntimeNotices({
  required AppComposition composition,
  required ShellChromeProjection projection,
  required ExampleSceneControl exampleSceneControl,
  required VoidCallback onOpenPrivacy,
  Future<void> Function()? onRetryConnection,
  Future<void> Function()? onHandleMismatch,
}) => [
  if (exampleSceneControl.active)
    ExampleSceneNotice(control: exampleSceneControl),
  if (projection.connectionIssue case final issue?)
    if (issue.action == ConnectionIssueAction.restoreOnline)
      _OnlineRecoveryNotice(
        issue: issue,
        controller: composition.manualPresence?.source.controller,
      )
    else
      ConnectionStatusNotice(
        issue: issue,
        retrying:
            projection.connectionIssueUsesAccountAction &&
            projection.accountBusy,
        onRetry: projection.connectionIssueUsesAccountAction
            ? () async {
                await composition.resolveAccountIssue();
              }
            : onRetryConnection,
      ),
  if (!exampleSceneControl.active &&
      projection.connectionIssue == null &&
      composition.localPrivacy != null)
    SharingStatusNotice(
      status: composition.sharingStatus!,
      onRetry: () => composition.sharingStatus!.canRetry
          ? () => unawaited(composition.sharingStatus!.retry())
          : null,
      onOpenSettings: onOpenPrivacy,
    ),
  if (!exampleSceneControl.active)
    officialFleetRallyBanner(composition),
  if (!exampleSceneControl.active)
    HandleMismatchBanner(
      module: composition.handleMismatch,
      onOpen: onHandleMismatch == null
          ? null
          : () => unawaited(onHandleMismatch()),
    ),
];

// The recovery control observes its own primary command owner. Do not add
// another shell-wide rebuild dependency for a local banner's busy/bind state.
class _OnlineRecoveryNotice extends StatelessWidget {
  const _OnlineRecoveryNotice({required this.issue, required this.controller});
  final ConnectionIssueProjection issue;
  final ManualPresenceController? controller;
  @override
  Widget build(BuildContext context) {
    final control = controller;
    if (control == null) return ConnectionStatusNotice(issue: issue);
    return ListenableBuilder(
      listenable: control,
      builder: (_, _) => ConnectionStatusNotice(
        issue: issue,
        retrying: control.busy,
        onRetry: control.canRestoreOnline
            ? () async {
                await control.restoreOnline();
              }
            : null,
      ),
    );
  }
}
