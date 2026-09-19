/*
 * File: reconcile_storage_card.dart
 * Description: Card widget for triggering remote storage reconciliation and orphan cleanup.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/routing/app_router.dart';
import '../../../../../../core/services/service_locator.dart';
import '../../../../../../core/services/storage_reconciler.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../core/utils/connectivity.dart';

/// Card presenting the "Reconcile & Clean Remote Storage" action with live progress.
class ReconcileStorageCard extends StatefulWidget {
  const ReconcileStorageCard({super.key});

  @override
  State<ReconcileStorageCard> createState() => _ReconcileStorageCardState();
}

class _ReconcileStorageCardState extends State<ReconcileStorageCard> {
  bool _isRunning = false;
  double _progress = 0.0;
  String _statusText = '';
  ReconciliationReport? _lastReport;

  Future<void> _handleReconcile() async {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = Theme.of(ctx).extension<AppColorsExtension>()!;
        return AlertDialog(
          backgroundColor: c.bgSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Reconcile & Clean?',
              style: TextStyle(
                  color: c.textPrimary, fontWeight: FontWeight.bold)),
          content: Text(
            'This will scan your Telegram channel, detect any orphaned chunk messages or leftover files that are no longer in your app library, and permanently delete them.\n\nFiles currently in your app will NOT be affected.',
            style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: c.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accentPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Clean in One Go',
                  style: TextStyle(
                      color: c.bgPrimary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final isOnline = await Connectivity.hasConnection();
    if (!isOnline && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot reconcile: device is offline.')),
      );
      return;
    }

    setState(() {
      _isRunning = true;
      _progress = 0.0;
      _statusText = 'Starting reconciliation...';
      _lastReport = null;
    });

    try {
      final reconciler = ServiceLocator.instance.storageReconciler;
      final report = await reconciler.reconcileAndCleanRemoteStorage(
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _statusText = status;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _lastReport = report;
          _isRunning = false;
          _progress = 1.0;
          _statusText = 'Reconciliation complete!';
        });

        if (!report.hasCleaned) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Everything is clean — no orphaned files found!'),
              backgroundColor: colors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _statusText = 'Reconciliation failed';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Reconciliation failed. Tap to view details.'),
            backgroundColor: colors.error,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View Logs',
              textColor: colors.bgPrimary,
              onPressed: () {
                Navigator.pushNamed(context, AppRouter.errorLogs);
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final report = _lastReport;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.accentPrimary.withValues(alpha: 0.18),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.accentPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(AppIcons.storage,
                    color: colors.accentPrimary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reconcile & Clean Remote Storage',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Purge orphaned Telegram files no longer in your library',
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Progress indicator
          if (_isRunning) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress.clamp(0.0, 1.0) : null,
                backgroundColor: colors.bgSurfaceInset,
                valueColor:
                    AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusText,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],

          // Result summary
          if (!_isRunning && report != null && report.hasCleaned) ...[
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.statusDone,
                      color: colors.success, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cleaned ${report.orphanedFilesCleaned} files, '
                      'deleted ${report.chunksDeleted} chunks, '
                      'freed ${report.spaceFreedMb.toStringAsFixed(1)} MB',
                      style: TextStyle(
                          fontSize: 13,
                          color: colors.success,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Action button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isRunning ? null : _handleReconcile,
              icon: _isRunning
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            colors.accentPrimary),
                      ),
                    )
                  : Icon(AppIcons.delete,
                      size: 18, color: colors.accentPrimary),
              label: Text(
                _isRunning ? 'Scanning & Cleaning…' : 'Clean in One Go',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isRunning
                        ? colors.textSecondary
                        : colors.accentPrimary),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: _isRunning
                        ? colors.textTertiary
                        : colors.accentPrimary,
                    width: 1.5),
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
}
