import 'package:flutter/material.dart';

import '../core/navigation/app_page_id.dart';
import '../core/navigation/navigation_scope.dart';
import '../shared/widgets/connection_status_chip.dart';
import 'app_destinations.dart';
import 'widgets/app_drawer.dart';

/// The single page of the application.
///
/// Instead of pushing routes with the Navigator, the shell keeps one
/// [Scaffold] alive and swaps its body according to the current
/// [AppPageId] held by the navigation controller.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _onDestinationSelected(AppPageId page) {
    _scaffoldKey.currentState?.closeDrawer();
    // `goTo` ignores requests for the page that is already visible, so
    // selecting the current page only closes the drawer.
    NavigationScope.read(context).goTo(page);
  }

  /// Android back button: close the drawer if open, otherwise return to the
  /// home page. Only exits the app when already on the home page.
  void _onBackPressed(bool didPop, Object? _) {
    if (didPop) return;
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
    NavigationScope.read(context).goTo(AppPageId.home);
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = NavigationScope.of(context).current;
    final destination = AppDestinations.byId(currentPage);

    return PopScope(
      canPop: currentPage == AppPageId.home,
      onPopInvokedWithResult: _onBackPressed,
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text(destination.title),
          actions: const [
            ConnectionStatusChip(),
            SizedBox(width: 12),
          ],
        ),
        drawer: AppDrawer(
          destinations: AppDestinations.all,
          currentPage: currentPage,
          onSelected: _onDestinationSelected,
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey<AppPageId>(destination.id),
            child: destination.builder(context),
          ),
        ),
      ),
    );
  }
}
