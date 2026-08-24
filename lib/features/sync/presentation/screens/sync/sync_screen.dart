/// File: sync_screen.dart
/// Description: Sync Center screen displaying real-time offline queue status, connectivity, and activity logs.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../core/services/service_locator.dart';
import '../../../../../core/services/sync_queue_service.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/connectivity.dart';

/// Screen component rendering synchronization status, logs, and manual sync action.
class SyncScreen extends StatefulWidget {
  /// Constructs SyncScreen.
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

/// State controller for SyncScreen.
class _SyncScreenState extends State<SyncScreen> {
  /// Flag tracking device connectivity.
  bool _isDeviceOnline = true;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  /// Verifies current network connectivity.
  Future<void> _checkConnection() async {
    final online = await Connectivity.hasConnection();
    if (mounted) {
      setState(() {
        _isDeviceOnline = online;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final syncQueue = ServiceLocator.instance.syncQueue;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Sync Center',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon:
                Icon(Icons.delete_outline_rounded, color: colors.textSecondary),
            tooltip: 'Clear Logs',
            onPressed: () {
              syncQueue.clearLogs();
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: syncQueue.pendingCountNotifier,
        builder: (context, pendingCount, _) {
          return ValueListenableBuilder<List<SyncLogItem>>(
            valueListenable: syncQueue.logsNotifier,
            builder: (context, logs, _) {
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildStatusCard(colors, syncQueue, pendingCount),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sync Activity Logs',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        '${logs.length} events',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (logs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colors.bgSurface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          'No sync logs recorded yet.',
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    ...logs.map((log) => _buildLogTile(colors, log)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Builds connection and pending items status banner.
  Widget _buildStatusCard(AppColorsExtension colors,
      SyncQueueService syncQueue, int pendingCount) {
    final statusText = !_isDeviceOnline
        ? 'Offline — Changes Queued'
        : (pendingCount > 0
            ? 'Syncing $pendingCount item(s)...'
            : 'All Changes Synced');

    final statusColor = !_isDeviceOnline
        ? colors.error
        : (pendingCount > 0 ? colors.accentPrimary : colors.success);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  pendingCount > 0
                      ? Icons.sync_rounded
                      : Icons.cloud_done_rounded,
                  color: statusColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isDeviceOnline
                          ? 'Background sync engine is active'
                          : 'Will automatically sync when reconnected',
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await _checkConnection();
                syncQueue.processQueue();
              },
              icon: Icon(Icons.sync_rounded,
                  size: 18, color: colors.bgPrimary),
              label: Text(
                'Sync Now',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: colors.bgPrimary),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds row item for a sync event log.
  Widget _buildLogTile(AppColorsExtension colors, SyncLogItem log) {
    final timeStr = DateFormat('HH:mm:ss').format(log.timestamp);
    IconData icon;
    Color color;

    switch (log.status) {
      case 'completed':
        icon = Icons.check_circle_rounded;
        color = colors.success;
        break;
      case 'syncing':
        icon = Icons.sync_rounded;
        color = colors.accentPrimary;
        break;
      case 'failed':
        icon = Icons.error_rounded;
        color = colors.error;
        break;
      default:
        icon = Icons.schedule_rounded;
        color = colors.textTertiary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.description,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (log.error != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    log.error!,
                    style: TextStyle(color: colors.error, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeStr,
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
