import 'package:flutter/widgets.dart';
import 'package:sorting_factory_mobile_app/app/app.dart';
import 'package:sorting_factory_mobile_app/core/communication/ble_communication_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(RobotArmApp(communicationService: BleCommunicationService()));
}
