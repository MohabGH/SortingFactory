import 'package:flutter/foundation.dart';

import 'app_page_id.dart';

/// Holds the page currently displayed by the app shell.
///
/// This replaces Navigator-based routing: changing [current] makes the shell
/// substitute its body with the requested page.
class NavigationController extends ChangeNotifier {
  NavigationController({AppPageId initialPage = AppPageId.home})
      : _current = initialPage;

  AppPageId _current;

  AppPageId get current => _current;

  /// Shows [page]. Does nothing if [page] is already visible.
  ///
  /// Returns `true` if the visible page changed.
  bool goTo(AppPageId page) {
    if (page == _current) return false;
    _current = page;
    notifyListeners();
    return true;
  }
}
