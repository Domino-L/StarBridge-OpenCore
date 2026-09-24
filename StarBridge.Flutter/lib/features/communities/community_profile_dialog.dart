import '../../design_system/icons/standard_icon.dart';
import 'dart:async';

import 'community_profile_form_sections.dart';

import 'community_visible_refresh.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_profile_controller.dart';
import 'community_profile_port.dart';
import 'community_profile_copy.dart';
import 'community_creation_port.dart';
import 'community_logo_port.dart';
import 'community_logo_crop.dart';
import 'community_tag_picker.dart';
import 'community_gameplay_tags.dart';
import 'community_workspace_copy.dart' show workspaceDays;
import 'community_workspace_port.dart';
import 'communities_module.dart';
import 'community_editor_surface.dart';

class CommunityProfileDialog extends StatefulWidget {
  const CommunityProfileDialog({
    required this.port,
    required this.targetRef,
    this.logoBytes,
    this.embedded = false,
    this.onSaved,
    this.onNameConfirmed,
    this.sectionIndex,
    this.onSectionChanged,
    super.key,
  });
  final CommunityProfilePort port;
  final String targetRef;
  final Uint8List? logoBytes;
  final bool embedded;
  final ValueChanged<Set<String>>? onSaved;
  final void Function(String code, String name)? onNameConfirmed;

  /// The settings rail controls profile sections without replacing this draft.
  final int? sectionIndex;
  final ValueChanged<int>? onSectionChanged;
  @override
  State<CommunityProfileDialog> createState() => CommunityProfileDialogState();
}

