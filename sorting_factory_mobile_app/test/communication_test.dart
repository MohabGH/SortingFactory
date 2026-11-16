import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorting_factory_mobile_app/app/app.dart';
import 'package:sorting_factory_mobile_app/core/communication/communication_log.dart';
import 'package:sorting_factory_mobile_app/core/communication/connection_status.dart';
import 'package:sorting_factory_mobile_app/core/communication/robot_command.dart';
import 'package:sorting_factory_mobile_app/core/communication/robot_communication_service.dart';
import 'package:sorting_factory_mobile_app/core/communication/sfra_protocol.dart';
import 'package:sorting_factory_mobile_app/core/communication/sfra_session.dart';
import 'package:sorting_factory_mobile_app/features/manual_control/widgets/command_console.dart';

/// In-memory transport that behaves like the SFRA_ESP firmware.
class FakeRobotService extends RobotCommunicationService {
  FakeRobotService({bool connected = true}) {
    session.addListener(notifyListeners);
    if (connected) {
      _status = ConnectionStatus.connected;
      session.start();
    }
  }

  @override
  final CommunicationLog log = CommunicationLog();
  late final SfraSession session = SfraSession(log: log);
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final List<String> written = [];

  @override
  String get transportName => 'Fake';
  @override
  ConnectionStatus get status => _status;
  @override
  RobotActivity get activity => session.activity;
  @override
  ConnectedDeviceInfo? get connectedDevice => isConnected
      ? const ConnectedDeviceInfo(name: 'SFRA_ESP', id: 'AA:BB', mtu: 517)
      : null;

  @override
  Future<void> connect() async {
    _status = ConnectionStatus.connected;
    session.start();
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    _status = ConnectionStatus.disconnected;
    session.stop();
    notifyListeners();
  }

  @override
  Future<void> send(RobotCommand command) async {
    final text = SfraProtocol.encode(command);
    if (!isConnected) throw const CommunicationException('Not connected');
    session.willSend(text);
    written.add(text);
  }

  /// Simulates a notification from the ESP32.
  void reply(String text) => session.addBytes('$text\r\n'.codeUnits);

  @override
  void dispose() {
    session.dispose();
    log.dispose();
    super.dispose();
  }
}

void main() {
  group('SfraProtocol', () {
    test('encodes commands like the firmware expects', () {
      expect(
        SfraProtocol.encode(const SetServoAngleCommand(servoId: 2, angle: 45)),
        '2:45',
      );
      expect(
        SfraProtocol.encode(SetServoAnglesCommand({3: 10, 0: 90, 1: 180})),
        '0:90,1:180,3:10',
      );
      expect(SfraProtocol.encode(const RawTextCommand('  0:1 ')), '0:1');
    });

    test('validate mirrors parseCommand()', () {
      for (final ok in ['0:90', '0:90,5:0', ' 1 : 2 , 3:4 ', '0:90,']) {
        expect(SfraProtocol.validate(ok), isNull, reason: ok);
      }
      for (final bad in [
        '',
        'hello',
        '6:90',
        '0:181',
        '0:-1',
        ':90',
        '0:',
        '0:9a',
        '0:90,,1:2',
        '0:90,1',
      ]) {
        expect(SfraProtocol.validate(bad), isNotNull, reason: bad);
      }
    });

    test('classifies replies', () {
      expect(SfraProtocol.parseResponse('Moving...'), DeviceResponse.moving);
      expect(SfraProtocol.parseResponse('DONE'), DeviceResponse.done);
      expect(
        SfraProtocol.parseResponse('ERROR, Try again'),
        DeviceResponse.error,
      );
      expect(SfraProtocol.parseResponse('hi'), DeviceResponse.unknown);
    });
  });

  group('SfraSession', () {
    test('splits CRLF lines across notifications and tracks activity', () {
      final log = CommunicationLog();
      final session = SfraSession(log: log)..start();
      session.willSend('0:90');
      expect(session.activity, RobotActivity.awaitingResponse);

      session.addBytes('Mov'.codeUnits);
      session.addBytes('ing...\r\nDO'.codeUnits);
      expect(session.activity, RobotActivity.moving);
      session.addBytes('NE\r\n'.codeUnits);
      expect(session.activity, RobotActivity.idle);

      expect(log.entries.map((e) => (e.direction, e.text)), [
        (LogDirection.sent, '0:90'),
        (LogDirection.received, 'Moving...'),
        (LogDirection.received, 'DONE'),
      ]);
      session.dispose();
    });

    test('error reply returns to idle', () {
      final session = SfraSession(log: CommunicationLog())..start();
      session.willSend('bad');
      session.addBytes('ERROR, Try again\r\n'.codeUnits);
      expect(session.activity, RobotActivity.idle);
      session.dispose();
    });

    test('times out when the robot stays silent', () async {
      final log = CommunicationLog();
      final session = SfraSession(
        log: log,
        responseTimeout: const Duration(milliseconds: 20),
      )..start();
      session.willSend('0:90');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(session.activity, RobotActivity.idle);
      expect(log.entries.last.direction, LogDirection.error);
      session.dispose();
    });
  });

  group('Manual control command window', () {
    Future<FakeRobotService> openManual(
      WidgetTester tester, {
      bool connected = true,
    }) async {
      // Disposed by RobotArmApp when the widget tree is torn down.
      final service = FakeRobotService(connected: connected);
      await tester.pumpWidget(RobotArmApp(communicationService: service));
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationDrawer),
          matching: find.text('Manual Control'),
        ),
      );
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('shows sent commands and received replies', (tester) async {
      final service = await openManual(tester);
      expect(find.byType(CommandConsole), findsOneWidget);

      await tester.tap(find.text('Send all'));
      await tester.pump();
      expect(service.written, ['0:90,1:90,2:90,3:90,4:90,5:90']);
      expect(find.textContaining('0:90,1:90,2:90'), findsOneWidget);

      service.reply('Moving...');
      service.reply('DONE');
      await tester.pump();
      expect(find.textContaining('Moving...'), findsWidgets);
      expect(find.textContaining('DONE'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
    });

    testWidgets('sends raw text typed in the console', (tester) async {
      final service = await openManual(tester);

      await tester.enterText(
        find.byKey(const ValueKey('console-input')),
        '3:120',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send command'));
      await tester.pump();
      expect(service.written, ['3:120']);

      service.reply('ERROR, Try again');
      await tester.pump();
      expect(find.textContaining('ERROR, Try again'), findsOneWidget);
    });

    testWidgets('warns when sending while disconnected', (tester) async {
      await openManual(tester, connected: false);
      expect(find.text('Connect'), findsOneWidget);

      await tester.tap(find.text('Send all'));
      await tester.pump();
      expect(find.text('Not connected'), findsWidgets);
    });

    testWidgets('clear empties the log', (tester) async {
      final service = await openManual(tester);
      await tester.tap(find.text('Send all'));
      await tester.pump();
      expect(service.log.isEmpty, isFalse);

      await tester.tap(find.byTooltip('Clear log'));
      await tester.pump();
      expect(service.log.isEmpty, isTrue);
    });
  });
}
