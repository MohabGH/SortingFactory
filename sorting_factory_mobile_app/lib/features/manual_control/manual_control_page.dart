import 'package:flutter/material.dart';

import '../../core/communication/communication_scope.dart';
import '../../core/communication/connection_status.dart';
import '../../core/communication/robot_command.dart';
import '../../core/communication/robot_communication_service.dart';
import '../../core/communication/sfra_protocol.dart';
import '../../core/navigation/app_page_id.dart';
import '../../core/navigation/navigation_scope.dart';
import '../../core/robot/robot_arm_config.dart';
import '../../core/robot/servo_config.dart';
import '../../shared/widgets/connection_status_chip.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/section_header.dart';
import 'manual_control_controller.dart';
import 'widgets/command_console.dart';
import 'widgets/servo_angle_field.dart';

/// Manual mode: one text field per servo to type the target angle, plus a
/// command window showing the traffic with the ESP32.
class ManualControlPage extends StatefulWidget {
  const ManualControlPage({super.key, this.servos = RobotArmConfig.servos});

  final List<ServoConfig> servos;

  @override
  State<ManualControlPage> createState() => _ManualControlPageState();
}

class _ManualControlPageState extends State<ManualControlPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final ManualControlController _controller = ManualControlController(
    servos: widget.servos,
  );
  late final Map<int, GlobalKey<FormFieldState<String>>> _fieldKeys = {
    for (final servo in widget.servos)
      servo.id: GlobalKey<FormFieldState<String>>(),
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendServo(ServoConfig servo) async {
    final isValid = _fieldKeys[servo.id]!.currentState?.validate() ?? false;
    if (!isValid) return;
    await _send(_controller.commandFor(servo));
  }

  Future<void> _sendAll() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;
    await _send(_controller.commandForAll());
  }

  Future<void> _send(RobotCommand command) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigation = NavigationScope.read(context);
    try {
      await CommunicationScope.read(context).send(command);
    } on CommunicationException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.message),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => navigation.goTo(AppPageId.settings),
            ),
          ),
        );
    }
  }

  void _reset() {
    _controller.resetToInitial();
    // Re-validate so any stale error messages are cleared.
    _formKey.currentState?.validate();
  }

  @override
  Widget build(BuildContext context) {
    final servoSection = <Widget>[
      const _StatusBanner(),
      const SectionHeader('Servos'),
      for (final (index, servo) in widget.servos.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ServoAngleField(
            index: index,
            servo: servo,
            fieldKey: _fieldKeys[servo.id]!,
            controller: _controller.fieldFor(servo),
            validator: (value) => _controller.validate(servo, value),
            onSend: () => _sendServo(servo),
          ),
        ),
    ];
    final actionBar = _ActionBar(onReset: _reset, onSendAll: _sendAll);

    // Decide the layout from the screen size (not the keyboard-reduced
    // constraints) so opening the keyboard never rebuilds the tree and
    // steals focus from a text field.
    final compact = MediaQuery.sizeOf(context).height < 520;

    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (compact) {
            // Short screens (landscape phones): everything scrolls together.
            return ListView(
              children: [
                PageBody(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Column(children: servoSection),
                  ),
                ),
                actionBar,
                const CommandConsole(logHeight: 140),
              ],
            );
          }

          final logHeight = (constraints.maxHeight * 0.22)
              .clamp(56.0, 200.0)
              .toDouble();
          return Column(
            children: [
              Expanded(
                child: PageBody(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: servoSection,
                  ),
                ),
              ),
              actionBar,
              CommandConsole(logHeight: logHeight),
            ],
          );
        },
      ),
    );
  }
}

/// Top banner: usage hint when connected, connection shortcut otherwise.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final service = CommunicationScope.of(context);
    final status = service.status;

    if (status == ConnectionStatus.connected) {
      final name = service.connectedDevice?.name ?? SfraProtocol.deviceName;
      return _BannerCard(
        color: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
        icon: Icons.info_outline_rounded,
        message:
            'Connected to $name. Type a target angle for each servo, '
            'then send it individually or all at once.',
      );
    }

    final (color, icon) = ConnectionStatusChip.statusVisuals(status, scheme);
    final scanning = service is ScanningCommunicationService ? service : null;
    final navigation = NavigationScope.read(context);

    final message = switch (status) {
      ConnectionStatus.notConfigured =>
        'No communication transport is configured.',
      ConnectionStatus.unavailable =>
        service.statusMessage ?? 'Bluetooth is unavailable.',
      ConnectionStatus.scanning => 'Searching for ${SfraProtocol.deviceName}…',
      ConnectionStatus.connecting => 'Connecting to the robot…',
      _ =>
        'Not connected to ${SfraProtocol.deviceName}. Commands cannot be '
            'sent until the robot is connected.',
    };

    final actions = <Widget>[
      if (status == ConnectionStatus.disconnected)
        FilledButton.tonalIcon(
          onPressed: service.connect,
          icon: const Icon(Icons.bluetooth_searching_rounded),
          label: const Text('Connect'),
        ),
      if (status == ConnectionStatus.unavailable &&
          (scanning?.canEnableAdapter ?? false))
        FilledButton.tonalIcon(
          onPressed: scanning!.enableAdapter,
          icon: const Icon(Icons.bluetooth_rounded),
          label: const Text('Turn on'),
        ),
      if (!status.isBusy)
        TextButton(
          onPressed: () => navigation.goTo(AppPageId.settings),
          child: const Text('Settings'),
        ),
    ];

    return _BannerCard(
      color: color.withValues(alpha: 0.12),
      foreground: scheme.onSurface,
      iconColor: color,
      icon: icon,
      busy: status.isBusy,
      message: message,
      actions: actions,
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.color,
    required this.foreground,
    required this.icon,
    required this.message,
    this.iconColor,
    this.busy = false,
    this.actions = const [],
  });

  final Color color;
  final Color foreground;
  final Color? iconColor;
  final IconData icon;
  final String message;
  final bool busy;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (busy)
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: iconColor ?? foreground,
                      ),
                    ),
                  )
                else
                  Icon(icon, color: iconColor ?? foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, runSpacing: 8, children: actions),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onReset, required this.onSendAll});

  final VoidCallback onReset;
  final VoidCallback onSendAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainer,
      child: PageBody(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: onSendAll,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send all'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
