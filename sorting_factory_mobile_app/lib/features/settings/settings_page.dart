import 'package:flutter/material.dart';

import '../../core/communication/communication_scope.dart';
import '../../core/constants/app_info.dart';
import '../../core/robot/robot_arm_config.dart';
import '../../shared/widgets/connection_status_chip.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/section_header.dart';

/// Application settings. Sections are placeholders ready to be filled once
/// the communication protocol and other options are defined.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = CommunicationScope.of(context);

    return PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const SectionHeader('Connection'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  enabled: false,
                  leading: Icon(Icons.settings_input_antenna_rounded),
                  title: Text('Communication protocol'),
                  subtitle: Text('Not specified yet'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.wifi_tethering_rounded),
                  title: const Text('Status'),
                  subtitle: Text(service.status.label),
                  trailing: const ConnectionStatusChip(),
                ),
              ],
            ),
          ),
          const SectionHeader('Robot arm'),
          Card(
            child: Column(
              children: [
                for (final (index, servo) in RobotArmConfig.servos.indexed)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(servo.name),
                    subtitle: Text('Default ${servo.initialAngle}°'),
                    trailing: Text(
                      '${servo.minAngle}° – ${servo.maxAngle}°',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
              ],
            ),
          ),
          const SectionHeader('About'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text(AppInfo.name),
              subtitle: Text('Version ${AppInfo.version}'),
            ),
          ),
        ],
      ),
    );
  }
}
