import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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

class _ControlState extends State<MenuAnnouncementDetailsControl> {
  ValueNotifier<MenuAnnouncementDetailsView?>? _dialog;
  @override
  void didUpdateWidget(MenuAnnouncementDetailsControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dialog?.value = oldWidget.active && !widget.active ? null : widget.view;
  }

  void _load() {
    final action = widget.action;
    if (action != null && widget.enabled) widget.dispatch(action, '');
  }

  Future<void> _open() async {
    if (_dialog != null) return;
    final state = _dialog = ValueNotifier<MenuAnnouncementDetailsView?>(
      widget.view,
    );
    _load();
    try {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (_) => _DetailsDialog(view: state, retry: _load),
      );
    } finally {
      if (identical(_dialog, state)) _dialog = null;
      state.dispose();
    }
  }

  @override
  void dispose() {
    _dialog?.value = null;
    _dialog = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: widget.enabled && widget.action != null ? _open : null,
    child: Text(communityAnnouncementText(context, 'details')),
  );
}

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.view, required this.retry});
  final ValueNotifier<MenuAnnouncementDetailsView?> view;
  final VoidCallback retry;
  @override
  State<_DetailsDialog> createState() => _DialogState();
}

class _DialogState extends State<_DetailsDialog> {
  bool _closing = false;
  Uint8List? _author, _editor;
  void _photos() {
    final view = widget.view.value;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.view.value == null && !_closing) {
        _closing = true;
        Navigator.of(context).pop();
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
    final value = widget.view.value;
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
                  onRetry: value.failed ? widget.retry : null,
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}
