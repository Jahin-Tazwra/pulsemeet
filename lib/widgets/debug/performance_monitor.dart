import 'package:flutter/material.dart';
import 'package:pulsemeet/services/conversation_key_cache.dart';
import 'package:pulsemeet/services/optimistic_ui_service.dart';

/// Performance monitoring widget for debugging chat performance
class PerformanceMonitor extends StatefulWidget {
  const PerformanceMonitor({super.key});

  @override
  State<PerformanceMonitor> createState() => _PerformanceMonitorState();
}

class _PerformanceMonitorState extends State<PerformanceMonitor> {
  Map<String, dynamic> _keyStats = {};
  Map<String, dynamic> _uiStats = {};
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _updateStats();
  }

  void _updateStats() {
    setState(() {
      _keyStats = ConversationKeyCache.instance.getCacheStats();
      _uiStats = OptimisticUIService.instance.getStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return FloatingActionButton.small(
        onPressed: () => setState(() => _isVisible = true),
        backgroundColor: Colors.blue.withOpacity(0.8),
        child: const Icon(Icons.speed, color: Colors.white),
      );
    }

    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '⚡ Performance Monitor',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: _updateStats,
                    icon:
                        const Icon(Icons.refresh, color: Colors.blue, size: 20),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _isVisible = false),
                    icon: const Icon(Icons.close, color: Colors.red, size: 20),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Key Cache Stats
          _buildSection(
            '🔑 Key Cache Performance',
            [
              _buildStat(
                  'Total Keys', _keyStats['totalKeys']?.toString() ?? '0'),
              _buildStat(
                  'Valid Keys', _keyStats['validKeys']?.toString() ?? '0'),
              _buildStat('Cache Hit Rate',
                  '${((_keyStats['cacheHitRate'] ?? 0.0) * 100).toStringAsFixed(1)}%'),
              _buildStat('Pending Requests',
                  _keyStats['pendingRequests']?.toString() ?? '0'),
            ],
          ),

          const SizedBox(height: 12),

          // Optimistic UI Stats
          _buildSection(
            '⚡ Optimistic UI Performance',
            [
              _buildStat('Active Conversations',
                  _uiStats['activeConversations']?.toString() ?? '0'),
              _buildStat('Optimistic Messages',
                  _uiStats['totalOptimisticMessages']?.toString() ?? '0'),
              _buildStat('Pending Messages',
                  _uiStats['totalPendingMessages']?.toString() ?? '0'),
              _buildStat('Failed Messages',
                  _uiStats['totalFailedMessages']?.toString() ?? '0'),
            ],
          ),

          const SizedBox(height: 12),

          // Performance Indicators
          _buildSection(
            '📊 Performance Indicators',
            [
              _buildPerformanceIndicator(
                'Key Cache Efficiency',
                (_keyStats['cacheHitRate'] ?? 0.0) * 100,
                Colors.green,
              ),
              _buildPerformanceIndicator(
                'UI Responsiveness',
                _calculateUIResponsiveness(),
                Colors.blue,
              ),
              _buildPerformanceIndicator(
                'System Health',
                _calculateSystemHealth(),
                Colors.orange,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    ConversationKeyCache.instance.clearCache();
                    _updateStats();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Key cache cleared')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.8),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Clear Cache'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    ConversationKeyCache.instance.cleanup();
                    _updateStats();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cache cleaned up')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.withValues(alpha: 0.8),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Cleanup'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceIndicator(
      String label, double percentage, Color color) {
    // Safely handle NaN and Infinity values
    final safePercentage = _sanitizePercentage(percentage);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${safePercentage.toStringAsFixed(1)}%',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: safePercentage / 100,
            backgroundColor: Colors.grey.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ],
      ),
    );
  }

  double _calculateUIResponsiveness() {
    final totalMessages = _uiStats['totalOptimisticMessages'] ?? 0;
    final failedMessages = _uiStats['totalFailedMessages'] ?? 0;

    if (totalMessages == 0) return 100.0;

    final successRate =
        ((totalMessages - failedMessages) / totalMessages) * 100;
    return successRate.clamp(0.0, 100.0);
  }

  double _calculateSystemHealth() {
    final cacheHitRate = (_keyStats['cacheHitRate'] ?? 0.0) * 100;
    final uiResponsiveness = _calculateUIResponsiveness();
    final pendingRequests = _keyStats['pendingRequests'] ?? 0;

    // Calculate health based on multiple factors
    double health = (cacheHitRate + uiResponsiveness) / 2;

    // Penalize for too many pending requests
    if (pendingRequests > 5) {
      health -= (pendingRequests - 5) * 2;
    }

    return _sanitizePercentage(health);
  }

  /// Safely handle NaN, Infinity, and out-of-range percentage values
  double _sanitizePercentage(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.0;
    }
    return value.clamp(0.0, 100.0);
  }
}
