import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../app/localization/app_strings.dart';
import '../game_log/local_game_log_setup_panel.dart';
import '../onboarding/bridge_onboarding_adapter.dart';
import '../onboarding/bridge_online_installation_adapter.dart';
import '../onboarding/bridge_online_review_adapter.dart';
import '../onboarding/first_use_setup_entry.dart';
import '../onboarding/onboarding_models.dart';
import '../onboarding/online_review_controller.dart';
import 'usage_mode_controller.dart';
import 'usage_mode_copy.dart';
import 'usage_mode_page.dart';

Future<void> openUsageModeSettings(
  BuildContext context,
  BridgeClientSession session, {
  Future<void> Function()? onModeChanged,
}) async {
  final port = BridgeOnboardingAdapter(session);
  OnboardingReply? initial;
  try {
    initial = await port.read();
  } on Object {
    /* The page owns retry UI. */
  }
  if (!context.mounted) return;
  final continueSetup = FirstUseSetupEntry.of(context);
  if (initial != null && !initial.canUseUsageMode && continueSetup != null) {
    await continueSetup(context);
    return;
  }
  final reviewPort = BridgeOnlineReviewAdapter(session);
  final installation = BridgeOnlineInstallationAdapter(session);
  // No automatic account-only install when signing in. Installation is step 4.
  final review = OnlineReviewController(reviewPort);
  final controller = UsageModeController(
    port,
    review,
    installation,
    onModeChanged: onModeChanged,
  );
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/settings/usage-mode'),
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              usageModeText(Localizations.localeOf(context), 'title'),
            ),
          ),
          body: UsageModePage(
            controller: controller,
            openSetup: () async =>
                FirstUseSetupEntry.of(context)?.call(context),
            logPanel: (confirmed) => LocalGameLogSetupPanel(
              session: session,
              allowOnlineSetup: true,
              onConfirmed: confirmed,
            ),
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
    // Keep the original adapter alive until its submitted request has consumed
    // the Host's next-generation observation and reconciled the main window.
    await controller.settled;
    review.dispose();
    installation.dispose();
  }
}

/// The "Confirm game identity again" entry of the gameplay panel and the game
/// log page: Usage mode shows the installed account's identity review; once
/// it closes, the caller reads the recording state again.
Future<void> openGameIdentityReview(
  BuildContext context,
  BridgeClientSession session, {
  Future<void> Function()? onModeChanged,
  Future<void> Function()? afterReview,
}) async {
  await openUsageModeSettings(context, session, onModeChanged: onModeChanged);
  await afterReview?.call();
}

/// Host startup classification or a historical receipt selects one entry.
class UsageModeSettingsEntry extends StatefulWidget {
  const UsageModeSettingsEntry({
    required this.session,
    this.onModeChanged,
    super.key,
  });
  final BridgeClientSession session;
  final Future<void> Function()? onModeChanged;
  @override
  State<UsageModeSettingsEntry> createState() => _UsageModeSettingsEntryState();
}

class _UsageModeSettingsEntryState extends State<UsageModeSettingsEntry> {
  late final _port = BridgeOnboardingAdapter(widget.session);
  OnboardingReply? _reply;
  bool _wasCurrent = true;
  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current && !_wasCurrent) unawaited(_read());
    _wasCurrent = current;
  }

  Future<void> _read() async {
    try {
      final reply = await _port.read();
      if (mounted) setState(() => _reply = reply);
    } on Object {
      /* Unknown completion exposes neither entry. */
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reply == null) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context);
    final completed = _reply!.canUseUsageMode;
    final setup = FirstUseSetupEntry.of(context);
    return ListTile(
      key: Key(completed ? 'settings-usage-mode' : 'settings-first-use'),
      title: Text(
        completed
            ? usageModeText(locale, 'title')
            : AppStrings.of(context).text('settings.firstUse'),
      ),
      subtitle: completed ? Text(usageModeText(locale, 'description')) : null,
      onTap: () async {
        if (completed) {
          await openUsageModeSettings(
            context,
            widget.session,
            onModeChanged: widget.onModeChanged,
          );
        } else {
          await setup?.call(context);
        }
        await _read();
      },
    );
  }
}
