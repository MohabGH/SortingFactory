import 'package:flutter/widgets.dart';

import 'navigation_controller.dart';

/// Exposes the [NavigationController] to the widget tree.
class NavigationScope extends InheritedNotifier<NavigationController> {
  const NavigationScope({
    super.key,
    required NavigationController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Returns the controller and rebuilds [context] when the page changes.
  /// Use inside `build` methods.
  static NavigationController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<NavigationScope>();
    assert(scope != null, 'No NavigationScope found in the widget tree.');
    return scope!.notifier!;
  }

  /// Returns the controller without subscribing to changes.
  /// Use inside callbacks such as `onPressed`.
  static NavigationController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<NavigationScope>();
    assert(scope != null, 'No NavigationScope found in the widget tree.');
    return scope!.notifier!;
  }
}
