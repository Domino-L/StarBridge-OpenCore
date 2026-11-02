import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import '../account/account_avatar_editor.dart';
import '../account/account_models.dart';
import '../onboarding/connection_mode_port.dart';
import 'personal_profile_module.dart';
import 'personal_profile_page.dart';
import 'personal_profile_port.dart';

import 'personal_profile_display_session.dart';

/// Owns the short-lived offline display module; never replaces the online owner.
class OfflinePersonalProfilePage extends StatefulWidget {
  const OfflinePersonalProfilePage({
    required this.mode,
    required this.createPort,
    required this.online,
    this.account,
    this.createRetainedPort,
    this.onlineModule,
    this.displaySession,
    super.key,
  });
  final ConnectionModeControl mode;
  final PersonalProfilePort Function() createPort;
  final Widget online;
  final ValueListenable<AccountProjection>? account;
  final PersonalProfilePort Function(String readId)? createRetainedPort;
  final PersonalProfileModule? onlineModule;
  final PersonalProfileDisplaySession? displaySession;
  @override
  State<OfflinePersonalProfilePage> createState() =>
      _OfflinePersonalProfilePageState();
}

class _OfflinePersonalProfilePageState
    extends State<OfflinePersonalProfilePage> {
  late PersonalProfileDisplaySession _owner;
  bool _owns = false;
  void _bind() {
    _owns = widget.displaySession == null;
    _owner =
        widget.displaySession ??
        PersonalProfileDisplaySession(
          mode: widget.mode,
          account: widget.account,
          createPort: widget.createPort,
          createRetainedPort: widget.createRetainedPort,
          onlineModule: widget.onlineModule,
        );
    _owner.addListener(_changed);
    _owner.activate();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant OfflinePersonalProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displaySession != widget.displaySession ||
        _owns &&
            (oldWidget.mode != widget.mode ||
                oldWidget.account != widget.account ||
                oldWidget.onlineModule != widget.onlineModule ||
                oldWidget.createRetainedPort != widget.createRetainedPort)) {
      _owner.removeListener(_changed);
      if (_owns) _owner.dispose();
      _bind();
    }
  }

  @override
  void dispose() {
    _owner.removeListener(_changed);
    if (_owns) _owner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.online;
    final page = original is PersonalProfilePage ? original : null;
    final module = _owner.displayModule;
    if (module == null && page == null) return original;
    final avatar = _owner.onlineDisplay ? AccountAvatarScope.of(context) : null;
    return AccountAvatarScope(
      port: avatar?.port,
      imageData: avatar?.imageData,
      editable: avatar?.editable == true,
      rsiManaged: avatar?.rsiManaged == true,
      child: PersonalProfilePage(
        key: ObjectKey(_owner),
        module: module ?? page!.module,
        offline: !_owner.onlineDisplay,
        viewState: _owner.view,
        access: _owner,
        presence: page?.presence,
        gameplayTime: page?.gameplayTime,
        pageToolbar: page?.pageToolbar,
        isVisitor: page?.isVisitor ?? false,
        visitorAvatarImageData: page?.visitorAvatarImageData,
      ),
    );
  }
}
