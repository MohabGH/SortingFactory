import 'package:flutter/material.dart';

import '../../core/constants/app_info.dart';
import '../../core/navigation/app_destination.dart';
import '../../core/navigation/app_page_id.dart';

/// Hamburger-menu drawer listing all registered destinations, grouped by
/// [DestinationGroup].
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.destinations,
    required this.currentPage,
    required this.onSelected,
  });

  final List<AppDestination> destinations;
  final AppPageId currentPage;
  final ValueChanged<AppPageId> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // NavigationDrawer indexes only its destination children, so keep a flat
    // list in display order to map indices back to pages.
    final ordered = <AppDestination>[];
    final children = <Widget>[const _DrawerHeader()];

    for (final group in DestinationGroup.values) {
      final items = destinations.where((d) => d.group == group).toList();
      if (items.isEmpty) continue;

      if (ordered.isNotEmpty) {
        children.add(const Divider(indent: 28, endIndent: 28));
      }
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 16, 8),
          child: Text(
            group.label,
            style: textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      for (final destination in items) {
        ordered.add(destination);
        children.add(
          NavigationDrawerDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon ?? destination.icon),
            label: Text(destination.title),
          ),
        );
      }
    }

    final selected = ordered.indexWhere((d) => d.id == currentPage);

    return NavigationDrawer(
      selectedIndex: selected < 0 ? null : selected,
      onDestinationSelected: (index) => onSelected(ordered[index].id),
      children: children,
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.precision_manufacturing_rounded,
              color: scheme.onPrimary,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppInfo.name,
            style: textTheme.titleLarge?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'v${AppInfo.version}',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
