import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../features/communities/community_announcement_details.dart';
import '../../features/communities/community_announcements_copy.dart';
import 'menu_announcement_details_view.dart';

class MenuAnnouncementDetailsControl extends StatefulWidget {
  const MenuAnnouncementDetailsControl({
    super.key,
    required this.view,
    required this.action,
    required this.enabled,
    required this.dispatch,
    this.active = true,
  });
  final MenuAnnouncementDetailsView view;
  final String? action;
  final bool enabled;
  final bool active;
  final void Function(String, String) dispatch;
  @override
  State<MenuAnnouncementDetailsControl> createState() => _ControlState();
}

class _DetailsPresentation {
  const _DetailsPresentation(this.view, this.retryEnabled, this.source);
  final MenuAnnouncementDetailsView view;
  final bool retryEnabled;
  final InteractionSource source;
}

class _ControlState extends State<MenuAnnouncementDetailsControl> {
  ValueNotifier<_DetailsPresentation?>? _dialog;
  StarBridgeDialogRoute<void>? _route;
  InteractionSource _readSource = InteractionSource.programmatic;
  bool get _available =>
      widget.active && widget.enabled && widget.action != null;
  _DetailsPresentation get _presentation =>
      _DetailsPresentation(widget.view, _available, _readSource);

  void _retire() {
    _dialog?.value = null;
    retireStarBridgeDialog(_route);
  }

  @override
  void didUpdateWidget(MenuAnnouncementDetailsControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Retirement is irreversible for this open route, even if another frame
    // arrives while it is being removed. A new entry must be explicitly opened.
    if (_dialog == null || _dialog!.value == null) return;
    if (!widget.active || oldWidget.view.key != widget.view.key) {
      _retire();
    } else {
      _dialog!.value = _presentation;
    }
  }

  void _load(InteractionSource source) {
    final action = widget.action;
    if (!_available || action == null || widget.view.loading) return;
    _readSource = source;
    if (_dialog?.value != null) _dialog!.value = _presentation;
    // Dispatch is still synchronous and the session owns its actual pending
    // and result. This is read provenance, not a fabricated transport Future.
    runStarBridgeSynchronousActivation(
      source,
      () => widget.dispatch(action, ''),
    );
  }

  Future<void> _open(InteractionSource source) async {
    if (!_available || _dialog != null) return;
    _readSource = source;
    final state = _dialog = ValueNotifier<_DetailsPresentation?>(_presentation);
    StarBridgeDialogRoute<void>? opened;
    try {
      _load(source);
      await showStarBridgeDialog<void>(
        context,
        source: source,
        useRootNavigator: false,
        builder: (_) => _DetailsDialog(view: state, retry: _load),
        onRouteCreated: (route) => _route = opened = route,
      );
    } finally {
      if (identical(_dialog, state)) _dialog = null;
      if (identical(_route, opened)) _route = null;
      state.dispose();
    }
  }

  @override
  void dispose() {
    _retire();
    _dialog = null;
    _route = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StarBridgeActionButton(
    controlKey: const Key('menu-announcement-details-open'),
    onActivate: _available ? _open : null,
    child: Text(communityAnnouncementText(context, 'details')),
  );
}

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.view, required this.retry});
  final ValueNotifier<_DetailsPresentation?> view;
  final ValueChanged<InteractionSource> retry;
  @override
  State<_DetailsDialog> createState() => _DialogState();
}

class _DialogState extends State<_DetailsDialog> {
  bool _closing = false;
  bool _rebuildScheduled = false;
  Uint8List? _author, _editor;
  void _photos() {
    final view = widget.view.value?.view;
    if (!listEquals(_author, view?.author)) _author = view?.author;
    if (!listEquals(_editor, view?.editor)) _editor = view?.editor;
  }

  @override
  void initState() {
    super.initState();
    _photos();
    widget.view.addListener(_changed);
  }

  void _changed() {
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (!mounted) return;
      if (widget.view.value == null && !_closing) {
        _closing = true;
        final route = ModalRoute.of(context);
        if (route is StarBridgeDialogRoute) retireStarBridgeDialog(route);
      } else {
        _photos();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    widget.view.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.view.value, value = presentation?.view;
    return AlertDialog(
      title: Text(communityAnnouncementText(context, 'details')),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: value == null
              ? const SizedBox.shrink()
              : CommunityAnnouncementDetailsBody(
                  entry: value.entry,
                  author: _author,
                  editor: _editor,
                  loading: value.loading,
                  loadingSource: presentation!.source,
                  retryEnabled: !value.loading && presentation.retryEnabled,
                  onRetryActivate: value.failed ? widget.retry : null,
                ),
        ),
      ),
      actions: [
        StarBridgeActionButton(
          controlKey: const Key('menu-announcement-details-close'),
          kind: StarBridgeActionKind.quiet,
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}
