import 'package:flutter/material.dart';

import '../../core/navigation/app_destination.dart';
import '../../core/navigation/navigation_scope.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/responsive_grid.dart';
import '../../shared/widgets/section_header.dart';
import 'widgets/feature_card.dart';
import 'widgets/home_hero_card.dart';

/// Landing page with shortcut cards to every registered feature.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.shortcuts});

  /// Destinations to display as cards (provided by the app registry).
  final List<AppDestination> shortcuts;

  @override
  Widget build(BuildContext context) {
    final groups = DestinationGroup.values
        .where((group) => shortcuts.any((d) => d.group == group));

    return PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const HomeHeroCard(),
          for (final group in groups) ...[
            SectionHeader(group.label),
            ResponsiveGrid(
              children: [
                for (final destination
                    in shortcuts.where((d) => d.group == group))
                  FeatureCard(
                    icon: destination.selectedIcon ?? destination.icon,
                    title: destination.title,
                    description: destination.description,
                    onTap: () =>
                        NavigationScope.read(context).goTo(destination.id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
