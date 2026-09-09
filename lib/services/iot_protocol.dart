class IotProtocol {
  IotProtocol._();

  /// Number of physical dispenser compartments (DIP switches 1-7 on the ESP32).
  static const int totalPositions = 7;

  static const String statusDispensed = 'DISPENSED';

  /// Builds the command sent to the ESP32 for one submitted request.
  ///
  /// The command is a fixed-width string with one 2-digit quantity per
  /// compartment position (1-7, in order), e.g. requesting 3 units from
  /// position 1 and 1 unit from position 4 produces "03000001000000".
  /// The ESP32 firmware reads 2 characters per slot and repeats its existing
  /// pickup routine (rotate to position, lower actuator, magnet on/off,
  /// raise, re-home) that many times before moving to the next slot,
  /// replacing manual DIP switch presses.
  static String buildDispenseCommand(Map<String, int> quantityByPosition) {
    final buffer = StringBuffer();
    for (var position = 1; position <= totalPositions; position++) {
      final quantity = quantityByPosition[position.toString()] ?? 0;
      buffer.write(quantity.clamp(0, 99).toString().padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

