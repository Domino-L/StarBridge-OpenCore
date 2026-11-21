import 'package:flutter/material.dart';

import 'organization_governance_port.dart';

class OrganizationEvidenceRefresh extends StatefulWidget {
  const OrganizationEvidenceRefresh({
    required this.port,
    required this.onRequested,
    required this.stale,
    required this.text,
    required this.enabled,
    required this.onBusyChanged,
    super.key,
  });
  final OrganizationEvidenceRefreshPort port;
  final Future<void> Function() onRequested;
  final bool stale;
  final String Function(String) text;
  final bool enabled;
  final ValueChanged<bool> onBusyChanged;
  @override
  State<OrganizationEvidenceRefresh> createState() => _RefreshState();
}

class _RefreshState extends State<OrganizationEvidenceRefresh> {
  bool _sending = false;
  OrganizationEvidenceRefreshResult? _result;
  Future<void> _refresh() async {
    if (_sending || !widget.enabled || !widget.port.canRefreshEvidence) return;
    setState(() {
      _sending = true;
      _result = null;
    });
    widget.onBusyChanged(true);
    OrganizationEvidenceRefreshResult result;
    try {
      result = await widget.port.refreshEvidence();
    } on Object {
      result = const OrganizationEvidenceRefreshResult('unavailable');
    }
    if (!mounted) return;
    widget.onBusyChanged(false);
    setState(() {
      _sending = false;
      _result = result;
    });
    if (result.state == 'requested') await widget.onRequested();
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => widget.text('refreshEvidence.$key');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.stale)
          OutlinedButton(
            key: const Key('governance-refresh-evidence'),
            onPressed: _sending || !widget.enabled ? null : _refresh,
            child: Text(t(_sending ? 'sending' : 'refresh')),
          ),
        if (_result case final result?)
          Text(
            t(result.state)
                .replaceAll('{minutes}', '${result.remainingMinutes ?? 0}'),
            key: const Key('governance-refresh-result'),
          ),
      ],
    );
  }
}
