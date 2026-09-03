/*
 * File: share_link_active_actions.dart
 * Description: Action button row and revocation trigger for active public web share links.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../qr_dialog.dart';

/// Action controls for copying, sharing via system sheet, showing QR code, and revoking active web links.
class ShareLinkActiveActions extends StatelessWidget {
  final String shareUrl;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const ShareLinkActiveActions({
    super.key,
    required this.shareUrl,
    required this.onCopy,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
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
            const SizedBox(width: 8),
            Expanded(
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
            const SizedBox(width: 8),
            Material(
              color: colors.bgSurface,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  showDialog(
                    context: context,
                    builder: (_) => QrDialog(
                      data: shareUrl,
                      title: 'Share File QR',
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: Center(
                    child: Icon(
                      AppIcons.qrCode,
                      color: colors.textPrimary,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
