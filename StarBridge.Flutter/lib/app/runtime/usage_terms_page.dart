import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/brand/starbridge_app_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/common/social_read_activity.dart';
import '../../features/settings/client_license.dart';
import '../legal/usage_terms_sections.dart';

/// Presentation only. The existing Host notice owner records acceptance.
class UsageTermsPage extends StatefulWidget {
  const UsageTermsPage({
    required this.readLicense,
    required this.saving,
    this.exiting = false,
    required this.failed,
    required this.savingSource,
    required this.onAccept,
    required this.onExit,
    super.key,
  });
  final ClientLicenseRead readLicense;
  final bool saving, failed, exiting;
  final InteractionSource savingSource;
  final VoidCallback onAccept;
  final void Function(InteractionSource) onExit;

  @override
  State<UsageTermsPage> createState() => _UsageTermsPageState();
}

class _UsageTermsPageState extends State<UsageTermsPage> {
  final _scroll = ScrollController();
  ClientLicenseDocument? _document;
  bool _loading = true, _reachedEnd = false, _checked = false;
  bool _measurementPending = false;
  Locale? _locale;
  int _readRevision = 0;
  Timer? _readTimeout;
  Completer<ClientLicenseDocument>? _pendingRead;

  bool get _ready =>
      !_loading &&
      _document?.state == ClientLicenseState.ready &&
      (_document?.text?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
    unawaited(_read());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_locale != locale) {
      _locale = locale;
      _reachedEnd = _checked = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });
      _scheduleMeasure();
    }
  }

  Future<void> _read() async {
    final revision = ++_readRevision;
    setState(() {
      _loading = true;
      _document = null;
      _reachedEnd = _checked = false;
    });
    final pending = Completer<ClientLicenseDocument>();
    _pendingRead = pending;
    void complete(ClientLicenseDocument document) {
      if (!pending.isCompleted) pending.complete(document);
    }

    _readTimeout?.cancel();
    _readTimeout = Timer(
      const Duration(seconds: 15),
      () =>
          complete(const ClientLicenseDocument(ClientLicenseState.unavailable)),
    );
    unawaited(
      Future<ClientLicenseDocument>.sync(widget.readLicense).then(
        complete,
        onError: (Object _, StackTrace _) => complete(
          const ClientLicenseDocument(ClientLicenseState.unavailable),
        ),
      ),
    );
    final document = await pending.future;
    _readTimeout?.cancel();
    if (!mounted || revision != _readRevision) return;
    setState(() {
      _document = document;
      _loading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (_measurementPending) return;
    _measurementPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementPending = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    if (!_ready || _reachedEnd || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.hasContentDimensions && position.extentAfter <= 1) {
      setState(() => _reachedEnd = true);
    }
  }

  void _move(double delta, {bool end = false, bool home = false}) {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(
      home
          ? 0
          : end
          ? _scroll.position.maxScrollExtent
          : (_scroll.offset + delta)
                .clamp(0, _scroll.position.maxScrollExtent)
                .toDouble(),
    );
  }

  @override
  void dispose() {
    _readRevision++;
    _readTimeout?.cancel();
    if (_pendingRead case final pending? when !pending.isCompleted) {
      pending.complete(
        const ClientLicenseDocument(ClientLicenseState.unavailable),
      );
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final locale = Localizations.localeOf(context);
    String t(String cn, String tw, String en) => locale.languageCode == 'en'
        ? en
        : locale.scriptCode == 'Hant' ||
              const {'TW', 'HK', 'MO'}.contains(locale.countryCode)
        ? tw
        : cn;
    final consentLabel = t(
      '我已阅读并同意上述条款与声明',
      '我已閱讀並同意上述條款與聲明',
      'I have read and agree to the terms and notices above',
    );
    final canChoose =
        _ready && _reachedEnd && !widget.saving && !widget.exiting;
    return Scaffold(
      key: const Key('test-build-notice'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (constraints.maxWidth >= 600) ...[
                      Row(
                        children: [
                          const StarBridgeAppIcon(size: 28),
                          const SizedBox(width: 12),
                          Text(
                            t('星海舰桥', '星海艦橋', 'StarBridge'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(t('使用前须知', '使用前須知', 'Before you start')),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      t('使用条款与声明', '使用條款與聲明', 'Terms and notices'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.end): () =>
                              _move(0, end: true),
                          const SingleActivator(LogicalKeyboardKey.home): () =>
                              _move(0, home: true),
                          const SingleActivator(
                            LogicalKeyboardKey.pageDown,
                          ): () => _move(
                            _scroll.hasClients
                                ? _scroll.position.viewportDimension * .8
                                : 0,
                          ),
                          const SingleActivator(
                            LogicalKeyboardKey.pageUp,
                          ): () => _move(
                            _scroll.hasClients
                                ? -_scroll.position.viewportDimension * .8
                                : 0,
                          ),
                        },
                        child: Focus(
                          autofocus: true,
                          child:
                              NotificationListener<ScrollMetricsNotification>(
                                onNotification: (_) {
                                  _scheduleMeasure();
                                  return false;
                                },
                                child: Scrollbar(
                                  controller: _scroll,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    key: const Key('usage-terms-scroll'),
                                    controller: _scroll,
                                    padding: const EdgeInsets.only(
                                      right: 16,
                                      bottom: 20,
                                    ),
                                    child: UsageTermsSections(
                                      license: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (_loading)
                                            Text(
                                              t(
                                                '正在读取完整许可…',
                                                '正在讀取完整授權條款…',
                                                'Loading the full license…',
                                              ),
                                            )
                                          else if (_ready)
                                            SelectableText(
                                              _document!.text!,
                                              key: const Key(
                                                'usage-terms-license',
                                              ),
                                            )
                                          else ...[
                                            Text(
                                              t(
                                                '未能完整读取许可，暂时无法同意。请重试。',
                                                '未能完整讀取授權條款，暫時無法同意。請重試。',
                                                'The full license could not be loaded. Acceptance is unavailable. Try again.',
                                              ),
                                            ),
                                            StarBridgeActionButton(
                                              kind: StarBridgeActionKind.quiet,
                                              controlKey: const Key(
                                                'usage-terms-reread',
                                              ),
                                              onActivate:
                                                  widget.saving ||
                                                      widget.exiting
                                                  ? null
                                                  : (_) => unawaited(_read()),
                                              child: Text(
                                                t('重新读取', '重新讀取', 'Read again'),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        ),
                      ),
                    ),
                    const Divider(),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        t(
                          _reachedEnd ? '已到达末尾，请自主确认是否同意。' : '请阅读至末尾后继续。',
                          _reachedEnd ? '已到達末尾，請自行確認是否同意。' : '請閱讀至末尾後繼續。',
                          _reachedEnd
                              ? 'End reached. Decide whether to accept.'
                              : 'Read to the end to continue.',
                        ),
                      ),
                    ),
                    StarBridgeCheckboxTile(
                      key: const Key('usage-terms-consent'),
                      value: _checked,
                      label: consentLabel,
                      onChanged: canChoose
                          ? (value) => setState(() => _checked = value)
                          : null,
                      rowBuilder: (control) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        enabled: canChoose,
                        // Preserve CheckboxListTile's 40px leading column.
                        leading: SizedBox(
                          width: 40,
                          height: 40,
                          child: OverflowBox(
                            maxWidth: 48,
                            maxHeight: 48,
                            child: control,
                          ),
                        ),
                        title: Text(consentLabel),
                      ),
                    ),
                    if (widget.failed)
                      Text(
                        t(
                          '暂时无法继续，请重试。确认未保存前不会放行。',
                          '暫時無法繼續，請重試。確認未儲存前不會放行。',
                          'Unable to continue. Try again. Access remains blocked until acknowledgement is saved.',
                        ),
                        style: TextStyle(color: tokens.colors.warning),
                      ),
                    if (widget.saving || widget.exiting)
                      SocialReadActivity(
                        key: const Key('test-build-accept-activity'),
                        source: widget.savingSource,
                        opening: false,
                        label: widget.exiting
                            ? t('正在退出应用…', '正在結束應用程式…', 'Exiting application…')
                            : t(
                                '正在记录确认…',
                                '正在記錄確認…',
                                'Recording acknowledgement…',
                              ),
                      ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        StarBridgeActionButton(
                          kind: StarBridgeActionKind.quiet,
                          controlKey: const Key('test-build-exit'),
                          onActivate: widget.saving || widget.exiting
                              ? null
                              : widget.onExit,
                          child: Text(
                            t('不同意并退出', '不同意並結束', 'Decline and exit'),
                          ),
                        ),
                        StarBridgeActionButton(
                          kind: StarBridgeActionKind.primary,
                          controlKey: const Key('test-build-accept'),
                          onActivate:
                              _ready &&
                                  _reachedEnd &&
                                  _checked &&
                                  !widget.saving &&
                                  !widget.exiting
                              ? (_) => widget.onAccept()
                              : null,
                          child: Text(
                            t('同意并继续', '同意並繼續', 'Agree and continue'),
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
