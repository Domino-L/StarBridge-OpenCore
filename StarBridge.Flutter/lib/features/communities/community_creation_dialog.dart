import '../../design_system/icons/standard_icon.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'community_creation_controller.dart';
import 'community_creation_copy.dart';
import 'community_creation_port.dart';
import 'community_logo_crop.dart';
import 'community_logo_port.dart';
import 'community_tag_picker.dart';

class CommunityCreationDialog extends StatefulWidget {
  const CommunityCreationDialog({
    required this.port,
    required this.invalidations,
    this.example = false,
    super.key,
  });
  final CommunityCreationPort port;
  final Stream<void> invalidations;
  final bool example;
  @override
  State<CommunityCreationDialog> createState() =>
      _CommunityCreationDialogState();
}

class _CommunityCreationDialogState extends State<CommunityCreationDialog> {
  late final CommunityCreationController model = CommunityCreationController(
    widget.port,
    widget.invalidations,
  );
  final _form = GlobalKey<FormState>();
  final _dialogs = <Route<dynamic>>[];
  bool choosingImage = false, imageFailed = false, confirming = false;
  bool get busy => model.locked || choosingImage;
  CommunityLogoPort? get images => widget.port is CommunityLogoPort
      ? widget.port as CommunityLogoPort
      : null;
  String t(String key) => creationText(context, key);

  @override
  void initState() {
    super.initState();
    model.addListener(changed);
    unawaited(model.load());
  }

  void changed() {
    if (!mounted) return;
    if (model.invalidated) {
      for (final route in _dialogs.toList().reversed) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
      final route = ModalRoute.of(context);
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
      return;
    }
    setState(() {});
  }

  Future<T?> dialog<T>(Widget child) async {
    final route = DialogRoute<T>(
      context: context,
      barrierDismissible: false,
      builder: (_) => child,
    );
    _dialogs.add(route);
    try {
      return await Navigator.of(context).push(route);
    } finally {
      _dialogs.remove(route);
    }
  }

