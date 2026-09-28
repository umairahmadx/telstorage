/*
 * File: share_link_active_actions.dart
 * Description: Active public web share command center with embedded QR card, copy/share actions, live stats, and revocation controls.
 */

import 'package:flutter/material.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import 'share_qr_card.dart';

/// Action controls for active web links: embedded QR card, copy, native share, live metadata, and revocation.
class ShareLinkActiveActions extends StatelessWidget {
  /// The active shareable URL.
  final String shareUrl;

  /// Display name of the file or folder.
  final String title;

  /// Optional expiration duration in days.
  final int? expiryDays;

  /// Optional maximum downloads quota limit.
  final int? maxDownloads;

  /// Callback when user copies link.
  final VoidCallback onCopy;

  /// Callback when user shares link natively.
  final VoidCallback onShare;

  /// Callback when user revokes/deletes link.
  final VoidCallback onDelete;

  /// Optional callback to open live settings edit sheet.
  final VoidCallback? onEditSettings;

  /// Constructs ShareLinkActiveActions.
  const ShareLinkActiveActions({
    super.key,
    required this.shareUrl,
    required this.title,
    this.expiryDays,
    this.maxDownloads,
    required this.onCopy,
    required this.onShare,
    required this.onDelete,
    this.onEditSettings,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShareQrCard(
          shareUrl: shareUrl,
          title: title,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: onCopy,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentPrimary,
                  foregroundColor: colors.bgPrimary,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(AppIcons.copy, size: 18),
                label: const Text(
                  'Copy Link',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: onShare,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(color: colors.borderSubtle),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(AppIcons.share, size: 18),
                label: const Text(
                  'Share',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
        if (expiryDays != null || maxDownloads != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                if (expiryDays != null) ...[
                  Row(
                    children: [
                      Icon(AppIcons.calendar,
                          size: 16, color: colors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Active for $expiryDays days',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
                if (expiryDays != null && maxDownloads != null)
                  Container(
                    width: 1,
                    height: 16,
                    color: colors.borderSubtle,
                  ),
                if (maxDownloads != null) ...[
                  Row(
                    children: [
                      Icon(Icons.download_for_offline_outlined,
                          size: 16, color: colors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        maxDownloads == 1
                            ? 'Single-use link'
                            : 'Max: $maxDownloads downloads',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: onDelete,
            style: TextButton.styleFrom(
              foregroundColor: colors.error,
              backgroundColor: colors.error.withValues(alpha: 0.08),
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(AppIcons.linkOff, size: 18),
            label: const Text(
              'Delete Link (Expire Now)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
