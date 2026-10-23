import 'package:flutter/material.dart';

import '../core/navigation/app_destination.dart';
import '../core/navigation/app_page_id.dart';
import '../features/home/home_page.dart';
import '../features/manual_control/manual_control_page.dart';
import '../features/settings/settings_page.dart';

/// Central registry of every page reachable from the drawer / home page.
///
/// To add a new feature:
///   1. Create its folder under `lib/features/<feature_name>/`.
///   2. Add a value to [AppPageId].
///   3. Register an [AppDestination] below.
/// The drawer, the home page shortcuts and the app bar title update
/// automatically.
abstract final class AppDestinations {
  static final List<AppDestination> all = List.unmodifiable(<AppDestination>[
    AppDestination(
      id: AppPageId.home,
      title: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      group: DestinationGroup.general,
      builder: (_) => HomePage(shortcuts: homeShortcuts),
    ),
    AppDestination(
      id: AppPageId.manualControl,
      title: 'Manual Control',
      description: 'Type an exact angle for each servo and send it.',
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
      group: DestinationGroup.controlModes,
      showOnHome: true,
      builder: (_) => const ManualControlPage(),
    ),
    AppDestination(
      id: AppPageId.settings,
      title: 'Settings',
      description: 'Connection, robot arm configuration and app info.',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      group: DestinationGroup.system,
      showOnHome: true,
      builder: (_) => const SettingsPage(),
    ),
  ]);

  /// Destinations displayed as cards on the home page.
  static List<AppDestination> get homeShortcuts =>
      all.where((d) => d.showOnHome).toList(growable: false);

  static AppDestination byId(AppPageId id) => all.firstWhere(
        (d) => d.id == id,
        orElse: () => throw StateError(
          'No AppDestination registered for $id. '
          'Add one to AppDestinations.all.',
        ),
      );
}