  Future<void> leave() async {
    if (confirming || choosingImage || model.submitting) return;
    if (model.outcome?.status == 'unknown') {
      Navigator.pop(context, model.outcome);
      return;
    }
    if (model.dirty) {
      confirming = true;
      final discard = await dialog<bool>(
        AlertDialog(
          title: Text(t('leaveTitle')),
          content: Text(t('leaveBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('continue')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('discard')),
            ),
          ],
        ),
      );
      confirming = false;
      if (!mounted || discard != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> submit() async {
    if (busy || confirming || !_form.currentState!.validate()) return;
    confirming = true;
    final confirmed = await dialog<bool>(
      AlertDialog(
        title: Text(t('title')),
        content: Text('${model.draft!['name']}\n\n${t('confirmBody')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('continue')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('title')),
          ),
        ],
      ),
    );
    confirming = false;
    if (!mounted || model.invalidated || confirmed != true) return;
    await model.submit();
    if (mounted && model.outcome?.status == 'accepted') {
      Navigator.pop(context, model.outcome);
    }
  }

  Future<void> pickLogo() async {
    final port = images;
    if (busy || port == null || !port.canPickLogo) return;
    setState(() {
      choosingImage = true;
      imageFailed = false;
    });
    try {
      final source = await port.pickLogo();
      if (!mounted || model.invalidated || source == null) return;
      final cropped = await dialog<String>(
        CommunityLogoCrop(port: port, source: source),
      );
      if (mounted && !model.invalidated && cropped != null) {
        model.update('logoImageData', cropped);
      }
    } catch (_) {
      if (mounted) setState(() => imageFailed = true);
    } finally {
      if (!model.invalidated) {
        try {
          await port.clearLogo();
        } catch (_) {
          /* Invalidation also clears the native buffer. */
        }
      }
      if (mounted) setState(() => choosingImage = false);
    }
  }

  Future<void> chooseTags() async {
    final tags = await dialog<List<String>>(
      CommunityTagPicker(
        options: model.options!,
        selected: List<String>.from(model.draft!['tagIds'] as List),
      ),
    );
    if (mounted && tags != null) model.update('tagIds', tags);
  }

  @override
  void dispose() {
    model.removeListener(changed);
    model.dispose();
    super.dispose();
  }

  Widget field(
    String key, {
    String? label,
    String? hint,
    int max = 32,
    int lines = 1,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('create-$key'),
      initialValue: model.draft![key] as String,
      enabled: !busy,
      maxLength: max,
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: t(label ?? key),
        helperText: hint == null ? null : t(hint),
        helperMaxLines: 3,
      ),
      onChanged: (value) => model.update(key, value),
      validator: required
          ? (value) =>
                value == null || value.trim().isEmpty ? t('required') : null
          : null,
    ),
  );

  Widget logo() {
    final value = model.draft!['logoImageData'] as String?;
    Widget preview = const StandardIcon(StandardIconSemantic.groups, size: 44);
    if (value != null) {
      try {
        preview = Image.memory(
          base64Decode(value.split(',').last),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const StandardIcon(StandardIconSemantic.brokenImage),
        );
      } catch (_) {
        /* Preserve the draft; report on submit. */
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('logo'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 80, height: 80, child: preview),
            OutlinedButton(
              onPressed: busy || images?.canPickLogo != true ? null : pickLogo,
              child: Text(t('pickLogo')),
            ),
            if (value != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () => model.update('logoImageData', null),
                child: Text(t('removeLogo')),
              ),
          ],
        ),
        Text(
          t(
            widget.example
                ? 'exampleHint'
                : images?.canPickLogo == true
                ? 'imageHint'
                : 'imageUnavailable',
          ),
        ),
        if (imageFailed)
          Text(
            t('imageFailed'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(leave());
    },
    child: Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 850),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: model.loading
                    ? const Center(child: CircularProgressIndicator())
                    : model.options == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t('optionsUnavailable')),
                            TextButton(
                              onPressed: model.load,
                              child: Text(t('retry')),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              logo(),
                              field('name', hint: 'nameHint', required: true),
                              field(
                                'code',
                                hint: 'codeHint',
                                max: 10,
                                required: true,
                              ),
                              field('description', max: 500, lines: 3),
                              Text(
                                t('tags'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final tag in model.options!.tags.where(
                                    (tag) => (model.draft!['tagIds'] as List)
                                        .contains(tag.id),
                                  ))
                                    Chip(label: Text(tag.name)),
                                  OutlinedButton(
                                    onPressed: busy ? null : chooseTags,
                                    child: Text(t('chooseTags')),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              FormField<List<String>>(
                                validator: (_) =>
                                    (model.draft!['activeSystemIds'] as List)
                                        .isEmpty
                                    ? t('systemRequired')
                                    : null,
                                builder: (state) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t('systems'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final system in [
                                          'stanton',
                                          'pyro',
                                          'nyx',
                                        ])
                                          FilterChip(
                                            label: Text(
                                              '${system[0].toUpperCase()}${system.substring(1)}',
                                            ),
                                            selected:
                                                (model.draft!['activeSystemIds']
                                                        as List)
                                                    .contains(system),
                                            onSelected: busy
                                                ? null
                                                : (selected) {
                                                    final values =
                                                        List<String>.from(
                                                          model.draft!['activeSystemIds']
                                                              as List,
                                                        );
                                                    selected
                                                        ? values.add(system)
                                                        : values.remove(system);
                                                    model.update(
                                                      'activeSystemIds',
                                                      values,
                                                    );
                                                    state.didChange(values);
                                                  },
                                          ),
                                      ],
                                    ),
                                    if (state.hasError)
                                      Text(
                                        state.errorText!,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                initialValue:
                                    model.draft!['joinPolicy'] as String,
                                decoration: InputDecoration(
                                  labelText: t('joinPolicy'),
                                ),
                                isExpanded: true,
                                items: [
                                  for (final mode in [
                                    'Open',
                                    'Approval',
                                    'Invite',
                                  ])
                                    DropdownMenuItem(
                                      value: mode,
                                      child: Text(t(mode)),
                                    ),
                                ],
                                onChanged: busy
                                    ? null
                                    : (value) =>
                                          model.update('joinPolicy', value),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                t('activity'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: field(
                                      'activeFrom',
                                      label: 'from',
                                      max: 5,
                                      required: true,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: field(
                                      'activeTo',
                                      label: 'to',
                                      max: 5,
                                      required: true,
                                    ),
                                  ),
                                ],
                              ),
                              Text(t('overnight')),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue:
                                    model.draft!['timeZoneId'] as String,
                                decoration: InputDecoration(
                                  labelText: t('zone'),
                                ),
                                isExpanded: true,
                                items: [
                                  for (final zone in model.options!.timeZones)
                                    DropdownMenuItem(
                                      value: zone.id,
                                      child: Text(
                                        zone.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: busy
                                    ? null
                                    : (value) =>
                                          model.update('timeZoneId', value),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              if (model.submitting || choosingImage && _dialogs.isEmpty)
                const LinearProgressIndicator(),
              if (model.outcome != null && model.outcome!.status != 'accepted')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    t(
                      model.outcome?.status == 'unknown'
                          ? 'outcomeUnknown'
                          : model.error ?? 'rejected',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              OverflowBar(
                spacing: 8,
                overflowSpacing: 8,
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: model.submitting || choosingImage ? null : leave,
                    child: Text(
                      t(
                        model.outcome?.status == 'unknown'
                            ? 'checkMine'
                            : 'cancel',
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: busy || model.options == null ? null : submit,
                    child: Text(t(model.submitting ? 'creating' : 'title')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
