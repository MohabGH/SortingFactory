/// Connection state between the app and the microcontroller.
enum ConnectionStatus {
  /// No communication protocol/transport has been implemented yet.
  notConfigured('Not configured'),
  disconnected('Disconnected'),
  connecting('Connecting…'),
  connected('Connected');

  const ConnectionStatus(this.label);

  final String label;
}
