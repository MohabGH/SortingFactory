import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/robot/servo_config.dart';

/// Card with a servo's name, its allowed range, an angle input and a
/// button to send that single angle.
class ServoAngleField extends StatelessWidget {
  const ServoAngleField({
    super.key,
    required this.index,
    required this.servo,
    required this.fieldKey,
    required this.controller,
    required this.validator,
    required this.onSend,
  });

  final int index;
  final ServoConfig servo;
  final GlobalKey<FormFieldState<String>> fieldKey;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      servo.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Range ${servo.minAngle}° – ${servo.maxAngle}°',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 104,
              child: TextFormField(
                key: fieldKey,
                controller: controller,
                validator: validator,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                style: theme.textTheme.titleMedium,
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: '°',
                  hintText: '${servo.initialAngle}',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Send ${servo.name} angle',
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
