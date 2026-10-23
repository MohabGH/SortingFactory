import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorting_factory_mobile_app/app/app.dart';
import 'package:sorting_factory_mobile_app/features/home/home_page.dart';
import 'package:sorting_factory_mobile_app/features/home/widgets/feature_card.dart';
import 'package:sorting_factory_mobile_app/features/manual_control/manual_control_page.dart';
import 'package:sorting_factory_mobile_app/features/settings/settings_page.dart';

Future<void> _selectFromDrawer(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationDrawer),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts on the home page', (tester) async {
    await tester.pumpWidget(const RobotArmApp());
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('drawer substitutes the page body', (tester) async {
    await tester.pumpWidget(const RobotArmApp());

    await _selectFromDrawer(tester, 'Manual Control');
    expect(find.byType(ManualControlPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(find.byType(NavigationDrawer), findsNothing);

    await _selectFromDrawer(tester, 'Settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(ManualControlPage), findsNothing);
  });

  testWidgets('selecting the current page only closes the drawer',
      (tester) async {
    await tester.pumpWidget(const RobotArmApp());
    await _selectFromDrawer(tester, 'Manual Control');

    await tester.enterText(find.byType(TextFormField).first, '42');
    await _selectFromDrawer(tester, 'Manual Control');

    expect(find.byType(NavigationDrawer), findsNothing);
    // Page state survived, so the page was not rebuilt from scratch.
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('home cards open their feature', (tester) async {
    await tester.pumpWidget(const RobotArmApp());
    await tester.tap(find.widgetWithText(FeatureCard, 'Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('send all validates servo angles', (tester) async {
    await tester.pumpWidget(const RobotArmApp());
    await _selectFromDrawer(tester, 'Manual Control');

    await tester.enterText(find.byType(TextFormField).first, '200');
    await tester.tap(find.text('Send all'));
    await tester.pump();
    expect(find.text('0–180°'), findsOneWidget);
  });
}
