import 'package:flutter/material.dart';

import '../../core/communication/communication_scope.dart';
import '../../core/communication/connection_status.dart';
import '../../core/navigation/app_page_id.dart';
import '../../core/navigation/navigation_scope.dart';

/// Pill showing the current microcontroller connection status.
///
/// Tapping it opens the Settings page, where the connection is managed.
class ConnectionStatusChip extends StatelessWidget {
  const ConnectionStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CommunicationScope.of(context);
    final status = service.status;
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = statusVisuals(status, scheme);
    final device = service.connectedDevice;

    final tooltip = StringBuffer('Robot: ${status.label}');
    if (device != null) tooltip.write(' to ${device.name}');
    if (service.statusMessage case final detail?) tooltip.write('\n$detail');

    return Tooltip(
      message: tooltip.toString(),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => NavigationScope.read(context).goTo(AppPageId.settings),
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
              if (status.isBusy)
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                status.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Color and icon used to represent [status] across the app.
  static (Color, IconData) statusVisuals(
    ConnectionStatus status,
    ColorScheme scheme,
  ) => switch (status) {
    ConnectionStatus.connected => (
      scheme.primary,
      Icons.bluetooth_connected_rounded,
    ),
    ConnectionStatus.connecting => (scheme.tertiary, Icons.sync_rounded),
    ConnectionStatus.scanning => (
      scheme.tertiary,
      Icons.bluetooth_searching_rounded,
    ),
    ConnectionStatus.disconnected => (scheme.error, Icons.link_off_rounded),
    ConnectionStatus.unavailable => (
      scheme.error,
      Icons.bluetooth_disabled_rounded,
    ),
    ConnectionStatus.notConfigured => (
      scheme.outline,
      Icons.portable_wifi_off_rounded,
    ),
  };
}
