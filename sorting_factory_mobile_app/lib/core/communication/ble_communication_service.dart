import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'communication_log.dart';
import 'connection_status.dart';
import 'robot_command.dart';
import 'robot_communication_service.dart';
import 'sfra_protocol.dart';
import 'sfra_session.dart';

/// Talks to the `SFRA_ESP` firmware over Bluetooth Low Energy.
///
/// * Scans for devices advertising the SFRA service UUID or the
///   `SFRA_ESP` name.
/// * Connects, discovers the UART service, subscribes to the TX
///   characteristic (notifications) and writes commands to the RX
///   characteristic.
/// * Every exchanged line is recorded in [log]; replies drive [activity].
class BleCommunicationService extends ScanningCommunicationService {
  BleCommunicationService({
    this.scanTimeout = const Duration(seconds: 8),
    this.connectTimeout = const Duration(seconds: 15),
  }) {
    _session.addListener(notifyListeners);
    _init();
  }

  final Duration scanTimeout;
  final Duration connectTimeout;

  static final Guid _serviceGuid = Guid(SfraProtocol.serviceUuid);
  static final Guid _rxGuid = Guid(SfraProtocol.rxCharacteristicUuid);
  static final Guid _txGuid = Guid(SfraProtocol.txCharacteristicUuid);

  @override
  final CommunicationLog log = CommunicationLog();
  late final SfraSession _session = SfraSession(log: log);

  bool _supported = true;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  bool _isScanning = false;
  bool _connecting = false;
  bool _ready = false;
  bool _userDisconnect = false;
  bool _disposed = false;

  final Map<String, DiscoveredDevice> _found = {};
  Completer<DiscoveredDevice?>? _robotSearch;

  BluetoothDevice? _device;
  String _deviceName = '';
  BluetoothCharacteristic? _rx;

  /// Last device successfully connected, used by [connect] to reconnect.
  DiscoveredDevice? _lastDevice;

  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<bool>? _scanningSub;
  StreamSubscription<List<ScanResult>>? _resultsSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  @override
  String get transportName => 'Bluetooth Low Energy';

  bool get _adapterUsable =>
      _supported &&
      (_adapterState == BluetoothAdapterState.on ||
          _adapterState == BluetoothAdapterState.unknown);

  @override
  ConnectionStatus get status {
    if (!_adapterUsable) return ConnectionStatus.unavailable;
    if (_ready) return ConnectionStatus.connected;
    if (_connecting) return ConnectionStatus.connecting;
    if (_isScanning) return ConnectionStatus.scanning;
    return ConnectionStatus.disconnected;
  }

  @override
  String? get statusMessage {
    if (!_supported) return 'This device does not support Bluetooth LE.';
    return switch (_adapterState) {
      BluetoothAdapterState.off ||
      BluetoothAdapterState.turningOff => 'Bluetooth is turned off.',
      BluetoothAdapterState.turningOn => 'Bluetooth is turning on…',
      BluetoothAdapterState.unauthorized =>
        'Bluetooth permission denied. Allow "Nearby devices" for this app '
            'in the system settings.',
      BluetoothAdapterState.unavailable =>
        'Bluetooth is not available on this device.',
      _ when _ready => null,
      _ when _connecting => 'Establishing link and discovering services…',
      _ when _isScanning => 'Looking for ${SfraProtocol.deviceName}…',
      _ => null,
    };
  }

  @override
  RobotActivity get activity => _session.activity;

  @override
  ConnectedDeviceInfo? get connectedDevice {
    final device = _device;
    if (!_ready || device == null) return null;
    return ConnectedDeviceInfo(
      name: _deviceName,
      id: device.remoteId.str,
      mtu: device.mtuNow,
    );
  }

  @override
  bool get isScanning => _isScanning;

  @override
  List<DiscoveredDevice> get discoveredDevices =>
      _found.values.toList()..sort((a, b) {
        if (a.isRobot != b.isRobot) return a.isRobot ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });

  @override
  bool get canEnableAdapter =>
      _supported && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // ---------------------------------------------------------------------------
  // Initialisation & radio
  // ---------------------------------------------------------------------------

  Future<void> _init() async {
    try {
      _supported = await FlutterBluePlus.isSupported;
    } catch (_) {
      _supported = false;
    }
    if (_disposed) return;
    if (!_supported) {
      log.error('Bluetooth LE is not supported on this device.');
      notifyListeners();
      return;
    }
    unawaited(
      FlutterBluePlus.setLogLevel(
        LogLevel.warning,
        color: false,
      ).catchError((Object _) {}),
    );
    _adapterSub = FlutterBluePlus.adapterState.listen(_onAdapterState);
    _scanningSub = FlutterBluePlus.isScanning.listen(_onScanningChanged);
    _resultsSub = FlutterBluePlus.onScanResults.listen(
      _onScanResults,
      onError: (Object e) => log.error('Scan error: ${_describe(e)}'),
    );
  }

