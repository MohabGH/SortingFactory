import 'package:flutter/material.dart';

import '../../core/communication/communication_scope.dart';
import '../../core/communication/connection_status.dart';
import '../../core/communication/robot_communication_service.dart';
import '../../core/communication/sfra_protocol.dart';
import '../../core/constants/app_info.dart';
import '../../core/robot/robot_arm_config.dart';
import '../../shared/widgets/connection_status_chip.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/section_header.dart';

/// Application settings: Bluetooth connection, robot configuration, protocol
/// reference and app information.
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
          _ConnectionCard(service: service),
          if (service is ScanningCommunicationService &&
              !service.isConnected &&
              service.status != ConnectionStatus.unavailable) ...[
            const SectionHeader('Nearby devices'),
            _DeviceScanner(service: service),
          ],
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
                    subtitle: Text(
                      'Channel ${servo.id} · default ${servo.initialAngle}°',
                    ),
                    trailing: Text(
                      '${servo.minAngle}° – ${servo.maxAngle}°',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
              ],
            ),
          ),
          const SectionHeader('Protocol'),
          const _ProtocolCard(),
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

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.service});

  final RobotCommunicationService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = service.status;
    final device = service.connectedDevice;
    final scanning = service is ScanningCommunicationService
        ? service as ScanningCommunicationService
        : null;

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.bluetooth_rounded),
            title: const Text('Communication protocol'),
            subtitle: Text(service.transportName),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.wifi_tethering_rounded),
            title: const Text('Status'),
            subtitle: Text(service.statusMessage ?? status.label),
            trailing: const ConnectionStatusChip(),
          ),
          if (device != null) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.memory_rounded),
              title: Text(device.name),
              subtitle: Text(
                [
                  device.id,
                  if (device.mtu != null) 'MTU ${device.mtu}',
                  'Robot: ${service.activity.label}',
                ].join(' · '),
              ),
            ),
          ],
          if (status != ConnectionStatus.notConfigured)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: switch (status) {
                  ConnectionStatus.connected => OutlinedButton.icon(
                    onPressed: service.disconnect,
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Disconnect'),
                  ),
                  ConnectionStatus.connecting => const FilledButton.tonal(
                    onPressed: null,
                    child: Text('Connecting…'),
                  ),
                  ConnectionStatus.unavailable => FilledButton.icon(
                    onPressed: (scanning?.canEnableAdapter ?? false)
                        ? scanning!.enableAdapter
                        : null,
                    icon: const Icon(Icons.bluetooth_rounded),
                    label: Text(
                      (scanning?.canEnableAdapter ?? false)
                          ? 'Turn Bluetooth on'
                          : 'Enable Bluetooth in system settings',
                    ),
                  ),
                  _ => FilledButton.icon(
                    onPressed: service.connect,
                    icon: const Icon(Icons.bluetooth_searching_rounded),
                    label: Text('Connect to ${SfraProtocol.deviceName}'),
                  ),
                },
              ),
            ),
          if (status == ConnectionStatus.disconnected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'The ESP32 blinks its blue LED while advertising and keeps it '
                'solid once connected.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceScanner extends StatefulWidget {
  const _DeviceScanner({required this.service});

  final ScanningCommunicationService service;

  @override
  State<_DeviceScanner> createState() => _DeviceScannerState();
}

class _DeviceScannerState extends State<_DeviceScanner> {
  bool _showAll = false;

  void _scan() => widget.service.startScan(onlyRobots: !_showAll);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final service = widget.service;
    final devices = service.discoveredDevices;
    final busy = service.status == ConnectionStatus.connecting;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.filter_alt_outlined),
            title: const Text('Show all BLE devices'),
            subtitle: Text(
              _showAll
                  ? 'Listing every advertising device'
                  : 'Only devices named ${SfraProtocol.deviceName}',
            ),
            value: _showAll,
            onChanged: service.isScanning
                ? null
                : (value) => setState(() => _showAll = value),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          if (service.isScanning) const LinearProgressIndicator(minHeight: 2),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                service.isScanning
                    ? 'Scanning…'
                    : 'No devices found yet. Tap "Scan" to search.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final device in devices)
              ListTile(
                enabled: !busy,
                leading: Icon(
                  device.isRobot
                      ? Icons.precision_manufacturing_rounded
                      : Icons.bluetooth_rounded,
                  color: device.isRobot ? scheme.primary : null,
                ),
                title: Text(device.displayName),
                subtitle: Text('${device.id} · ${device.rssi} dBm'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => service.connectTo(device),
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: service.isScanning
                ? OutlinedButton.icon(
                    onPressed: service.stopScan,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop scan'),
                  )
                : OutlinedButton.icon(
                    onPressed: busy ? null : _scan,
                    icon: const Icon(Icons.radar_rounded),
                    label: const Text('Scan'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');

    Widget row(String label, String value) => ListTile(
      dense: true,
      title: Text(label),
      subtitle: SelectableText(value, style: mono),
    );

    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.code_rounded),
        title: const Text('SFRA BLE protocol'),
        subtitle: const Text('UUIDs and command format'),
        children: [
          row('Device name', SfraProtocol.deviceName),
          row('Service UUID', SfraProtocol.serviceUuid),
          row('RX (app → ESP32, write)', SfraProtocol.rxCharacteristicUuid),
          row('TX (ESP32 → app, notify)', SfraProtocol.txCharacteristicUuid),
          row(
            'Command format',
            '${SfraProtocol.formatHint}\n'
                'servo 0–${SfraProtocol.servoCount - 1}, '
                'angle ${SfraProtocol.minAngle}–${SfraProtocol.maxAngle}\n'
                'e.g. ${SfraProtocol.example}',
          ),
          row(
            'Replies',
            '"${SfraProtocol.responseMoving}" command accepted\n'
                '"${SfraProtocol.responseDone}" all servos reached target\n'
                '"${SfraProtocol.responseError}" invalid command',
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
