import 'package:flutter/material.dart';

import '../../core/communication/communication_scope.dart';
import '../../core/robot/robot_arm_config.dart';
import '../../core/robot/servo_config.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/section_header.dart';
import 'manual_control_controller.dart';
import 'widgets/servo_angle_field.dart';

/// Manual mode: one text field per servo to type the target angle.
class ManualControlPage extends StatefulWidget {
  const ManualControlPage({super.key, this.servos = RobotArmConfig.servos});

  final List<ServoConfig> servos;

  @override
  State<ManualControlPage> createState() => _ManualControlPageState();
}

class _ManualControlPageState extends State<ManualControlPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final ManualControlController _controller =
      ManualControlController(servos: widget.servos);
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
    // The active service is a no-op until the protocol is specified.
    await CommunicationScope.read(context).send(_controller.commandFor(servo));
  }

  Future<void> _sendAll() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;
    // The active service is a no-op until the protocol is specified.
    await CommunicationScope.read(context).send(_controller.commandForAll());
  }

  void _reset() {
    _controller.resetToInitial();
    // Re-validate so any stale error messages are cleared.
    _formKey.currentState?.validate();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: PageBody(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  const _InfoBanner(),
                  const SectionHeader('Servos'),
                  for (final (index, servo) in widget.servos.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ServoAngleField(
                        index: index,
                        servo: servo,
                        fieldKey: _fieldKeys[servo.id]!,
                        controller: _controller.fieldFor(servo),
                        validator: (value) =>
                            _controller.validate(servo, value),
                        onSend: () => _sendServo(servo),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _ActionBar(onReset: _reset, onSendAll: _sendAll),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded,
                color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Type a target angle for each servo, then send it '
                'individually or all at once.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
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
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
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
      ),
    );
  }
}
