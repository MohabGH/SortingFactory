import 'package:flutter/material.dart';

import '../../core/communication/communication_scope.dart';
import '../../core/communication/connection_status.dart';

/// Pill showing the current microcontroller connection status.
class ConnectionStatusChip extends StatelessWidget {
  const ConnectionStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final status = CommunicationScope.of(context).status;
    final scheme = Theme.of(context).colorScheme;

    final (Color color, IconData icon) = switch (status) {
      ConnectionStatus.connected => (scheme.primary, Icons.link_rounded),
      ConnectionStatus.connecting => (scheme.tertiary, Icons.sync_rounded),
      ConnectionStatus.disconnected => (scheme.error, Icons.link_off_rounded),
      ConnectionStatus.notConfigured => (
          scheme.outline,
          Icons.portable_wifi_off_rounded,
        ),
    };

    return Tooltip(
      message: 'Microcontroller: ${status.label}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              status.label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