  void _onAdapterState(BluetoothAdapterState state) {
    final previous = _adapterState;
    _adapterState = state;
    if (state == BluetoothAdapterState.off &&
        previous != BluetoothAdapterState.unknown &&
        previous != BluetoothAdapterState.off) {
      log.info('Bluetooth turned off.');
      if (_ready || _device != null) {
        _handleDisconnected('Bluetooth turned off');
      }
    } else if (state == BluetoothAdapterState.on &&
        (previous == BluetoothAdapterState.off ||
            previous == BluetoothAdapterState.turningOn)) {
      log.info('Bluetooth turned on.');
    } else if (state == BluetoothAdapterState.unauthorized) {
      log.error('Bluetooth permission denied.');
    }
    notifyListeners();
  }

  @override
  Future<void> enableAdapter() async {
    if (!canEnableAdapter) return;
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      log.error('Could not turn Bluetooth on: ${_describe(e)}');
    }
  }

  /// Returns `false` (and logs why) when the radio cannot be used.
  bool _ensureRadio(String action) {
    if (_adapterUsable) return true;
    log.error('Cannot $action: ${statusMessage ?? 'Bluetooth unavailable.'}');
    return false;
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  @override
  Future<void> startScan({bool onlyRobots = true}) async {
    if (!_ensureRadio('scan')) return;
    _found.clear();
    notifyListeners();
    try {
      await FlutterBluePlus.startScan(
        // Filters are OR-ed: match the advertised service or the name.
        withServices: onlyRobots ? [_serviceGuid] : const [],
        withNames: onlyRobots ? const [SfraProtocol.deviceName] : const [],
        timeout: scanTimeout,
      );
    } catch (e) {
      log.error('Scan failed: ${_describe(e)}');
      _completeRobotSearch(null);
    }
  }

  @override
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // Already stopped or radio gone: nothing to do.
    }
  }

  void _onScanningChanged(bool _) {
    // Use the authoritative current value: stale events can be delivered
    // after a scan was restarted.
    final scanning = FlutterBluePlus.isScanningNow;
    if (_isScanning == scanning) return;
    _isScanning = scanning;
    if (!scanning) _completeRobotSearch(null);
    notifyListeners();
  }

  void _onScanResults(List<ScanResult> results) {
    for (final r in results) {
      final adv = r.advertisementData;
      final name = adv.advName.isNotEmpty ? adv.advName : r.device.platformName;
      final device = DiscoveredDevice(
        id: r.device.remoteId.str,
        name: name,
        rssi: r.rssi,
        isRobot:
            name == SfraProtocol.deviceName ||
            adv.serviceUuids.contains(_serviceGuid),
      );
      _found[device.id] = device;
      if (device.isRobot) _completeRobotSearch(device);
    }
    notifyListeners();
  }

  void _completeRobotSearch(DiscoveredDevice? device) {
    final search = _robotSearch;
    if (search != null && !search.isCompleted) search.complete(device);
  }

  /// Scans until a robot is found or the scan times out.
  Future<DiscoveredDevice?> _searchRobot() async {
    log.info('Searching for ${SfraProtocol.deviceName}…');
    final search = _robotSearch = Completer<DiscoveredDevice?>();
    await startScan();
    final found = await search.future.timeout(
      scanTimeout + const Duration(seconds: 2),
      onTimeout: () => null,
    );
    _robotSearch = null;
    return found;
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect() async {
    if (_ready || _connecting) return;
    if (!_ensureRadio('connect')) return;

    final remembered = _lastDevice;
    if (remembered != null) {
      await connectTo(remembered);
      if (_ready || _disposed) return;
      _lastDevice = null; // Stale id: fall back to a fresh search.
    }

    final target =
        _found.values.where((d) => d.isRobot).firstOrNull ??
        await _searchRobot();
    if (_disposed) return;
    if (target == null) {
      log.error(
        '${SfraProtocol.deviceName} not found. Make sure the ESP32 is '
        'powered and its blue LED is blinking (advertising).',
      );
      await stopScan();
      return;
    }
    await connectTo(target);
  }

  @override
  Future<void> connectTo(DiscoveredDevice target) async {
    if (_connecting) return;
    if (!_ensureRadio('connect')) return;
    if (_ready) {
      if (_device?.remoteId.str == target.id) return;
      await disconnect();
    }

    _connecting = true;
    _userDisconnect = false;
    notifyListeners();
    await stopScan();

    final device = BluetoothDevice.fromId(target.id);
    _device = device;
    _deviceName = target.name.isNotEmpty
        ? target.name
        : SfraProtocol.deviceName;
    log.info('Connecting to ${target.displayName} (${target.id})…');

    try {
      // On Android this also requests a 512-byte MTU right after connecting.
      await device.connect(license: License.nonprofit, timeout: connectTimeout);
      if (_disposed) return;

      final services = await device.discoverServices();
      final service = services.where((s) => s.uuid == _serviceGuid).firstOrNull;
      if (service == null) {
        throw const CommunicationException(
          'Device does not expose the SFRA UART service.',
        );
      }
      final rx = service.characteristics
          .where((c) => c.uuid == _rxGuid)
          .firstOrNull;
      final tx = service.characteristics
          .where((c) => c.uuid == _txGuid)
          .firstOrNull;
      if (rx == null || tx == null) {
        throw const CommunicationException(
          'RX/TX characteristics not found on the device.',
        );
      }

      _notifySub = tx.onValueReceived.listen(_session.addBytes);
      device.cancelWhenDisconnected(_notifySub!);
      await tx.setNotifyValue(true);
      if (_disposed) return;

      _rx = rx;
      _ready = true;
      _lastDevice = target;
      // The stream replays the current state, so a link dropped during the
      // setup above is still detected.
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          final reason = device.disconnectReason?.description;
          _handleDisconnected(_userDisconnect ? null : reason);
        }
      });
      _session.start();
      log.info('Connected to $_deviceName · MTU ${device.mtuNow}.');
    } catch (e) {
      if (_disposed) return;
      log.error('Connection failed: ${_describe(e)}');
      _teardown();
      try {
        await device.disconnect();
      } catch (_) {}
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  @override
  Future<void> disconnect() async {
    final device = _device;
    if (device == null) return;
    _userDisconnect = true;
    try {
      await device.disconnect();
    } catch (e) {
      log.error('Disconnect failed: ${_describe(e)}');
    }
    _handleDisconnected(null);
  }

  /// Idempotent clean-up after the link went down. [reason] is `null` for
  /// user-initiated disconnections.
  void _handleDisconnected(String? reason) {
    if (!_ready && _device == null) return;
    final wasReady = _ready;
    _teardown();
    if (wasReady) {
      if (_userDisconnect || reason == null) {
        log.info('Disconnected.');
      } else {
        log.error('Connection lost: $reason');
      }
    }
    notifyListeners();
  }

  void _teardown() {
    _connectionSub?.cancel();
    _connectionSub = null;
    _notifySub?.cancel();
    _notifySub = null;
    _rx = null;
    _ready = false;
    _device = null;
    _session.stop();
  }

  // ---------------------------------------------------------------------------
  // Messaging
  // ---------------------------------------------------------------------------

  @override
  Future<void> send(RobotCommand command) async {
    final text = SfraProtocol.encode(command);
    if (text.isEmpty) {
      throw const CommunicationException('Nothing to send.');
    }

    final rx = _rx;
    final device = _device;
    if (!_ready || rx == null || device == null) {
      const message = 'Not connected to the robot.';
      log.error('$message "$text" was not sent.');
      throw const CommunicationException(message);
    }
    if (text.codeUnits.any((c) => c < 32 || c > 126)) {
      const message = 'Only plain ASCII text can be sent.';
      log.error('$message "$text" was not sent.');
      throw const CommunicationException(message);
    }

    final bytes = ascii.encode(text);
    _session.willSend(text);
    try {
      // Each write is parsed as one complete command by the firmware, so it
      // must never be split. Payloads larger than the MTU use a BLE long
      // (prepared) write, which the ESP32 reassembles before onWrite().
      await rx.write(bytes, allowLongWrite: bytes.length > device.mtuNow - 3);
    } catch (e) {
      final reason = _describe(e);
      _session.sendFailed(reason);
      throw CommunicationException('Send failed: $reason');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _describe(Object error) => switch (error) {
    FlutterBluePlusException(:final description, :final function) =>
      description ?? function,
    CommunicationException(:final message) => message,
    TimeoutException() => 'timed out',
    _ => error.toString(),
  };

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _adapterSub?.cancel();
    _scanningSub?.cancel();
    _resultsSub?.cancel();
    _connectionSub?.cancel();
    _notifySub?.cancel();
    _completeRobotSearch(null);
    final device = _device;
    if (device != null) unawaited(device.disconnect().catchError((_) {}));
    _session
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
