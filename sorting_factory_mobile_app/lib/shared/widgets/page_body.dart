import 'package:flutter/widgets.dart';

/// Centers page content and caps its width so pages look good on tablets
/// and desktops as well as phones.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 840});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
