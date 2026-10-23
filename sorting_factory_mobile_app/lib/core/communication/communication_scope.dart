import 'package:flutter/widgets.dart';

import 'robot_communication_service.dart';

/// Exposes the active [RobotCommunicationService] to the widget tree.
class CommunicationScope extends InheritedNotifier<RobotCommunicationService> {
  const CommunicationScope({
    super.key,
    required RobotCommunicationService service,
    required super.child,
  }) : super(notifier: service);

  /// Returns the service and rebuilds [context] when its state changes
  /// (e.g. connection status). Use inside `build` methods.
  static RobotCommunicationService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<CommunicationScope>();
    assert(scope != null, 'No CommunicationScope found in the widget tree.');
    return scope!.notifier!;
  }

  /// Returns the service without subscribing to changes.
  /// Use inside callbacks such as `onPressed`.
  static RobotCommunicationService read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<CommunicationScope>();
    assert(scope != null, 'No CommunicationScope found in the widget tree.');
    return scope!.notifier!;
  }
}
