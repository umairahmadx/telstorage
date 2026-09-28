/*
 * File: share_link_progress_section.dart
 * Description: In-sheet live progress display showing upload stream status, percentage, and cancellation controls.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';

/// Progress card displayed inside the share sheet while a file or folder is being streamed to storage.to.
class ShareLinkProgressSection extends StatelessWidget {
  /// Stream progress between 0.0 and 1.0.
  final double progress;

  /// Current pipeline stage label.
  final String stage;

  /// Cancellation callback.
  final VoidCallback onCancel;

  /// Constructs ShareLinkProgressSection.
  const ShareLinkProgressSection({
    super.key,
    required this.progress,
    required this.stage,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final pctInt = (progress * 100).clamp(0, 100).toInt();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 3.5,
                      backgroundColor: colors.borderSubtle,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                    ),
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 18,
                      color: colors.accentPrimary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stage.isNotEmpty ? stage : 'Generating secure link…',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$pctInt% complete · Streaming to storage.to',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 6,
              backgroundColor: colors.borderSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                onCancel();
              },
              style: TextButton.styleFrom(
                foregroundColor: colors.error,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(AppIcons.close, size: 16),
              label: const Text(
                'Cancel Share',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
