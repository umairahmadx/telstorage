/*
 * File: share_link_sheet.dart
 * Description: Modal bottom sheet for configuring and generating public web share URLs with expiry, passwords, QR codes, and thumbnail previews.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/file_record.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import 'dialogs/app_dialogs.dart';
import 'dialogs/share_link_active_actions.dart';
import 'dialogs/share_link_options_section.dart';
import 'thumbnail_widget.dart';

/// Modal bottom sheet providing public web link sharing controls with dynamic Get URL / Copy Link states.
class ShareLinkSheet extends StatefulWidget {
  /// File to be shared.
  final FileRecord file;

  /// Optional pre-existing share URL.
  final String? shareUrl;

  /// Callback to enqueue/generate public share link.
  final Function(String? password, int expiryDays, String? vanitySlug)
      onCopyLink;

  /// Constructs ShareLinkSheet.
  const ShareLinkSheet({
    super.key,
    required this.file,
    this.shareUrl,
    required this.onCopyLink,
  });

  @override
  State<ShareLinkSheet> createState() => _ShareLinkSheetState();
}

class _ShareLinkSheetState extends State<ShareLinkSheet> {
  bool _setPassword = false;
  int _expiryDays = 7;
  final _passCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();

  String? _effectiveShareUrl;
  bool _hasActiveShare = false;

  @override
  void initState() {
    super.initState();
    _checkExistingShare();
  }

  void _checkExistingShare() {
    if (widget.shareUrl != null && widget.shareUrl!.isNotEmpty) {
      _effectiveShareUrl = widget.shareUrl;
      _hasActiveShare = true;
      return;
    }

    try {
      if (ServiceLocator.instance.isInitialized) {
        final existing = ServiceLocator.instance.webShareQueue
            .getActiveShare(widget.file.fileId);
        if (existing != null &&
            existing.shareUrl != null &&
            existing.shareUrl!.isNotEmpty) {
          _effectiveShareUrl = existing.shareUrl;
          _hasActiveShare = true;
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleCopyExistingLink(
      BuildContext context, AppColorsExtension colors) async {
    if (_effectiveShareUrl != null) {
      HapticFeedback.lightImpact();
      await Clipboard.setData(ClipboardData(text: _effectiveShareUrl!));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Share link copied to clipboard!'),
            backgroundColor: colors.accentPrimary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleNativeShare() async {
    if (_effectiveShareUrl != null) {
      HapticFeedback.lightImpact();
      await SharePlus.instance.share(ShareParams(text: _effectiveShareUrl!));
    }
  }

  Future<void> _handleDeleteShare(
      BuildContext context, AppColorsExtension colors) async {
    HapticFeedback.heavyImpact();
    final confirm = await AppDialogs.showConfirm(
      context,
      title: 'Delete Share Link?',
      message:
          'This will immediately revoke access and expire the public link.',
      confirmText: 'Delete Link',
      isDestructive: true,
    );
    if (confirm == true && context.mounted) {
      HapticFeedback.heavyImpact();
      if (ServiceLocator.instance.isInitialized) {
        await ServiceLocator.instance.webShareQueue
            .deleteShare(widget.file.fileId);
      }
      setState(() {
        _hasActiveShare = false;
        _effectiveShareUrl = null;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Share link deleted and expired.'),
            backgroundColor: colors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: ThumbnailWidget(
                    file: widget.file,
                    width: 56,
                    height: 56,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.file.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.file.formattedSize,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_hasActiveShare && _effectiveShareUrl != null) ...[
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.bgSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colors.accentPrimary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_rounded,
                        color: colors.accentPrimary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _effectiveShareUrl!,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            ShareLinkOptionsSection(
              expiryDays: _expiryDays,
              onExpiryDaysChanged: (days) => setState(() => _expiryDays = days),
              setPassword: _setPassword,
              onSetPasswordChanged: (val) => setState(() => _setPassword = val),
              passwordController: _passCtrl,
              slugController: _slugCtrl,
            ),
            const SizedBox(height: 28),
            if (_hasActiveShare && _effectiveShareUrl != null) ...[
              ShareLinkActiveActions(
                shareUrl: _effectiveShareUrl!,
                onCopy: () => _handleCopyExistingLink(context, colors),
                onShare: _handleNativeShare,
                onDelete: () => _handleDeleteShare(context, colors),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    widget.onCopyLink(
                      _setPassword ? _passCtrl.text : null,
                      _expiryDays,
                      _slugCtrl.text.trim().isNotEmpty
                          ? _slugCtrl.text.trim()
                          : null,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accentPrimary,
                    foregroundColor: colors.bgPrimary,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text(
                    'Get URL',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
