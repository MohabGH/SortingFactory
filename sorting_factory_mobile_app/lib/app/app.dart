import 'package:flutter/material.dart';

import '../core/communication/communication_scope.dart';
import '../core/communication/robot_communication_service.dart';
import '../core/communication/unconfigured_communication_service.dart';
import '../core/constants/app_info.dart';
import '../core/navigation/navigation_controller.dart';
import '../core/navigation/navigation_scope.dart';
import 'app_shell.dart';
import 'theme/app_theme.dart';

/// Root widget of the application.
///
/// Owns the app-wide singletons (navigation state and the communication
/// service) and exposes them to the widget tree through inherited scopes.
class RobotArmApp extends StatefulWidget {
  const RobotArmApp({super.key, this.communicationService});

  /// Optional override, useful for tests or for plugging in a real transport
  /// (Bluetooth, Wi-Fi, serial, ...) once the protocol is decided.
  final RobotCommunicationService? communicationService;

  @override
  State<RobotArmApp> createState() => _RobotArmAppState();
}

class _RobotArmAppState extends State<RobotArmApp> {
  final NavigationController _navigation = NavigationController();
  late final RobotCommunicationService _communication =
      widget.communicationService ?? UnconfiguredCommunicationService();

  @override
  void dispose() {
    _navigation.dispose();
    _communication.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommunicationScope(
      service: _communication,
      child: NavigationScope(
        controller: _navigation,
        child: MaterialApp(
          title: AppInfo.name,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.system,
          home: const AppShell(),
        ),
      ),
    );
  }
}
