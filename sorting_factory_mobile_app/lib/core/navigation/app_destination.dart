import 'package:flutter/widgets.dart';

import 'app_page_id.dart';

/// Groups destinations into sections in the drawer and on the home page.
/// Sections are displayed in declaration order.
enum DestinationGroup {
  general('General'),
  controlModes('Control modes'),
  system('System');

  const DestinationGroup(this.label);

  final String label;
}

/// Describes a page that can be displayed by the app shell.
@immutable
class AppDestination {
  const AppDestination({
    required this.id,
    required this.title,
    required this.icon,
    required this.builder,
    this.selectedIcon,
    this.description,
    this.group = DestinationGroup.general,
    this.showOnHome = false,
  });

  final AppPageId id;
  final String title;
  final IconData icon;
  final IconData? selectedIcon;

  /// Short text shown on the home page card.
  final String? description;

  final DestinationGroup group;

  /// Whether a shortcut card for this destination appears on the home page.
  final bool showOnHome;

  /// Builds the page body. Pages must NOT contain their own [Scaffold]
  /// app bar or drawer; the shell provides those.
  final WidgetBuilder builder;
}