class CommunityProfileDialogState extends State<CommunityProfileDialog>
    with CommunityVisibleRefresh<CommunityProfileDialog> {
  @override
  Future<void> refreshVisibleCommunity() => model.refreshLease();
  @override
  Duration get communityRefreshInterval => const Duration(minutes: 2);
  late final model = CommunityProfileController(widget.port, widget.targetRef);
  final form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _anchors = List.generate(4, (_) => GlobalKey());
  bool _scrollUpdateQueued = false;
  bool _initialScrollDone = false;
  final dialogs = <Route<dynamic>>[];
  CommunityCreationOptions? options;
  CommunityEditingProfile? baseline;
  int section = 0, serial = 0;
  bool choosing = false,
      confirming = false,
      optionsFailed = false,
      saved = false;
  String? localError;
  String? draftLogoData;
  Uint8List? draftLogoBytes;
  Uint8List? serverLogoBytes;
  int logoEpoch = 0;
  bool logoLoading = false, logoFailed = false;
  bool get busy => model.locked || choosing || confirming;
  String t(String key) => profileText(context, key);
  Map<String, Object?> get fields => model.fields;
  CommunityLogoPort? get images => widget.port is CommunityLogoPort
      ? widget.port as CommunityLogoPort
      : null;
  @override
  void initState() {
    super.initState();
    section = widget.sectionIndex ?? 0;
    _scroll.addListener(_queueScrollSectionUpdate);
    serverLogoBytes = widget.logoBytes;
    model.addListener(changed);
    unawaited(model.load());
    unawaited(loadOptions());
  }

  @override
  void didUpdateWidget(covariant CommunityProfileDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sectionIndex != null &&
        oldWidget.sectionIndex != widget.sectionIndex) {
      if (section != widget.sectionIndex) {
        scrollToSection(widget.sectionIndex!);
      }
    }
  }

  /// Embedded profile categories are anchors in one form, not separate pages.
  void scrollToSection(int index) {
    section = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _anchors[index].currentContext?.findRenderObject();
      if (target == null) return;
      final offset = RenderAbstractViewport.of(target)
          .getOffsetToReveal(target, 0)
          .offset;
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
      _publishSection(index);
    });
  }

  void _publishSection(int index) {
    if (!mounted || !widget.embedded) return;
    section = index;
    widget.onSectionChanged?.call(index);
  }

  void _queueScrollSectionUpdate() {
    if (_scrollUpdateQueued || !widget.embedded) return;
    _scrollUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollUpdateQueued = false;
      if (!mounted || !_scroll.hasClients) return;
      var active = 0;
      for (var i = 0; i < _anchors.length; i++) {
        final target = _anchors[i].currentContext?.findRenderObject();
        if (target == null) continue;
        final offset = RenderAbstractViewport.of(target)
            .getOffsetToReveal(target, 0)
            .offset;
        if (offset <= _scroll.offset + 32) active = i;
      }
      if (_scroll.position.maxScrollExtent > 0 &&
          _scroll.offset >= _scroll.position.maxScrollExtent - 1 &&
          _anchors[3].currentContext != null) {
        active = 3;
      }
      if (active != section) _publishSection(active);
    });
  }

  Future<void> loadOptions() async {
    if (widget.port is! CommunityCreationPort) return;
    try {
      final result = await (widget.port as CommunityCreationPort)
          .creationOptions();
      if (mounted && !model.invalidated) {
        setState(() {
          options = result;
          optionsFailed = false;
        });
      }
    } catch (_) {
      if (mounted && !model.invalidated) setState(() => optionsFailed = true);
    }
  }

  void changed() {
    if (!mounted) return;
    if (model.invalidated) {
      for (final route in dialogs.toList().reversed) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
      if (!widget.embedded) {
        final route = ModalRoute.of(context);
        if (route?.isActive == true) route!.navigator?.removeRoute(route);
      } else {
        setState(() {});
      }
      return;
    }
    if (baseline != model.profile) {
      final old = baseline;
      baseline = model.profile;
      if (old == null ||
          baseline == null ||
          !communityProfileEqual(old.fields, baseline!.fields)) {
        serial++;
      }
      if (baseline != null &&
          (old == null ||
              old.revision != baseline!.revision ||
              old.hasLogo != baseline!.hasLogo)) {
        unawaited(refreshLogo(baseline!));
      }
    }
    final data = model.changes['logoImageData'] as String?;
    if (data != draftLogoData) {
      draftLogoData = data;
      draftLogoBytes = data == null ? null : base64Decode(data.split(',').last);
    }
    setState(() {});
  }

  Future<void> refreshLogo(CommunityEditingProfile profile) async {
    final current = ++logoEpoch;
    serverLogoBytes = null;
    logoLoading = false;
    logoFailed = false;
    if (!profile.hasLogo || widget.port is! CommunityWorkspacePort) return;
    logoLoading = true;
    void checkCurrent() {
      if (!mounted ||
          model.invalidated ||
          model.profile != profile ||
          current != logoEpoch) {
        throw StateError('Stale profile image');
      }
    }

    try {
      final bytes = await assembleCommunityMedia(
        (offset, version) => (widget.port as CommunityWorkspacePort).readMedia(
          profile.targetRef,
          'logo',
          offset: offset,
          version: version,
        ),
        'logo',
        checkCurrent: checkCurrent,
      );
      checkCurrent();
      setState(() => serverLogoBytes = bytes);
    } catch (failure) {
      if (!mounted ||
          model.invalidated ||
          model.profile != profile ||
          current != logoEpoch) {
        return;
      }
      if (failure is CommunityFailure &&
          const {'notAllowed', 'identityUnavailable'}.contains(failure.code)) {
        model.invalidate(failure.code);
      } else {
        setState(() {
          localError = 'imageFailed';
          logoFailed = true;
        });
      }
    } finally {
      if (mounted && current == logoEpoch) setState(() => logoLoading = false);
    }
  }

  Future<T?> dialog<T>(Widget child) async {
    final route = DialogRoute<T>(
      context: context,
      barrierDismissible: false,
      builder: (_) => child,
    );
    dialogs.add(route);
    try {
      return await Navigator.of(context).push(route);
    } finally {
      dialogs.remove(route);
    }
  }

  Future<bool> confirm(String title, String body, String action) async {
    final result = await dialog<bool>(
      AlertDialog(
        title: Text(t(title)),
        content: Text(t(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('continue')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t(action)),
          ),
        ],
      ),
    );
    return mounted && !model.invalidated && result == true;
  }

  Future<bool> confirmLeave() async {
    if (choosing || confirming || model.submitting) return false;
    if (model.invalidated) return true;
    if (model.dirty) {
      confirming = true;
      final choice = await dialog<String>(
        AlertDialog(
          title: Text(t('leaveTitle')),
          content: Text(
            t(
              model.needsRefresh
                  ? model.error ?? 'outcomeUnknown'
                  : 'leaveBody',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'stay'),
              child: Text(t('continue')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: Text(t('discard')),
            ),
            if (!model.needsRefresh)
              FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: Text(t('save')),
              ),
          ],
        ),
      );
      confirming = false;
      if (!mounted || model.invalidated || choice == null || choice == 'stay') {
        return false;
      }
      if (choice == 'save') {
        await save();
        if (!mounted || model.dirty) return false;
      }
    }
    return mounted;
  }

  Future<void> leave() async {
    if (await confirmLeave() && mounted && !widget.embedded) {
      Navigator.pop(context, saved);
    }
  }

  Future<void> reload() async {
    if (choosing || confirming || model.submitting || model.loading) return;
    if (model.dirty) {
      confirming = true;
      final yes = await confirm('reloadTitle', 'reloadBody', 'reload');
      confirming = false;
      if (!yes) return;
    }
    localError = null;
    await model.load(discardChanges: true);
  }

  Future<void> discard() async {
    if (busy || !model.dirty) return;
    confirming = true;
    final yes = await confirm('reloadTitle', 'leaveBody', 'discard');
    confirming = false;
    if (yes) {
      serial++;
      localError = null;
      model.discard();
    }
  }

  List<Map<String, Object?>> rows(String field) =>
      (fields[field] as List? ?? [])
          .map((v) => Map<String, Object?>.from(v as Map))
          .toList();
  void update(String field, Object? value) {
    localError = null;
    model.update(field, value);
    if (field == 'activityWindows') {
      final windows = rows('activityWindows');
      model.update(
        'activeTime',
        windows
            .map(
              (row) =>
                  '${workspaceDays(context, (row['days'] as List).cast<String>())} ${row['startTime']}–${row['endTime']}${row['endsNextDay'] == true ? ' (${t('nextDay')})' : ''}',
            )
            .join('; '),
      );
      model.update('activeDaysDescription', '');
    }
  }

  Future<void> save() async {
    if (busy || !model.canSave) return;
    if (!(form.currentState?.validate() ?? false)) {
      if (widget.embedded) {
        // All fields are mounted. Bring the first invalid chapter into view.
        for (var i = 0; i < _anchors.length; i++) {
          var invalid = false;
          void inspect(Element element) {
            if (element is StatefulElement &&
                element.state is FormFieldState &&
                (element.state as FormFieldState).hasError) {
              invalid = true;
            }
            element.visitChildren(inspect);
          }

          (_anchors[i].currentContext as Element?)?.visitChildren(inspect);
          if (invalid) {
            scrollToSection(i);
            break;
          }
        }
      }
      return;
    }
    if (model.changes.containsKey('activeSystemIds') &&
        (fields['activeSystemIds'] as List).isEmpty) {
      setState(() {
        localError = 'systemsRequired';
        section = 2;
      });
      widget.onSectionChanged?.call(section);
      if (widget.embedded) scrollToSection(section);
      return;
    }
    if (model.changes.containsKey('activityWindows')) {
      final clock = RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$');
      if (rows('activityWindows').any(
        (r) =>
            (r['days'] as List).isEmpty ||
            !clock.hasMatch(r['startTime'] as String) ||
            !clock.hasMatch(r['endTime'] as String),
      )) {
        setState(() {
          localError = 'daysRequired';
          section = 2;
        });
        widget.onSectionChanged?.call(section);
        if (widget.embedded) scrollToSection(section);
        return;
      }
    }
    final contacts = rows('externalContacts');
    if (model.changes.containsKey('externalContacts') &&
        contacts.any(
          (r) =>
              (r['platform'] as String).trim().isEmpty ||
              (r['value'] as String).trim().isEmpty,
        )) {
      setState(() {
        localError = 'required';
        section = 3;
      });
      widget.onSectionChanged?.call(section);
      if (widget.embedded) scrollToSection(section);
      return;
    }
    // WPF's Empty -> Public rule is explicit here. Existing private contacts
    // remain private until the separate publication confirmation is accepted.
    if (model.changes.containsKey('externalContacts')) {
      if (contacts.isEmpty) {
        model.update('publicShowExternalContacts', false);
      } else if ((model.profile!.fields['externalContacts'] as List).isEmpty &&
          fields['publicShowExternalContacts'] != true) {
        confirming = true;
        final yes = await confirm(
          'publishContacts',
          'publishBody',
          'publishContacts',
        );
        confirming = false;
        if (!yes) return;
        model.update('publicShowExternalContacts', true);
      }
    }
    final changedFields = model.changes.keys.toSet();
    await model.save();
    if (mounted && model.outcome?.status == 'accepted') {
      saved = true;
      if (changedFields.contains('name') &&
          !model.needsRefresh &&
          model.profile != null) {
        widget.onNameConfirmed?.call(model.profile!.code, model.profile!.name);
      }
      widget.onSaved?.call(changedFields);
    }
  }

  Future<void> publishContacts() async {
    if (busy) return;
    confirming = true;
    final yes = await confirm(
      'publishContacts',
      'publishBody',
      'publishContacts',
    );
    confirming = false;
    if (yes) model.update('publicShowExternalContacts', true);
  }

  Future<void> pickLogo() async {
    final port = images;
    if (busy || port == null || !port.canPickLogo) return;
    setState(() {
      choosing = true;
      localError = null;
    });
    try {
      final source = await port.pickLogo();
      if (!mounted || model.invalidated || source == null) return;
      final image = await dialog<String>(
        CommunityLogoCrop(port: port, source: source),
      );
      if (mounted && !model.invalidated && image != null) {
        model.update('logoImageData', image);
      }
    } catch (_) {
      if (mounted) setState(() => localError = 'imageFailed');
    } finally {
      if (!model.invalidated) {
        try {
          await port.clearLogo();
        } catch (_) {
          /* Account invalidation also clears the buffer. */
        }
      }
      if (mounted) setState(() => choosing = false);
    }
  }

  Future<void> chooseTags() async {
    if (busy || options == null) return;
    final names = communityTagNames(fields['type'] as String? ?? '')
        .map((name) => name.toLowerCase())
        .toSet();
    final known = options!.tags
        .where(
          (v) =>
              names.contains(v.name.toLowerCase()) ||
              names.contains(v.id.toLowerCase()),
        )
        .toList();
    if (names.length != known.length &&
        !await confirm('chooseTags', 'unknownTags', 'chooseTags')) {
      return;
    }
    if (!mounted || model.invalidated) return;
    final selected = await dialog<List<String>>(
      CommunityTagPicker(
        options: options!,
        profileQuotas: true,
        selected: known.map((v) => v.id).toList(),
      ),
    );
    if (mounted && !model.invalidated && selected != null) {
      model.update(
        'type',
        selected
            .map((id) => options!.tags.firstWhere((v) => v.id == id).name)
            .join(' · '),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    logoEpoch++;
    draftLogoBytes = serverLogoBytes = null;
    draftLogoData = null;
    model.removeListener(changed);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = CommunityProfileFormSections(
      context: context,
      model: model,
      options: options,
      serial: serial,
      busy: busy,
      canPickLogo: images?.canPickLogo == true,
      draftLogoBytes: draftLogoBytes,
      serverLogoBytes: serverLogoBytes,
      logoLoading: logoLoading,
      logoFailed: logoFailed,
      update: update,
      structureChanged: () => serial++,
      pickLogo: pickLogo,
      chooseTags: chooseTags,
      publishContacts: publishContacts,
    );
    final size = MediaQuery.sizeOf(context);
    if (widget.embedded && model.profile != null && !_initialScrollDone) {
      _initialScrollDone = true;
      scrollToSection(section);
    }
    return PopScope(
      canPop: widget.embedded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leave());
      },
      child: CommunityEditorSurface(
        embedded: widget.embedded,
        insetPadding: const EdgeInsets.all(20),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.embedded ? 1120 : 960),
            child: SizedBox(
              width: widget.embedded ? null : 1000,
              height: widget.embedded ? null : size.height - 60,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t('editProfile'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (!widget.embedded)
                          IconButton(
                            onPressed: model.submitting || choosing
                                ? null
                                : leave,
                            tooltip: t('close'),
                            icon: const StandardIcon(StandardIconSemantic.close),
                          ),
                      ],
                    ),
                    if (model.loading) const LinearProgressIndicator(),
                    if (optionsFailed)
                      Row(
                        children: [
                          Expanded(child: Text(t('optionsFailed'))),
                          TextButton(
                            onPressed: loadOptions,
                            child: Text(t('reload')),
                          ),
                        ],
                      ),
                    if (localError != null || model.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          t(localError ?? model.error!),
                          style: TextStyle(
                            color: context.tokens.colors.warning,
                          ),
                        ),
                      ),
                    if (model.profile == null)
                      Expanded(
                        child: Center(
                          child: model.loading
                              ? const CircularProgressIndicator()
                              : TextButton(
                                  onPressed: reload,
                                  child: Text(t('reload')),
                                ),
                        ),
                      )
                    else ...[
                      const SizedBox(height: 12),
                      if (!widget.embedded)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < 4; i++)
                              ChoiceChip(
                                label: Text(
                                  t(
                                    [
                                      'basic',
                                      'discovery',
                                      'schedule',
                                      'contacts',
                                    ][i],
                                  ),
                                ),
                                selected: section == i,
                                onSelected:
                                    choosing || confirming || model.submitting
                                    ? null
                                    : (_) => setState(() => section = i),
                              ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Form(
                          key: form,
                          child: SingleChildScrollView(
                            controller: widget.embedded ? _scroll : null,
                            // Desktop scrollbars paint over the viewport. Keep
                            // their hit area clear of switches and dropdowns.
                            padding: widget.embedded
                                ? const EdgeInsetsDirectional.only(end: 16)
                                : null,
                            key: widget.embedded
                                ? const ValueKey('profile-continuous-scroll')
                                : ValueKey('profile-section-$section'),
                            child: widget.embedded
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      sections.continuousSection(
                                        0,
                                        _anchors[0],
                                        sections.basic,
                                      ),
                                      if (model.profile!.canEditProfile) ...[
                                        sections.continuousSection(
                                          1,
                                          _anchors[1],
                                          sections.discovery,
                                        ),
                                        sections.continuousSection(
                                          2,
                                          _anchors[2],
                                          sections.schedule,
                                        ),
                                        sections.continuousSection(
                                          3,
                                          _anchors[3],
                                          sections.contacts,
                                        ),
                                      ],
                                    ],
                                  )
                                : switch (section) {
                                    0 => sections.basic,
                                    1 => sections.discovery,
                                    2 => sections.schedule,
                                    _ => sections.contacts,
                                  },
                          ),
                        ),
                      ),
                    ],
                    const Divider(),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          t(
                            model.submitting
                                ? 'saving'
                                : model.dirty
                                ? 'dirty'
                                : model.outcome?.status == 'accepted'
                                ? 'saved'
                                : 'clean',
                          ),
                        ),
                        TextButton(
                          onPressed: model.submitting || choosing
                              ? null
                              : reload,
                          child: Text(t('reload')),
                        ),
                        TextButton(
                          onPressed: !busy && model.dirty ? discard : null,
                          child: Text(t('discard')),
                        ),
                        Tooltip(
                          message: widget.embedded ? t('saveProfileDraft') : '',
                          child: FilledButton(
                            onPressed: !busy && model.canSave ? save : null,
                            child: Text(t('save')),
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
      ),
    );
  }
}
