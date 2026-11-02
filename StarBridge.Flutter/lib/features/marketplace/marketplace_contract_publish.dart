import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_contracts_controller.dart';
import 'marketplace_contracts_copy.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_trade_style.dart';
import 'marketplace_widgets.dart';

/// 发布合约 (approved preview): the same dialog look as publishing a listing.
/// SCM's own limits are checked here and again by the Host; the contract is
/// sent once, then 我发布的 is read again.
Future<void> showContractPublish(
  BuildContext context,
  MarketplaceContractsController c,
) => tradeMotionDialog<void>(context, (dialog) => _PublishDialog(c));

class _PublishDialog extends StatefulWidget {
  const _PublishDialog(this.c);
  final MarketplaceContractsController c;
  @override
  State<_PublishDialog> createState() => _PublishState();
}

class _PublishState extends State<_PublishDialog> {
  String type = 'SERVICE', rewardType = 'UEC';
  Duration deadline = const Duration(days: 3);
  final title = TextEditingController(), description = TextEditingController();
  final uec = TextEditingController(), note = TextEditingController();
  final slots = TextEditingController(text: '1'),
      reputation = TextEditingController(text: '0');
  final location = TextEditingController(),
      requirements = TextEditingController();
  String? error;
  bool sending = false;

  @override
  void dispose() {
    for (final field in [
      title,
      description,
      uec,
      note,
      slots,
      reputation,
      location,
      requirements,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final count = int.tryParse(slots.text.trim());
    final amount = int.tryParse(uec.text.trim().replaceAll(',', ''));
    final minimum = int.tryParse(reputation.text.trim()) ?? 0;
    final valid =
        title.text.trim().isNotEmpty &&
        title.text.trim().length <= 100 &&
        count != null &&
        count >= 1 &&
        count <= 100 &&
        minimum >= 0 &&
        (rewardType == 'UEC'
            ? amount != null && amount > 0
            : note.text.trim().isNotEmpty);
    if (!valid) {
      setState(
        () => error = contractText(
          context,
          '请核对：标题必填；UEC 报酬要大于 0；物品报酬要写说明；名额 1–100；截止时间要在未来。',
        ),
      );
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    String? text(TextEditingController field) =>
        field.text.trim().isEmpty ? null : field.text.trim();
    final ok = await widget.c.act('create', {
      'contract': {
        'type': type,
        'title': title.text.trim(),
        'description': ?text(description),
        'rewardType': rewardType,
        if (rewardType == 'UEC') 'rewardUec': amount,
        'rewardNote': ?text(note),
        'slots': count,
        'minReputation': minimum,
        'location': ?text(location),
        'requirements': ?text(requirements),
        'expireTime': DateTime.now().add(deadline).millisecondsSinceEpoch,
      },
    });
    if (!mounted) return;
    if (ok) {
      dismissStarBridgeDialog<void>(
        context,
        source: StarBridgeActivationOrigin.sourceOf(context),
      );
      return;
    }
    setState(() {
      sending = false;
      error = contractText(context, 'SCM 未接受这个操作，详情已按 SCM 的最新状态刷新。');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget row(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                contractText(context, label),
                style: TextStyle(fontSize: 12.5, color: t.colors.textSecondary),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
    Widget field(
      TextEditingController controller,
      String hint, {
      Key? key,
      int maxLength = 100,
      int lines = 1,
      bool digits = false,
      String? prefix,
    }) => TextField(
      key: key,
      controller: controller,
      maxLength: maxLength,
      minLines: lines,
      maxLines: lines,
      keyboardType: digits ? TextInputType.number : null,
      inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        prefixText: prefix == null ? null : contractText(context, prefix),
        hintText: contractText(context, hint),
        isDense: true,
        counterText: '',
      ),
    );
    Widget chips(
      String group,
      Map<String, String> values,
      String selected,
      ValueChanged<String> pick,
    ) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in values.entries)
          MarketToggle(
            key: ValueKey(('market-contract-publish', group, e.key)),
            label: Text(contractText(context, e.value)),
            selected: selected == e.key,
            onSelected: (_) => setState(() => pick(e.key)),
          ),
      ],
    );
    return AlertDialog(
      title: Text(contractText(context, '发布合约')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row(
                '类型',
                chips(
                  'type',
                  const {'BOUNTY': '悬赏', 'SERVICE': '委托', 'COOPERATION': '协作'},
                  type,
                  (v) => type = v,
                ),
              ),
              row(
                '标题',
                field(
                  title,
                  '标题（最多 100 字）',
                  key: const Key('market-contract-publish-title'),
                ),
              ),
              row(
                '说明',
                field(description, '说明（最多 2000 字）', maxLength: 2000, lines: 3),
              ),
              row(
                '报酬',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    chips(
                      'reward',
                      const {'UEC': 'UEC', 'ITEMS': '物品'},
                      rewardType,
                      (v) => rewardType = v,
                    ),
                    const SizedBox(height: 6),
                    if (rewardType == 'UEC')
                      field(
                        uec,
                        'UEC 金额',
                        key: const Key('market-contract-publish-uec'),
                        maxLength: 13,
                        digits: true,
                      ),
                    field(note, '报酬说明（物品报酬必填）', maxLength: 500),
                  ],
                ),
              ),
              row(
                '名额 / 信誉',
                Row(
                  children: [
                    Expanded(
                      child: field(
                        slots,
                        '名额（1–100）',
                        prefix: '名额 ',
                        key: const Key('market-contract-publish-slots'),
                        maxLength: 3,
                        digits: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: field(
                        reputation,
                        '最低信誉',
                        prefix: '信誉 ≥ ',
                        maxLength: 6,
                        digits: true,
                      ),
                    ),
                  ],
                ),
              ),
              row('地点', field(location, '地点', maxLength: 500)),
              row(
                '其他要求',
                field(requirements, '其他要求', maxLength: 1000, lines: 2),
              ),
              row(
                '截止',
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (key, value, label) in [
                      ('6h', const Duration(hours: 6), '{n} 小时'),
                      ('1d', const Duration(days: 1), '{n} 天'),
                      ('3d', const Duration(days: 3), '{n} 天'),
                      ('7d', const Duration(days: 7), '{n} 天'),
                      ('30d', const Duration(days: 30), '{n} 天'),
                    ])
                      MarketToggle(
                        key: ValueKey((
                          'market-contract-publish',
                          'deadline',
                          key,
                        )),
                        label: Text(
                          contractText(context, label, {
                            'n':
                                '${value.inHours < 24 ? value.inHours : value.inDays}',
                          }),
                        ),
                        selected: deadline == value,
                        onSelected: (_) => setState(() => deadline = value),
                      ),
                  ],
                ),
              ),
              if (error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    error!,
                    style: TextStyle(fontSize: 12, color: t.colors.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        marketButtonAction(
          key: const Key('market-contract-publish-cancel'),
          TextButton(
            onPressed: () => dismissStarBridgeDialog<void>(
              context,
              source: StarBridgeActivationOrigin.sourceOf(context),
            ),
            child: Text(contractText(context, '取消')),
          ),
        ),
        marketButtonAction(
          key: const Key('market-contract-publish-submit'),
          FilledButton(
            style: tradePrimaryStyle(context),
            onPressed: sending ? null : _submit,
            child: Text(contractText(context, '发布合约')),
          ),
        ),
      ],
    );
  }
}
