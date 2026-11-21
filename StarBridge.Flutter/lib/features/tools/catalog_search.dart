import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../common/organization_holo.dart';
import 'catalog_controller.dart';
import 'catalog_port.dart';

class CatalogSearch extends StatelessWidget {
  const CatalogSearch(this.controller, {super.key});
  final CatalogController controller;
  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final height = organizationHoloFieldHeight(context);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: height,
            child: TextField(
              key: const Key('catalog-search'),
              controller: controller.searchText,
              onChanged: controller.search,
              onSubmitted: controller.search,
              decoration: organizationHoloField(
                context,
                InputDecoration(
                  hintText: strings.text(
                    'catalog.${controller.kind == CatalogKind.missions ? 'searchMissions' : 'searchBlueprints'}',
                  ),
                ),
                slantEnd: true,
              ),
            ),
          ),
        ),
        Transform.translate(
          offset: Offset(4 - organizationHoloRun(height), 0),
          child: SizedBox(
            height: height,
            child: TextButton(
              key: const Key('catalog-search-submit'),
              style: organizationHoloButton(context, parallelogram: true),
              onPressed: () => controller.search(controller.searchText.text),
              child: Text(strings.text('terminal.search')),
            ),
          ),
        ),
      ],
    );
  }
}
