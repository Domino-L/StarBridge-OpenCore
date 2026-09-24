import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'application_support_copy.dart';
import 'application_support_models.dart';
import 'application_support_module.dart';
import 'data_location_copy.dart';

/// Inline diagnostics use the same results/actions as the existing dialog.
/// Opening settings does not start a probe or perform a repair.
class ApplicationSupportPanel extends StatefulWidget {
  const ApplicationSupportPanel({required this.module, super.key});
  final ApplicationSupportModule module;
  @override
  State<ApplicationSupportPanel> createState() =>
      _ApplicationSupportPanelState();
}

class _ApplicationSupportPanelState extends State<ApplicationSupportPanel> {
  bool _requested = false;
  ApplicationSupportSnapshot? _lastSnapshot;
  DateTime? _checkedAt;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<ApplicationSupportProjection>(
    valueListenable: widget.module.projection,
    builder: (context, projection, _) {
      if (!_requested) {
        return StarBridgeSurface(
          role: SurfaceRole.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                applicationSupportCopy(context, 'title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: context.tokens.space.sm),
              Text(applicationSupportCopy(context, 'description')),
              SizedBox(height: context.tokens.space.md),
              FilledButton.icon(
                key: const Key('diagnostics-run'),
                onPressed: () {
                  setState(() => _requested = true);
                  unawaited(widget.module.refresh());
                },
                icon: const StarBridgeIcon(StarBridgeIconSemantic.diagnostics),
                label: Text(applicationSupportCopy(context, 'action.refresh')),
              ),
            ],
          ),
        );
      }
      if (projection.loading) return const _LoadingView();
      if (projection.snapshot case final snapshot?) {
        if (!identical(snapshot, _lastSnapshot)) {
          _lastSnapshot = snapshot;
          _checkedAt = DateTime.now();
        }
        final at = _checkedAt!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReadyView(module: widget.module, snapshot: snapshot),
            Padding(
              padding: EdgeInsets.only(top: context.tokens.space.xs),
              child: Text(
                '${applicationSupportCopy(context, 'checkedAt')} ${MaterialLocalizations.of(context).formatShortDate(at)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: true)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      }
      return _FailureView(
        module: widget.module,
        failure:
            projection.failure ?? ApplicationSupportFailure.inspectionFailed,
      );
    },
  );
}

class ApplicationSupportPage extends StatefulWidget {
  const ApplicationSupportPage({required this.module, super.key});

  final ApplicationSupportModule module;

  @override
  State<ApplicationSupportPage> createState() => _ApplicationSupportPageState();
}

class _ApplicationSupportPageState extends State<ApplicationSupportPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.module.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ValueListenableBuilder<ApplicationSupportProjection>(
      valueListenable: widget.module.projection,
      builder: (context, projection, _) => SingleChildScrollView(
        key: const Key('application-support-page'),
        padding: EdgeInsetsDirectional.fromSTEB(
          tokens.space.xl,
          tokens.space.lg,
          tokens.space.xl,
          tokens.space.xxl,
        ),
        child: Align(
          alignment: AlignmentDirectional.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: tokens.density.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  applicationSupportCopy(context, 'title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SizedBox(height: tokens.space.xs),
                Text(
                  applicationSupportCopy(context, 'description'),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: tokens.colors.textSecondary),
                ),
                SizedBox(height: tokens.space.lg),
                if (projection.loading)
                  const _LoadingView()
                else if (projection.snapshot case final snapshot?)
                  _ReadyView(module: widget.module, snapshot: snapshot)
                else
                  _FailureView(
                    module: widget.module,
                    failure:
                        projection.failure ??
                        ApplicationSupportFailure.inspectionFailed,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => const StarBridgeSurface(
    key: Key('application-support-loading'),
    role: SurfaceRole.panel,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _ReadyView extends StatefulWidget {
  const _ReadyView({required this.module, required this.snapshot});

  final ApplicationSupportModule module;
  final ApplicationSupportSnapshot snapshot;

  @override
  State<_ReadyView> createState() => _ReadyViewState();
}

class _ReadyViewState extends State<_ReadyView> {
  bool _busy = false;
  ApplicationSupportModule get module => widget.module;
  ApplicationSupportSnapshot get snapshot => widget.snapshot;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final summaryKey = snapshot.hasIssues
        ? 'summary.issues'
        : snapshot.hasUnavailableChecks
        ? 'summary.partial'
        : 'summary.healthy';
    final summaryColor = snapshot.hasIssues
        ? tokens.colors.warning
        : snapshot.hasUnavailableChecks
        ? tokens.colors.info
        : tokens.colors.success;
    final rows =
        <(String, String, StarBridgeIconSemantic, ApplicationSupportCheck)>[
          if (snapshot.connection case final connection?)
            (
              'connection',
              'item.connection',
              StarBridgeIconSemantic.connected,
              connection,
            ),
          (
            'data-directory',
            'item.dataDirectory',
            StarBridgeIconSemantic.cache,
            snapshot.dataDirectory,
          ),
          (
            'game-log',
            'item.gameLog',
            StarBridgeIconSemantic.statusGame,
            snapshot.gameLog,
          ),
          (
            'startup',
            'item.startup',
            StarBridgeIconSemantic.generalData,
            snapshot.startup,
          ),
          (
            'installation',
            'item.installation',
            StarBridgeIconSemantic.diagnostics,
            snapshot.installation,
          ),
        ];
    return StarBridgeSurface(
      key: const Key('application-support-ready'),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StarBridgeIcon(
                snapshot.hasIssues
                    ? StarBridgeIconSemantic.warning
                    : StarBridgeIconSemantic.connected,
                color: summaryColor,
                size: tokens.icons.medium,
              ),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Text(
                  applicationSupportCopy(context, summaryKey),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: summaryColor),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space.md),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) Divider(height: tokens.space.lg),
            _SupportRow(
              id: rows[index].$1,
              title: applicationSupportCopy(context, rows[index].$2),
              icon: rows[index].$3,
              check: rows[index].$4,
            ),
          ],
          SizedBox(height: tokens.space.lg),
          Wrap(
            spacing: tokens.space.sm,
            runSpacing: tokens.space.sm,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                key: const Key('application-support-open-data-directory'),
                onPressed:
                    !_busy &&
                        snapshot.dataDirectory.state ==
                            ApplicationSupportCheckState.healthy
                    ? () => _openDataDirectory(context)
                    : null,
                child: Text(
                  applicationSupportCopy(context, 'action.openDataDirectory'),
                ),
              ),
              OutlinedButton(
                key: const Key('application-support-copy'),
                onPressed: _busy ? null : () => _copy(context),
                child: Text(applicationSupportCopy(context, 'action.copy')),
              ),
              FilledButton.icon(
                key: const Key('application-support-refresh'),
                onPressed: _busy ? null : module.refresh,
                icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                label: Text(applicationSupportCopy(context, 'action.refresh')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    final rows = <(String, ApplicationSupportCheck)>[
      if (snapshot.connection case final connection?)
        ('item.connection', connection),
      ('item.dataDirectory', snapshot.dataDirectory),
      ('item.gameLog', snapshot.gameLog),
      ('item.startup', snapshot.startup),
      ('item.installation', snapshot.installation),
    ];
    final summary = StringBuffer('StarBridge · ')
      ..writeln(applicationSupportCopy(context, 'title'));
    for (final row in rows) {
      summary
        ..write(applicationSupportCopy(context, row.$1))
        ..write('：')
        ..write(_stateText(context, row.$2.state))
        ..write(' · ')
        ..writeln(_detailText(context, row.$2));
    }
    var copied = true;
    try {
      await Clipboard.setData(ClipboardData(text: summary.toString().trim()));
    } on Object {
      copied = false;
    }
    if (!context.mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied
              ? applicationSupportCopy(context, 'copied')
              : dataLocationCopy(context, 'copyFailed'),
        ),
      ),
    );
  }

  Future<void> _openDataDirectory(BuildContext context) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await module.openDataDirectory();
    if (!context.mounted) return;
    setState(() => _busy = false);
    final key = switch (result) {
      ApplicationSupportActionResult.completed => 'openedDataDirectory',
      ApplicationSupportActionResult.hostUnavailable =>
        'openDataDirectoryHostUnavailable',
      ApplicationSupportActionResult.failed => 'openDataDirectoryFailed',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(applicationSupportCopy(context, key))),
    );
  }
}

class _SupportRow extends StatelessWidget {
  const _SupportRow({
    required this.id,
    required this.title,
    required this.icon,
    required this.check,
  });

  final String id;
  final String title;
  final StarBridgeIconSemantic icon;
  final ApplicationSupportCheck check;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = switch (check.state) {
      ApplicationSupportCheckState.healthy => tokens.colors.success,
      ApplicationSupportCheckState.actionRequired => tokens.colors.warning,
      ApplicationSupportCheckState.unavailable => tokens.colors.info,
    };
    return Row(
      key: Key('application-support-$id'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StarBridgeIcon(icon, color: color, size: tokens.icons.medium),
        SizedBox(width: tokens.space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: tokens.space.sm,
                runSpacing: tokens.space.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  Text(
                    _stateText(context, check.state),
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: color),
                  ),
                ],
              ),
              SizedBox(height: tokens.space.xxs),
              Text(
                _detailText(context, check),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.module, required this.failure});

  final ApplicationSupportModule module;
  final ApplicationSupportFailure failure;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final key = switch (failure) {
      ApplicationSupportFailure.hostUnavailable => 'error.hostUnavailable',
      ApplicationSupportFailure.timeout => 'error.timeout',
      ApplicationSupportFailure.inspectionFailed => 'error.inspectionFailed',
      ApplicationSupportFailure.invalidResponse => 'error.invalidResponse',
    };
    return StarBridgeSurface(
      key: const Key('application-support-failure'),
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            applicationSupportCopy(context, 'error.title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: tokens.space.xs),
          Text(applicationSupportCopy(context, key)),
          SizedBox(height: tokens.space.md),
          FilledButton.icon(
            onPressed: module.refresh,
            icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
            label: Text(applicationSupportCopy(context, 'action.refresh')),
          ),
        ],
      ),
    );
  }
}

String _stateText(BuildContext context, ApplicationSupportCheckState state) =>
    applicationSupportCopy(context, switch (state) {
      ApplicationSupportCheckState.healthy => 'state.healthy',
      ApplicationSupportCheckState.actionRequired => 'state.actionRequired',
      ApplicationSupportCheckState.unavailable => 'state.unavailable',
    });

String _detailText(BuildContext context, ApplicationSupportCheck check) {
  var text = applicationSupportCopy(context, 'detail.${check.detail}');
  if (check is ApplicationInstallationCheck &&
      (check.otherInstallations > 0 ||
          check.orphanedRegistrations > 0 ||
          check.scanWarnings > 0)) {
    final details = <String>[
      if (check.otherInstallations > 0)
        '${applicationSupportCopy(context, 'count.otherInstallations')} '
            '${check.otherInstallations}',
      if (check.orphanedRegistrations > 0)
        '${applicationSupportCopy(context, 'count.orphanedRegistrations')} '
            '${check.orphanedRegistrations}',
      if (check.scanWarnings > 0)
        '${applicationSupportCopy(context, 'count.scanWarnings')} '
            '${check.scanWarnings}',
    ];
    text = '$text ${details.join('，')}';
  }
  return text;
}
