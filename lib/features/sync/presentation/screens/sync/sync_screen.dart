/*
 * File: sync_screen.dart
 * Description: Sync Center screen displaying real-time offline queue status, connectivity, and activity logs.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../core/services/service_locator.dart';
import '../../../../../core/services/sync_queue_service.dart';
import '../../../../../core/theme/app_icons.dart';
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

  /// Flag tracking if manual synchronization is actively executing.
  bool _isSyncing = false;

  /// Progress fraction of the ongoing sync (0.0 to 1.0).
  double _syncProgress = 0.0;

  /// Status description of the current sync phase.
  String _syncStatus = '';

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

  /// Executes full two-way synchronization when "Sync Now" is pressed.
  Future<void> _handleSyncNow(SyncQueueService syncQueue) async {
    if (_isSyncing) return;
    await _checkConnection();
    if (!_isDeviceOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot sync: device is offline.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncProgress = 0.0;
      _syncStatus = 'Starting synchronization…';
    });

    final syncLogId = 'sync_${DateTime.now().millisecondsSinceEpoch}';

    try {
      // Step 1: Flush pending offline mutations to Telegram in batch
      if (syncQueue.pendingCount > 0) {
        setState(() {
          _syncProgress = 0.1;
          _syncStatus = 'Processing pending actions…';
        });
        await syncQueue.processQueue(force: true);
      }

      // Step 2: Pull cloud updates from Telegram
      setState(() {
        _syncProgress = 0.2;
        _syncStatus = 'Connecting to Telegram…';
      });

      final syncService = ServiceLocator.instance.syncService;
      final result = await syncService.syncFromTelegram(
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _syncProgress = 0.2 + (progress * 0.8);
              _syncStatus = status;
            });
          }
        },
      );

      syncQueue.recordLog(SyncLogItem(
        id: syncLogId,
        actionType: 'cloud_sync',
        description:
            'Full Cloud Sync: +${result.added} added, -${result.removed} removed',
        timestamp: DateTime.now(),
        status: 'completed',
      ));

      if (mounted) {
        setState(() {
          _syncProgress = 1.0;
          _syncStatus = 'All Changes Synced';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync complete! +${result.added} added, -${result.removed} removed.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      syncQueue.recordLog(SyncLogItem(
        id: syncLogId,
        actionType: 'cloud_sync',
        description: 'Full Cloud Sync failed',
        timestamp: DateTime.now(),
        status: 'failed',
        error: e.toString(),
      ));

      if (mounted) {
        setState(() {
          _syncStatus = 'Sync failed';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
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
          icon: Icon(AppIcons.back, color: colors.textPrimary),
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
            icon: Icon(AppIcons.delete, color: colors.textSecondary),
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
  Widget _buildStatusCard(
      AppColorsExtension colors, SyncQueueService syncQueue, int pendingCount) {
    final String statusText;
    if (_isSyncing) {
      statusText = _syncStatus.isNotEmpty ? _syncStatus : 'Syncing with cloud…';
    } else if (!_isDeviceOnline) {
      statusText = 'Offline — Changes Queued';
    } else if (pendingCount > 0) {
      statusText = 'Syncing $pendingCount item(s)...';
    } else {
      statusText = 'All Changes Synced';
    }

    final statusColor = !_isDeviceOnline
        ? colors.error
        : ((pendingCount > 0 || _isSyncing)
            ? colors.accentPrimary
            : colors.success);

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
                child: Center(
                  child: _isSyncing
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(statusColor),
                          ),
                        )
                      : Icon(
                          pendingCount > 0
                              ? AppIcons.syncing
                              : AppIcons.cloudDone,
                          color: statusColor,
                          size: 24,
                        ),
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
                          ? (_isSyncing
                              ? 'Synchronizing partitions and files'
                              : 'Background sync engine is active')
                          : 'Will automatically sync when reconnected',
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isSyncing) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _syncProgress > 0 ? _syncProgress.clamp(0.0, 1.0) : null,
                backgroundColor: colors.bgSurfaceInset,
                valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                minHeight: 4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSyncing ? null : () => _handleSyncNow(syncQueue),
              icon: _isSyncing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colors.bgPrimary),
                      ),
                    )
                  : Icon(AppIcons.syncing, size: 18, color: colors.bgPrimary),
              label: Text(
                _isSyncing ? 'Syncing…' : 'Sync Now',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: colors.bgPrimary),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentPrimary,
                disabledBackgroundColor:
                    colors.accentPrimary.withValues(alpha: 0.6),
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
        icon = AppIcons.statusDone;
        color = colors.success;
        break;
      case 'syncing':
        icon = AppIcons.syncing;
        color = colors.accentPrimary;
        break;
      case 'failed':
        icon = AppIcons.statusError;
        color = colors.error;
        break;
      default:
        icon = AppIcons.statusPending;
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
