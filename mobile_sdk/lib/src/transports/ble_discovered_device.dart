class BleDiscoveredDevice {
  const BleDiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is BleDiscoveredDevice &&
        other.id == id &&
        other.name == name &&
        other.rssi == rssi;
  }

  @override
  int get hashCode => Object.hash(id, name, rssi);
}
