import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Comprehensive performance monitoring service for chat system
/// 
/// This service provides:
/// - Real-time performance metrics tracking
/// - Automated performance regression detection
/// - Performance dashboard data
/// - Alert system for performance issues
class PerformanceMonitoringService {
  static final PerformanceMonitoringService _instance = PerformanceMonitoringService._internal();
  factory PerformanceMonitoringService() => _instance;
  PerformanceMonitoringService._internal();

  // Performance targets (in milliseconds)
  static const Map<String, int> _performanceTargets = {
    'chat_initialization': 500,
    'message_status_update': 50,
    'message_send_ui': 100,
    'mark_as_read': 50,
    'cache_hit': 10,
    'message_decryption': 100,
  };

  // Performance data storage
  final Map<String, Queue<PerformanceMetric>> _metrics = {};
  final Map<String, PerformanceAlert> _activeAlerts = {};
  final StreamController<PerformanceUpdate> _updateController = StreamController.broadcast();

  // Configuration
  static const int _maxMetricsPerType = 1000;
  static const Duration _alertCooldown = Duration(minutes: 5);
  static const double _regressionThreshold = 1.5; // 50% performance degradation

  /// Stream of performance updates
  Stream<PerformanceUpdate> get performanceUpdates => _updateController.stream;

  /// Record a performance metric
  void recordMetric(String metricType, int durationMs, {Map<String, dynamic>? metadata}) {
    final metric = PerformanceMetric(
      type: metricType,
      durationMs: durationMs,
      timestamp: DateTime.now(),
      metadata: metadata ?? {},
    );

    // Store metric
    if (!_metrics.containsKey(metricType)) {
      _metrics[metricType] = Queue<PerformanceMetric>();
    }

    _metrics[metricType]!.add(metric);

    // Maintain size limit
    if (_metrics[metricType]!.length > _maxMetricsPerType) {
      _metrics[metricType]!.removeFirst();
    }

    // Check for performance issues
    _checkPerformanceThresholds(metricType, durationMs);
    _checkForRegressions(metricType);

    // Emit update
    _updateController.add(PerformanceUpdate(
      metricType: metricType,
      currentValue: durationMs,
      target: _performanceTargets[metricType],
      isWithinTarget: _isWithinTarget(metricType, durationMs),
      timestamp: DateTime.now(),
    ));

    if (kDebugMode && _shouldLogMetric(metricType, durationMs)) {
      debugPrint('📊 PERFORMANCE: ${metricType} took ${durationMs}ms (target: ${_performanceTargets[metricType]}ms)');
    }
  }

  /// Check if metric is within performance target
  bool _isWithinTarget(String metricType, int durationMs) {
    final target = _performanceTargets[metricType];
    return target == null || durationMs <= target;
  }

  /// Check performance thresholds and trigger alerts
  void _checkPerformanceThresholds(String metricType, int durationMs) {
    final target = _performanceTargets[metricType];
    if (target == null) return;

    if (durationMs > target * 2) {
      // Critical performance issue
      _triggerAlert(metricType, AlertSeverity.critical, 
          'Performance critical: ${metricType} took ${durationMs}ms (target: ${target}ms)');
    } else if (durationMs > target * 1.5) {
      // Warning level performance issue
      _triggerAlert(metricType, AlertSeverity.warning,
          'Performance warning: ${metricType} took ${durationMs}ms (target: ${target}ms)');
    }
  }

  /// Check for performance regressions
  void _checkForRegressions(String metricType) {
    final metrics = _metrics[metricType];
    if (metrics == null || metrics.length < 10) return;

    // Calculate recent average (last 5 metrics)
    final recentMetrics = metrics.toList().reversed.take(5).toList();
    final recentAverage = recentMetrics.map((m) => m.durationMs).reduce((a, b) => a + b) / recentMetrics.length;

    // Calculate baseline average (metrics 10-20 from end)
    final baselineMetrics = metrics.toList().reversed.skip(5).take(10).toList();
    if (baselineMetrics.length < 10) return;

    final baselineAverage = baselineMetrics.map((m) => m.durationMs).reduce((a, b) => a + b) / baselineMetrics.length;

    // Check for regression
    if (recentAverage > baselineAverage * _regressionThreshold) {
      _triggerAlert(metricType, AlertSeverity.regression,
          'Performance regression detected: ${metricType} average increased from ${baselineAverage.round()}ms to ${recentAverage.round()}ms');
    }
  }

  /// Trigger performance alert
  void _triggerAlert(String metricType, AlertSeverity severity, String message) {
    final existingAlert = _activeAlerts[metricType];
    
    // Check cooldown period
    if (existingAlert != null && 
        DateTime.now().difference(existingAlert.timestamp) < _alertCooldown) {
      return;
    }

    final alert = PerformanceAlert(
      metricType: metricType,
      severity: severity,
      message: message,
      timestamp: DateTime.now(),
    );

    _activeAlerts[metricType] = alert;

    debugPrint('🚨 PERFORMANCE ALERT [${severity.name.toUpperCase()}]: $message');

    // Emit alert update
    _updateController.add(PerformanceUpdate(
      metricType: metricType,
      alert: alert,
      timestamp: DateTime.now(),
    ));
  }

