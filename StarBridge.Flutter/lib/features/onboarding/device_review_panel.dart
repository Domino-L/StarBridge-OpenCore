import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/interaction/starbridge_action_button.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'device_review_controller.dart';
import 'device_review_port.dart';
import 'onboarding_copy.dart';

/// Original settings pages remain the editor; this panel reviews saved values.
class DeviceReviewPanel extends StatefulWidget {
  const DeviceReviewPanel({
    required this.copy,
    this.controller,
    this.enabled = false,
    this.interactionBlocked = false,
    this.onEdit,
    this.onChanged,
    super.key,
  });
  final OnboardingCopy copy;
  final DeviceReviewController? controller;
  final bool enabled;
  final bool interactionBlocked;
  final Future<void> Function(DeviceReviewSection)? onEdit;
  final Future<void> Function()? onChanged;
  @override
  State<DeviceReviewPanel> createState() => _DeviceReviewPanelState();
}

class _DeviceReviewPanelState extends State<DeviceReviewPanel> {
  @override
  void initState() {
    super.initState();
    _readAfterBuild();
  }

  void _readAfterBuild() {
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller == widget.controller) {
        unawaited(controller?.refresh());
      }
    });
  }

  @override
  void didUpdateWidget(DeviceReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        !oldWidget.enabled && widget.enabled) {
      _readAfterBuild();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
    if (mounted) await widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => widget.controller == null
      ? _content(context, const DeviceReviewView())
      : ValueListenableBuilder<DeviceReviewView>(
          valueListenable: widget.controller!,
          builder: (context, view, _) => _content(context, view),
        );
  Widget _content(BuildContext context, DeviceReviewView view) {
    final t = context.tokens;
    final copy = widget.copy;
    final snapshot = view.snapshot;
    final reviewed = snapshot.state == DeviceReviewState.reviewed;
    final status = view.busy
        ? 'busy'
        : view.error
        ? 'error'
        : 'device.state.${snapshot.state.name}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(copy.text('device.intro')),
        SizedBox(height: t.space.md),
        Semantics(
          liveRegion: true,
          child: Text(
            copy.text(status),
            style: TextStyle(
              color: reviewed ? t.colors.success : t.colors.textSecondary,
            ),
          ),
        ),
        SizedBox(height: t.space.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final paired =
                constraints.maxWidth >= 680 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.25;
            final width = paired
                ? (constraints.maxWidth - t.space.lg) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: t.space.lg,
              runSpacing: t.space.lg,
              children: [
                for (final section in DeviceReviewSection.values)
                  SizedBox(
                    width: width,
                    child: _section(context, view, section),
                  ),
              ],
            );
          },
        ),
        SizedBox(height: t.space.lg),
        Text(copy.text('device.separate')),
        SizedBox(height: t.space.md),
        Wrap(
          spacing: t.space.md,
          runSpacing: t.space.sm,
          children: [
            StarBridgeActionButton(
              controlKey: const Key('device-confirm'),
              kind: StarBridgeActionKind.primary,
              onActivate: _tap(
                widget.enabled && !widget.interactionBlocked && view.canConfirm
                    ? () => _run(widget.controller!.confirm)
                    : null,
              ),
              child: Text(copy.text('device.confirm')),
            ),
            StarBridgeActionButton(
              controlKey: const Key('device-refresh'),
              kind: StarBridgeActionKind.quiet,
              onActivate: _tap(
                !widget.interactionBlocked &&
                        !view.busy &&
                        widget.controller != null
                    ? () => _run(widget.controller!.refresh)
                    : null,
              ),
              child: Text(copy.text('retry')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    DeviceReviewView view,
    DeviceReviewSection section,
  ) {
    final t = context.tokens;
    final copy = widget.copy;
    final snapshot = view.snapshot;
    final ready =
        widget.enabled &&
        !widget.interactionBlocked &&
        !view.busy &&
        !view.error;
    final reviewed = snapshot.state == DeviceReviewState.reviewed;
    return Container(
      padding: EdgeInsets.all(t.space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.shape.radiusSmall),
        border: Border.all(color: t.colors.textDisabled.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              copy.text('device.section.${section.name}'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SizedBox(height: t.space.sm),
          if (snapshot.sections[section] case final values?)
            for (final field in values.entries.where(
              (field) => !{
                'startupChoiceMade',
                'closeBehaviorChoiceMade',
                'renderMode',
              }.contains(field.key),
            ))
              Padding(
                padding: EdgeInsets.symmetric(vertical: t.space.xxs),
                child: Text(
                  '${copy.text('device.field.${field.key}')} · ${_value(copy, field.key, field.value, values)}',
                ),
              )
          else
            Text(copy.text('unknown')),
          SizedBox(height: t.space.sm),
          StarBridgeActionButton(
            controlKey: Key('device-edit-${section.name}'),
            kind: StarBridgeActionKind.secondary,
            onActivate: _tap(
              ready && widget.controller != null && widget.onEdit != null
                  ? () => _run(
                      () => widget.controller!.edit(section, widget.onEdit!),
                    )
                  : null,
            ),
            child: Text(copy.text('device.edit')),
          ),
          CheckboxListTile(
            key: Key('device-check-${section.name}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: reviewed || view.checked.contains(section),
            onChanged: ready && snapshot.canReview && !reviewed
                ? (value) => widget.controller!.check(section, value == true)
                : null,
            title: Text(copy.text('device.checked')),
          ),
        ],
      ),
    );
  }

  String _value(
    OnboardingCopy copy,
    String field,
    Object? value,
    Map<String, Object?> values,
  ) {
    if ({'launchAtStartup', 'startMinimized'}.contains(field) &&
            values['startupChoiceMade'] != true ||
        field == 'keepRunningInBackground' &&
            values['closeBehaviorChoiceMade'] != true) {
      return copy.text('unknown');
    }
    if (value is bool) {
      return copy.text(value ? 'device.enabled' : 'device.disabled');
    }
    if (field == 'position' || field == 'preview') {
      return copy.text('device.value.$value');
    }
    if (field == 'opacity') return '${((value! as num) * 100).round()}%';
    if (value is int) return '$value ${copy.text('device.minutes')}';
    return value.toString();
  }
}

/// Native-style tap callback to a suite activation (source unused here).
ValueChanged<InteractionSource>? _tap(VoidCallback? onPressed) =>
    onPressed == null ? null : (_) => onPressed();
