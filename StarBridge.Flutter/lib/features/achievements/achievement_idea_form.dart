import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'achievement_ideas_port.dart';

class AchievementIdeaForm extends StatefulWidget {
  const AchievementIdeaForm({
    required this.port,
    required this.generation,
    this.onConfirmationCreated,
    super.key,
  });
  final AchievementIdeasPort port;
  final int generation;

  /// Presentation ownership only: the containing page can retire this child
  /// before a pending exit delays disposal of the parent editor.
  final ValueChanged<StarBridgeDialogRoute<bool>>? onConfirmationCreated;
  @override
  State<AchievementIdeaForm> createState() => _AchievementIdeaFormState();
}

class _AchievementIdeaFormState extends State<AchievementIdeaForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _condition = TextEditingController();
  final _confirmations = <StarBridgeDialogRoute<bool>>{};
  String? _image, _status;
  var _id = achievementIdeaSubmissionId();
  bool _busy = false, _picking = false, _sent = false, _closing = false;
  bool get _dirty =>
      !_sent &&
      (_name.text.isNotEmpty || _condition.text.isNotEmpty || _image != null);
  String t(String key) => AppStrings.of(context).text('achievements.idea.$key');
  void _changed() => setState(() {
    _id = achievementIdeaSubmissionId();
    _status = null;
  });

  Future<void> _close() async {
    if (_busy || _closing) return;
    final source = StarBridgeActivationOrigin.sourceOf(context);
    var exitSource = source;
    _closing = true;
    final discard =
        !_dirty ||
        await showStarBridgeDialog<bool>(
              context,
              source: source,
              requestFocus: true,
              traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
              onRouteCreated: (route) {
                _confirmations.add(route);
                widget.onConfirmationCreated?.call(route);
                unawaited(
                  route.completed.then((_) {
                    _confirmations.remove(route);
                  }),
                );
              },
              builder: (context) {
                // This route may outlive its opener for an exit frame. Read
                // labels from its own live context, never a disposed editor.
                String label(String key) =>
                    AppStrings.of(context).text('achievements.idea.$key');
                return Semantics(
                  scopesRoute: true,
                  explicitChildNodes: true,
                  child: SafeArea(
                    child: AlertDialog(
                      title: Text(label('discardTitle')),
                      content: Text(label('discardBody')),
                      actions: [
                        StarBridgeActionButton(
                          controlKey: const Key('achievement-idea-keep'),
                          kind: StarBridgeActionKind.quiet,
                          onActivate: (source) => dismissStarBridgeDialog(
                            context,
                            source: source,
                            result: false,
                          ),
                          child: Text(label('keepEditing')),
                        ),
                        StarBridgeActionButton(
                          controlKey: const Key('achievement-idea-discard'),
                          kind: StarBridgeActionKind.primary,
                          onActivate: (source) {
                            exitSource = source;
                            dismissStarBridgeDialog(
                              context,
                              source: source,
                              result: true,
                            );
                          },
                          child: Text(label('discard')),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ) ==
            true;
    _closing = false;
    if (mounted && discard) {
      setState(() => _sent = true);
      dismissStarBridgeDialog(context, source: exitSource);
    }
  }

  Future<void> _pick() async {
    if (_busy || _sent) return;
    setState(() {
      _busy = true;
      _picking = true;
      _status = null;
    });
    try {
      final image = await widget.port.pickImage(generation: widget.generation);
      if (mounted && image != null) {
        _image = image;
        _changed();
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'imageFailed');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _picking = false;
        });
      }
    }
  }

  Future<void> _send() async {
    if (_busy || _sent || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await widget.port.submit(
        generation: widget.generation,
        submissionId: _id,
        name: _name.text.trim(),
        condition: _condition.text.trim(),
        imageData: _image,
      );
      if (mounted) {
        setState(() {
          _sent = true;
          _status = 'sent';
          _image = null;
          _name.clear();
          _condition.clear();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error is AchievementIdeaFailure
              ? error.code
              : 'unconfirmed',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final route in _confirmations.toList(growable: false)) {
      retireStarBridgeDialog(route, includeClosing: true);
    }
    _confirmations.clear();
    _name.dispose();
    _condition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && (!_dirty || _sent),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('title'), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(t('intro')),
                const SizedBox(height: 10),
                Text(
                  t('identity'),
                  style: TextStyle(color: context.tokens.colors.textSecondary),
                ),
                const SizedBox(height: 20),
                StarBridgeFieldFrame(
                  enabled: !_busy && !_sent,
                  followNativeError: true,
                  builder: (_, focus) => TextFormField(
                    key: const Key('achievement-idea-name'),
                    focusNode: focus,
                    controller: _name,
                    enabled: !_busy && !_sent,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: t('name'),
                      errorMaxLines: 3,
                    ),
                    onChanged: (_) => _changed(),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? t('nameRequired')
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                StarBridgeFieldFrame(
                  enabled: !_busy && !_sent,
                  followNativeError: true,
                  builder: (_, focus) => TextFormField(
                    key: const Key('achievement-idea-condition'),
                    focusNode: focus,
                    controller: _condition,
                    enabled: !_busy && !_sent,
                    maxLength: 2000,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: t('condition'),
                      errorMaxLines: 3,
                    ),
                    onChanged: (_) => _changed(),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? t('conditionRequired')
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t('imageHint'),
                  style: TextStyle(color: context.tokens.colors.textSecondary),
                ),
                if (_image != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(_image!.split(',').last),
                      height: 144,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Text(t('imageFailed')),
                    ),
                  ),
                ],
                if (!_sent)
                  Wrap(
                    spacing: 8,
                    children: [
                      StarBridgeActionButton(
                        controlKey: const Key('achievement-idea-image'),
                        onActivate: !_busy && widget.port.canPickImage
                            ? (_) => _pick()
                            : null,
                        child: Text(
                          t(
                            _picking
                                ? 'pickingImage'
                                : _image == null
                                ? 'addImage'
                                : 'replaceImage',
                          ),
                        ),
                      ),
                      if (_image != null)
                        StarBridgeActionButton(
                          controlKey: const Key(
                            'achievement-idea-remove-image',
                          ),
                          kind: StarBridgeActionKind.quiet,
                          onActivate: _busy
                              ? null
                              : (_) {
                                  _image = null;
                                  _changed();
                                },
                          child: Text(t('removeImage')),
                        ),
                    ],
                  ),
                if (!widget.port.available)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(t('unavailable')),
                  ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        t(_status!),
                        key: const Key('achievement-idea-status'),
                        style: TextStyle(
                          color: _sent
                              ? context.tokens.colors.success
                              : context.tokens.colors.warning,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StarBridgeActionButton(
                      controlKey: const Key('achievement-idea-close'),
                      kind: StarBridgeActionKind.quiet,
                      onActivate: _busy ? null : (_) => _close(),
                      child: Text(t('close')),
                    ),
                    if (!_sent)
                      StarBridgeActionButton(
                        controlKey: const Key('achievement-idea-submit'),
                        kind: StarBridgeActionKind.primary,
                        onActivate: _busy || !widget.port.available
                            ? null
                            : (_) => _send(),
                        child: Text(
                          t(_busy && !_picking ? 'sending' : 'submit'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
