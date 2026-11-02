import 'dart:async';

import 'community_profile_form_sections.dart';
import 'community_profile_dialog_presentation.dart';

import 'community_visible_refresh.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

import 'community_profile_controller.dart';
import 'community_profile_port.dart';
import 'community_profile_copy.dart';
import 'community_creation_port.dart';
import 'community_logo_port.dart';
import 'community_logo_crop.dart';
import 'community_profile_wide_images.dart';
import 'community_wide_image_port.dart';
import 'community_tag_picker.dart';
import 'community_gameplay_tags.dart';
import 'community_workspace_copy.dart' show workspaceDays;
import 'community_workspace_port.dart';
import 'communities_module.dart';
import 'community_editor_surface.dart';
import 'community_profile_editor_chrome.dart';
import '../common/social_read_activity.dart';

class CommunityProfileDialog extends StatefulWidget {
  const CommunityProfileDialog({
    required this.port,
    required this.targetRef,
    this.logoBytes,
    this.bannerBytes,
    this.backgroundBytes,
    this.embedded = false,
    this.onSaved,
    this.onNameConfirmed,
    this.sectionIndex,
    this.onSectionChanged,
    super.key,
  });
  final CommunityProfilePort port;
  final String targetRef;
  final Uint8List? logoBytes, bannerBytes, backgroundBytes;
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
  late final SocialReadActivityBinding _reading, _saving;
  ValueGetter<InteractionSource>? _imageSource;
  int _imageRevision = 0;
  bool _observedLoading = false, _observedSubmitting = false;
  bool _optionsBusy = false, _optionsOpening = false, _firstOptions = true;
  int _optionsRevision = 0;
  InteractionSource _optionsSource = InteractionSource.programmatic;
  InteractionSource _logoSource = InteractionSource.programmatic;
  bool _logoOpening = false;
  final form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _anchors = List.generate(4, (_) => GlobalKey());
  bool _scrollUpdateQueued = false;
  bool _initialScrollDone = false;
  final dialogs = <StarBridgeDialogRoute<dynamic>>[];
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
  CommunityProfileDialogActivity get _activity =>
      CommunityProfileDialogActivity(
        model: model,
        reading: _reading,
        saving: _saving,
        text: t,
      );
  Widget _readMarker(String key, {bool circular = false}) =>
      _activity.readMarker(key, circular: circular);
  Widget? get _footerActivity => _activity.footerActivity(
    choosing: choosing,
    dialogOpen: dialogs.isNotEmpty,
    imageSource: _imageSource,
    imageRevision: _imageRevision,
  );
  Widget? get _optionsActivity => _activity.optionsActivity(
    busy: _optionsBusy,
    revision: _optionsRevision,
    dialogOpen: dialogs.isNotEmpty,
    source: _optionsSource,
    opening: _optionsOpening,
  );
  Widget get _logoActivity => _activity.logoActivity(
    epoch: logoEpoch,
    dialogOpen: dialogs.isNotEmpty,
    source: _logoSource,
    opening: _logoOpening,
  );

