import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../onboarding/onboarding_copy.dart';
import '../onboarding/online_review_panel.dart';
import 'usage_mode_controller.dart';
import 'usage_mode_copy.dart';

class UsageModePage extends StatefulWidget {
  const UsageModePage({
    required this.controller,
    required this.logPanel,
    this.openSetup,
    super.key,
  });
  final UsageModeController controller;
  final Widget Function(Future<void> Function()) logPanel;
  final Future<void> Function()? openSetup;
  @override
  State<UsageModePage> createState() => _UsageModePageState();
}

class _UsageModePageState extends State<UsageModePage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
  }

  Future<void> _local() async {
    final locale = Localizations.localeOf(context);
    String text(String key) => usageModeText(locale, key);
    final confirmed = await showStarBridgeDialog<bool>(
      context,
      source: StarBridgeActivationOrigin.sourceOf(context),
      builder: (context) => AlertDialog(
        title: Text(text('toLocal')),
        content: Text(text('confirmLocal')),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.secondary,
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: false),
            child: Text(text('cancel')),
          ),
          StarBridgeActionButton(
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: true),
            child: Text(text('switch')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await widget.controller.enterLocal();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, locale = Localizations.localeOf(context);
    final copy = OnboardingCopy(locale);
    String text(String key) => usageModeText(locale, key);
    Widget button(String key, String label, Future<void> Function() work) =>
        StarBridgeActionButton(
          controlKey: Key(key),
          onActivate: c.busy ? null : (_) => unawaited(work()),
          child: Text(label),
        );
    return AnimatedBuilder(
      animation: Listenable.merge([c, c.review]),
      builder: (context, _) => ListView(
        padding: EdgeInsets.all(context.tokens.space.lg),
        children: [
          Text(text('title'), style: Theme.of(context).textTheme.headlineSmall),
          if (c.reply != null && !c.completed)
            button(
              'usage-mode-continue-setup',
              copy.text('entry'),
              widget.openSetup ?? () async {},
            ),
          if (c.completed && c.recoveryRequired) ...[
            Text(copy.text('onlineRestore.recovery')),
            if (c.failure case final failure?) ...[
              Text(text('failure.${failure.kind}')),
            ],
            button('usage-mode-recover-local', text('toLocal'), c.cancel),
            button(
              'usage-mode-retry',
              copy.text('onlineRestore.recheck'),
              c.refresh,
            ),
          ],
          if (c.completed && c.modeKnown && !c.recoveryRequired) ...[
            Text(
              text(c.online ? 'currentOnline' : 'currentLocal'),
              key: const Key('usage-mode-current'),
            ),
            Text(copy.text('localDescription')),
            Text(copy.text('onlineDescription')),
            if (c.switched) Text(text('switched')),
            const SizedBox(height: 16),
            if (c.online) ...[
              // The installed account's identity review, the same panel the
              // guide uses: check, then confirm the Handle.
              if (c.installedIdentityReview) ...[
                OnlineReviewPanel(
                  key: const ValueKey('usage-mode-installed-review'),
                  controller: c.review,
                  copy: copy,
                  enabled: !c.busy,
                  onChanged: c.installedIdentityChanged,
                ),
                const SizedBox(height: 16),
              ],
              button('usage-mode-to-local', text('toLocal'), _local),
            ] else if (c.step == null)
              button('usage-mode-to-online', text('toOnline'), c.begin)
            else ...[
              // Keep the full sequence visible while presenting only the
              // current step's existing domain panel.
              for (final step in UsageModeStep.values)
                Text(
                  '${step.index + 1}. ${switch (step) {
                    UsageModeStep.login => copy.text('online'),
                    UsageModeStep.log => copy.text('step.log'),
                    UsageModeStep.names => text('checkNames'),
                    UsageModeStep.installation => text('enableOnline'),
                  }}',
                  style: step == c.step
                      ? Theme.of(context).textTheme.titleMedium
                      : null,
                ),
              const SizedBox(height: 16),
              switch (c.step!) {
                UsageModeStep.login => OnlineReviewPanel(
                  key: const ValueKey('usage-mode-login'),
                  controller: c.review,
                  copy: copy,
                  enabled: !c.busy,
                  accountCard: true,
                  retainedAccountCard: true,
                  onContinue: c.accountConfirmed,
                ),
                UsageModeStep.log => widget.logPanel(c.logConfirmed),
                UsageModeStep.names => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(copy.text('logReady')),
                    if (c.reply?.facts.version case final version?)
                      Text(version),
                    OnlineReviewPanel(
                      key: const ValueKey('usage-mode-names'),
                      accountCard: true,
                      retainedAccountCard: true,
                      controller: c.review,
                      copy: copy,
                      enabled: !c.busy,
                      autoReview: true,
                      onChanged: c.namesConfirmed,
                    ),
                  ],
                ),
                UsageModeStep.installation => button(
                  'usage-mode-install',
                  text('enableOnline'),
                  c.install,
                ),
              },
              const SizedBox(height: 16),
              button('usage-mode-cancel', text('cancelSwitch'), c.cancel),
            ],
          ],
          if (c.busy) Text(copy.text('busy')),
          if (c.failed && !c.recoveryRequired) ...[
            Text(
              copy.text(c.failure != null ? 'onlineRestore.local' : 'error'),
            ),
            if (c.failure case final failure?) ...[
              Text(text('failure.${failure.kind}')),
            ],
          ],
          if (!c.recoveryRequired && (c.failed || c.reply == null))
            button('usage-mode-retry', copy.text('retry'), c.refresh),
        ],
      ),
    );
  }
}
