import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Performance monitoring widget to track chat loading and sending times
class PerformanceMonitor extends StatefulWidget {
  final Widget child;
  final String screenName;

  const PerformanceMonitor({
    Key? key,
    required this.child,
    required this.screenName,
  }) : super(key: key);

  @override
  State<PerformanceMonitor> createState() => _PerformanceMonitorState();
}

class _PerformanceMonitorState extends State<PerformanceMonitor> {
  final Map<String, Stopwatch> _timers = {};
  final List<PerformanceMetric> _metrics = [];
  bool _showMetrics = false;

  @override
  void initState() {
    super.initState();
    _startTimer('Screen_Load_${widget.screenName}');
  }

  void _startTimer(String operation) {
    _timers[operation] = Stopwatch()..start();
    debugPrint('🚀 PERF: Started timing $operation');
  }

  void _stopTimer(String operation) {
    final timer = _timers[operation];
    if (timer != null) {
      timer.stop();
      final metric = PerformanceMetric(
        operation: operation,
        duration: timer.elapsedMilliseconds,
        timestamp: DateTime.now(),
      );
      _metrics.add(metric);
      debugPrint('⏱️ PERF: $operation took ${timer.elapsedMilliseconds}ms');
      _timers.remove(operation);
      
      // Keep only last 20 metrics
      if (_metrics.length > 20) {
        _metrics.removeAt(0);
      }
      
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        
        // Performance overlay (only in debug mode)
        if (kDebugMode)
          Positioned(
            top: 50,
            right: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Toggle button
                FloatingActionButton.small(
                  onPressed: () => setState(() => _showMetrics = !_showMetrics),
                  backgroundColor: Colors.black87,
                  child: Icon(
                    _showMetrics ? Icons.close : Icons.speed,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                
                // Metrics panel
                if (_showMetrics)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(
                      maxWidth: 300,
                      maxHeight: 400,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Performance Metrics',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        
                        // Current timers
                        if (_timers.isNotEmpty) ...[
                          Text(
                            'Running:',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ..._timers.entries.map((entry) => Text(
                            '${entry.key}: ${entry.value.elapsedMilliseconds}ms',
                            style: TextStyle(color: Colors.orange, fontSize: 10),
                          )),
                          const SizedBox(height: 8),
                        ],
                        
                        // Recent metrics
                        Text(
                          'Recent:',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _metrics.reversed.take(10).map((metric) {
                                final color = metric.duration < 100 
                                    ? Colors.green 
                                    : metric.duration < 500 
                                        ? Colors.orange 
                                        : Colors.red;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '${metric.operation}: ${metric.duration}ms',
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        
                        // Quick actions
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                _startTimer('Manual_Chat_Load_Test');
                                // You can trigger chat loading here
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                              child: Text(
                                'Test Chat Load',
                                style: TextStyle(fontSize: 10, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 4),
                            ElevatedButton(
                              onPressed: () {
                                _startTimer('Manual_Message_Send_Test');
                                // You can trigger message sending here
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                              child: Text(
                                'Test Send',
                                style: TextStyle(fontSize: 10, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _stopTimer('Screen_Load_${widget.screenName}');
    super.dispose();
  }
}

class PerformanceMetric {
  final String operation;
  final int duration;
  final DateTime timestamp;

  PerformanceMetric({
    required this.operation,
    required this.duration,
    required this.timestamp,
  });
}

/// Extension to easily add performance monitoring to any widget
extension PerformanceMonitorExtension on Widget {
  Widget withPerformanceMonitor(String screenName) {
    return PerformanceMonitor(
      screenName: screenName,
      child: this,
    );
  }
}