  CommunityLogoPort? get images => widget.port is CommunityLogoPort
      ? widget.port as CommunityLogoPort
      : null;
  @override
  void initState() {
    super.initState();
    section = widget.sectionIndex ?? 0;
    _scroll.addListener(_queueScrollSectionUpdate);
    serverLogoBytes = widget.logoBytes;
    _reading = SocialReadActivityBinding(
      model,
      () => model.loading,
      initialRead: true,
    );
    _saving = SocialReadActivityBinding(
      model,
      () => model.submitting,
      initialRead: false,
    );
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
    final revision = ++_optionsRevision;
    setState(() {
      _optionsSource = captureStarBridgeActivationSource()();
      _optionsOpening = _firstOptions;
      _firstOptions = false;
      _optionsBusy = true;
    });
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
    } finally {
      if (mounted && revision == _optionsRevision) {
        setState(() => _optionsBusy = false);
      }
    }
  }

  void changed() {
    if (!mounted) return;
    final readCompleted = _observedLoading && !model.loading;
    final saveCompleted = _observedSubmitting && !model.submitting;
    _observedLoading = model.loading;
    _observedSubmitting = model.submitting;
    if (model.invalidated) {
      for (final route in dialogs.toList().reversed) {
        retireStarBridgeDialog(route);
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
        unawaited(
          refreshLogo(
            baseline!,
            activitySource: saveCompleted
                ? _saving.source
                : readCompleted
                ? _reading.source
                : InteractionSource.programmatic,
            opening: !saveCompleted && readCompleted && _reading.opening,
          ),
        );
      }
    }
    final data = model.changes['logoImageData'] as String?;
    if (data != draftLogoData) {
      draftLogoData = data;
      draftLogoBytes = data == null ? null : base64Decode(data.split(',').last);
    }
    setState(() {});
  }

  Future<void> refreshLogo(
    CommunityEditingProfile profile, {
    InteractionSource activitySource = InteractionSource.programmatic,
    bool opening = false,
  }) async {
    final current = ++logoEpoch;
    _logoSource = activitySource;
    _logoOpening = opening;
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
    StarBridgeDialogRoute<T>? opened;
    try {
      return await showStarBridgeDialog<T>(
        context,
        useRootNavigator: false,
        barrierDismissible: false,
        onRouteCreated: (route) {
          opened = route;
          dialogs.add(route);
          if (choosing && mounted) setState(() {});
        },
        builder: (_) => child,
      );
    } finally {
      dialogs.remove(opened);
      if (choosing && mounted) setState(() {});
    }
  }

  Future<bool> confirm(String title, String body, String action) async {
    final result = await dialog<bool>(
      communityProfileConfirmation(
        text: t,
        title: title,
        body: body,
        action: action,
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
        communityProfileLeaveConfirmation(text: t, model: model),
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
      dismissStarBridgeDialog(
        context,
        source: currentStarBridgeActivationSource,
        result: saved,
      );
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
    _imageSource = captureStarBridgeActivationSource();
    _imageRevision++;
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
      _imageSource = null;
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
    for (final route in dialogs.toList().reversed) {
      retireStarBridgeDialog(route);
    }
    dialogs.clear();
    _scroll.dispose();
    logoEpoch++;
    draftLogoBytes = serverLogoBytes = null;
    draftLogoData = null;
    _reading.dispose();
    _saving.dispose();
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
      logoLoadingIndicator: _logoActivity,
      wideImages: CommunityProfileWideImages(
        model: model,
        port: widget.port is CommunityWideImagePort
            ? widget.port as CommunityWideImagePort
            : null,
        busy: busy,
        openDialog: dialog<String>,
        onChoosing: (value) {
          if (mounted) setState(() => choosing = value);
        },
        current: {
          'banner': widget.bannerBytes,
          'background': widget.backgroundBytes,
        },
      ),
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
        if (!didPop) {
          unawaited(
            runStarBridgeActivation<void>(InteractionSource.keyboard, leave),
          );
        }
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
                    CommunityProfileEditorHeader(
                      model: model,
                      embedded: widget.embedded,
                      choosing: choosing,
                      optionsFailed: optionsFailed,
                      localError: localError,
                      onLeave: leave,
                      onRetryOptions: loadOptions,
                      loadingIndicator: _readMarker('profile-read-activity'),
                      optionsActivity: _optionsActivity,
                    ),
                    if (model.profile == null)
                      communityProfileInitialRead(
                        loading: model.loading,
                        loadingIndicator: () => _readMarker(
                          'profile-initial-activity',
                          circular: true,
                        ),
                        onRetry: reload,
                        text: t,
                      )
                    else
                      ...communityProfileFormContent(
                        sections: sections,
                        embedded: widget.embedded,
                        section: section,
                        form: form,
                        scroll: _scroll,
                        anchors: _anchors,
                        onSectionChanged:
                            choosing || confirming || model.submitting
                            ? null
                            : (index) => setState(() => section = index),
                      ),
                    const Divider(),
                    CommunityProfileEditorActions(
                      model: model,
                      busy: busy,
                      choosing: choosing,
                      embedded: widget.embedded,
                      onReload: reload,
                      onDiscard: discard,
                      onSave: save,
                      activity: _footerActivity,
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
