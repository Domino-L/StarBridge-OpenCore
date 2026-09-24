import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'community_sharing.dart';

class CommunitySharingDialog extends StatefulWidget {
  const CommunitySharingDialog({
    required this.target,
    required this.onSave,
    super.key,
  });
  final CommunitySharingTarget target;
  final Future<bool> Function(CommunitySharingScope) onSave;
  @override
  State<CommunitySharingDialog> createState() => _CommunitySharingDialogState();
}

class _CommunitySharingDialogState extends State<CommunitySharingDialog> {
  int _fields = 0;
  bool _busy = false, _failed = false;
  Future<void> _save(int fields) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    var saved = false;
    try {
      saved = await widget.onSave(widget.target.choice(fields: fields));
    } catch (_) {
      /* Keep the unconfirmed choice visible. */
    }
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('community-sharing-dialog'),
        title: Text(s.text('privacy.community.title')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.target.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(s.text('privacy.community.body')),
                const SizedBox(height: 12),
                for (final entry in const {
                  1: 'presence',
                  2: 'ship',
                  4: 'location',
                  8: 'server',
                }.entries)
                  CheckboxListTile(
                    key: Key('community-sharing-${entry.key}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(s.text('privacy.local.${entry.value}')),
                    value: _fields & entry.key != 0,
                    onChanged: _busy
                        ? null
                        : (checked) => setState(
                            () => _fields = checked == true
                                ? _fields | entry.key
                                : _fields & ~entry.key,
                          ),
                  ),
                if (_failed) Text(s.text('privacy.community.failed')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('community-sharing-none'),
            onPressed: _busy ? null : () => _save(0),
            child: Text(s.text('privacy.community.none')),
          ),
          FilledButton(
            key: const Key('community-sharing-confirm'),
            onPressed: _busy || _fields == 0 ? null : () => _save(_fields),
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(s.text('privacy.community.confirm')),
          ),
        ],
      ),
    );
  }
}
