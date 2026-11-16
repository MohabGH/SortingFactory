import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'communication_log.dart';
import 'connection_status.dart';
import 'sfra_protocol.dart';

/// Transport-independent half of the SFRA protocol.
///
/// Feeds every exchanged message into [log], re-assembles the `\r\n`
/// terminated lines notified by the ESP32 and tracks the robot's
/// [activity] from its replies (`Moving...`, `DONE`, `ERROR, Try again`).
class SfraSession extends ChangeNotifier {
  SfraSession({
    required this.log,
    this.responseTimeout = const Duration(seconds: 10),
    this.lineFlushDelay = const Duration(milliseconds: 150),
  });

  final CommunicationLog log;

  /// How long to wait for `Moving...`/`DONE` before giving up. A full
  /// 0°→180° sweep takes 180 × 15 ms ≈ 2.7 s on the firmware.
  final Duration responseTimeout;

  /// Text received without a line terminator is shown after this delay.
  final Duration lineFlushDelay;

  RobotActivity _activity = RobotActivity.offline;
  RobotActivity _activityBeforeSend = RobotActivity.offline;
  String _buffer = '';
  Timer? _responseTimer;
  Timer? _flushTimer;

  RobotActivity get activity => _activity;

  /// Call once the link is ready to exchange commands.
  void start() {
    _buffer = '';
    _setActivity(RobotActivity.idle);
  }

  /// Call when the link is lost or closed.
  void stop() {
    _flushTimer?.cancel();
    _flushPartialLine();
    _responseTimer?.cancel();
    _setActivity(RobotActivity.offline);
  }

  /// Records [text] as sent. Call right before the transport writes it.
  void willSend(String text) {
    if (_activity.isBusy) {
      log.info(
        'Arm still busy: the ESP32 does not queue commands, only the '
        'latest one runs after the current move finishes.',
      );
    }
    log.sent(text);
    _activityBeforeSend = _activity;
    _setActivity(RobotActivity.awaitingResponse);
    _armResponseTimer();
  }

  /// Call when writing the text passed to [willSend] failed.
  void sendFailed(String reason) {
    log.error('Send failed: $reason');
    if (_activity == RobotActivity.awaitingResponse) {
      if (!_activityBeforeSend.isBusy) _responseTimer?.cancel();
      _setActivity(_activityBeforeSend);
    }
  }

  /// Feeds raw bytes notified by the microcontroller.
  void addBytes(List<int> bytes) {
    if (bytes.isEmpty) return;
    _buffer += utf8.decode(bytes, allowMalformed: true);
    _drainLines();
    _flushTimer?.cancel();
    if (_buffer.isNotEmpty) {
      _flushTimer = Timer(lineFlushDelay, _flushPartialLine);
    }
  }

  void _drainLines() {
    while (true) {
      final end = _buffer.indexOf(RegExp(r'[\r\n]'));
      if (end == -1) return;
      final line = _buffer.substring(0, end);
      _buffer = _buffer.substring(end + 1);
      _handleLine(line);
    }
  }

  void _flushPartialLine() {
    if (_buffer.isEmpty) return;
    final line = _buffer;
    _buffer = '';
    _handleLine(line);
  }

  void _handleLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;
    log.received(line);
    switch (SfraProtocol.parseResponse(line)) {
      case DeviceResponse.moving:
        _setActivity(RobotActivity.moving);
        _armResponseTimer();
      case DeviceResponse.done:
      case DeviceResponse.error:
        _responseTimer?.cancel();
        _setActivity(RobotActivity.idle);
      case DeviceResponse.unknown:
        break;
    }
  }

  void _armResponseTimer() {
    _responseTimer?.cancel();
    _responseTimer = Timer(responseTimeout, () {
      if (!_activity.isBusy) return;
      log.error(
        'No reply from the ESP32 within '
        '${responseTimeout.inSeconds} s.',
      );
      _setActivity(RobotActivity.idle);
    });
  }

  void _setActivity(RobotActivity value) {
    if (_activity == value) return;
    _activity = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _responseTimer?.cancel();
    _flushTimer?.cancel();
    super.dispose();
  }
}