  /// Get performance dashboard data
  PerformanceDashboard getDashboardData() {
    final dashboardMetrics = <String, MetricSummary>{};

    for (final entry in _metrics.entries) {
      final metricType = entry.key;
      final metrics = entry.value.toList();
      
      if (metrics.isEmpty) continue;

      final durations = metrics.map((m) => m.durationMs).toList();
      final average = durations.reduce((a, b) => a + b) / durations.length;
      final min = durations.reduce((a, b) => a < b ? a : b);
      final max = durations.reduce((a, b) => a > b ? a : b);
      
      // Calculate percentiles
      durations.sort();
      final p50 = durations[durations.length ~/ 2];
      final p95 = durations[(durations.length * 0.95).round() - 1];
      final p99 = durations[(durations.length * 0.99).round() - 1];

      // Calculate success rate (within target)
      final target = _performanceTargets[metricType];
      final successCount = target != null 
          ? durations.where((d) => d <= target).length 
          : durations.length;
      final successRate = successCount / durations.length;

      dashboardMetrics[metricType] = MetricSummary(
        metricType: metricType,
        average: average.round(),
        min: min,
        max: max,
        p50: p50,
        p95: p95,
        p99: p99,
        target: target,
        successRate: successRate,
        sampleCount: durations.length,
        lastUpdated: metrics.last.timestamp,
      );
    }

    return PerformanceDashboard(
      metrics: dashboardMetrics,
      activeAlerts: _activeAlerts.values.toList(),
      overallHealth: _calculateOverallHealth(dashboardMetrics),
      generatedAt: DateTime.now(),
    );
  }

  /// Calculate overall system health score
  double _calculateOverallHealth(Map<String, MetricSummary> metrics) {
    if (metrics.isEmpty) return 1.0;

    final healthScores = metrics.values.map((metric) {
      if (metric.target == null) return 1.0;
      
      // Health based on success rate and average performance
      final targetRatio = metric.average / metric.target!;
      final healthFromAverage = (2.0 - targetRatio).clamp(0.0, 1.0);
      
      return (metric.successRate + healthFromAverage) / 2.0;
    }).toList();

    return healthScores.reduce((a, b) => a + b) / healthScores.length;
  }

  /// Check if metric should be logged
  bool _shouldLogMetric(String metricType, int durationMs) {
    final target = _performanceTargets[metricType];
    if (target == null) return false;
    
    // Log if exceeds target or is a critical metric
    return durationMs > target || _isCriticalMetric(metricType);
  }

  /// Check if metric type is critical
  bool _isCriticalMetric(String metricType) {
    const criticalMetrics = [
      'chat_initialization',
      'message_status_update',
      'message_send_ui',
    ];
    return criticalMetrics.contains(metricType);
  }

  /// Clear old alerts
  void clearOldAlerts() {
    final now = DateTime.now();
    _activeAlerts.removeWhere((key, alert) => 
        now.difference(alert.timestamp) > const Duration(hours: 1));
  }

  /// Get specific metric history
  List<PerformanceMetric> getMetricHistory(String metricType, {int? limit}) {
    final metrics = _metrics[metricType]?.toList() ?? [];
    if (limit != null && metrics.length > limit) {
      return metrics.reversed.take(limit).toList().reversed.toList();
    }
    return metrics;
  }

  /// Export performance data for analysis
  Map<String, dynamic> exportPerformanceData() {
    final data = <String, dynamic>{};
    
    for (final entry in _metrics.entries) {
      data[entry.key] = entry.value.map((metric) => {
        'duration_ms': metric.durationMs,
        'timestamp': metric.timestamp.toIso8601String(),
        'metadata': metric.metadata,
      }).toList();
    }
    
    return {
      'metrics': data,
      'targets': _performanceTargets,
      'exported_at': DateTime.now().toIso8601String(),
    };
  }

  /// Dispose service
  void dispose() {
    _updateController.close();
    _metrics.clear();
    _activeAlerts.clear();
  }
}

/// Performance metric data structure
class PerformanceMetric {
  final String type;
  final int durationMs;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  PerformanceMetric({
    required this.type,
    required this.durationMs,
    required this.timestamp,
    required this.metadata,
  });
}

/// Performance alert
class PerformanceAlert {
  final String metricType;
  final AlertSeverity severity;
  final String message;
  final DateTime timestamp;

  PerformanceAlert({
    required this.metricType,
    required this.severity,
    required this.message,
    required this.timestamp,
  });
}

/// Alert severity levels
enum AlertSeverity { info, warning, critical, regression }

/// Performance update event
class PerformanceUpdate {
  final String metricType;
  final int? currentValue;
  final int? target;
  final bool? isWithinTarget;
  final PerformanceAlert? alert;
  final DateTime timestamp;

  PerformanceUpdate({
    required this.metricType,
    this.currentValue,
    this.target,
    this.isWithinTarget,
    this.alert,
    required this.timestamp,
  });
}

/// Metric summary for dashboard
class MetricSummary {
  final String metricType;
  final int average;
  final int min;
  final int max;
  final int p50;
  final int p95;
  final int p99;
  final int? target;
  final double successRate;
  final int sampleCount;
  final DateTime lastUpdated;

  MetricSummary({
    required this.metricType,
    required this.average,
    required this.min,
    required this.max,
    required this.p50,
    required this.p95,
    required this.p99,
    this.target,
    required this.successRate,
    required this.sampleCount,
    required this.lastUpdated,
  });
}

/// Performance dashboard data
class PerformanceDashboard {
  final Map<String, MetricSummary> metrics;
  final List<PerformanceAlert> activeAlerts;
  final double overallHealth;
  final DateTime generatedAt;

  PerformanceDashboard({
    required this.metrics,
    required this.activeAlerts,
    required this.overallHealth,
    required this.generatedAt,
  });
}
