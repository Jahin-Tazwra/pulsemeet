import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pulsemeet/models/pulse.dart';

/// A service to notify listeners when pulses are created or updated
class PulseNotifier {
  // Singleton instance
  static final PulseNotifier _instance = PulseNotifier._internal();
  
  factory PulseNotifier() => _instance;
  
  PulseNotifier._internal();
  
  // Stream controller for pulse creation events
  final _pulseCreatedController = StreamController<Pulse>.broadcast();
  
  /// Stream of pulse creation events
  Stream<Pulse> get onPulseCreated => _pulseCreatedController.stream;
  
  /// Notify listeners that a pulse was created
  void notifyPulseCreated(Pulse pulse) {
    debugPrint('PulseNotifier: Notifying pulse created: ${pulse.id}');
    _pulseCreatedController.add(pulse);
  }
  
  /// Dispose resources
  void dispose() {
    _pulseCreatedController.close();
  }
}
