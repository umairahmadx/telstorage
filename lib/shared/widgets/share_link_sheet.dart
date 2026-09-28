/*
 * File: share_link_sheet.dart
 * Description: Interactive 3-phase modal bottom sheet coordinating public web share configuration, live streaming progress, and active QR/link management.
 */

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/file_record.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import 'dialogs/app_dialogs.dart';
import 'dialogs/share_link_active_actions.dart';
import 'dialogs/share_link_options_section.dart';
import 'dialogs/share_link_progress_section.dart';
import 'thumbnail_widget.dart';

/// Modal bottom sheet coordinating the 3-state share lifecycle (Config, Streaming Progress, Active QR Hub).
class ShareLinkSheet extends StatefulWidget {
  /// File to be shared.
  final FileRecord file;

  /// Optional pre-existing share URL.
  final String? shareUrl;

  /// Optional callback to trigger generation with full parameter suite.
  final Function(String? password, int expiryDays, String? vanitySlug,
      int? maxDownloads)? onGenerateLink;

  /// Legacy callback to trigger public share link generation.
  final Function(String? password, int expiryDays, String? vanitySlug)?
      onCopyLink;

  /// Constructs ShareLinkSheet.
  const ShareLinkSheet({
    super.key,
    required this.file,
    this.shareUrl,
    this.onGenerateLink,
    this.onCopyLink,
  });

  @override
  State<ShareLinkSheet> createState() => _ShareLinkSheetState();
}

class _ShareLinkSheetState extends State<ShareLinkSheet> {
  bool _setPassword = false;
  int _expiryDays = 7;
  int? _maxDownloads;
  final _passCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();

  String? _effectiveShareUrl;
  bool _hasActiveShare = false;
  bool _isInProgress = false;
  double _progress = 0.0;
  String _currentStage = 'Preparing secure link…';
  Timer? _progressPollTimer;

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
        if (existing != null) {
          if (existing.isComplete &&
              existing.shareUrl != null &&
              existing.shareUrl!.isNotEmpty) {
            _effectiveShareUrl = existing.shareUrl;
            _hasActiveShare = true;
            _expiryDays = existing.expiryDays ?? 7;
            _maxDownloads = existing.maxDownloads;
          } else if (existing.isUploading ||
              existing.isDownloading ||
              existing.isQueued) {
            _isInProgress = true;
            _progress = existing.progress;
            _currentStage = existing.status == 'uploading'
                ? 'Streaming to storage.to…'
                : 'Preparing file…';
            _startProgressPolling();
          }
        }
      }
    } catch (_) {}
  }

  void _startProgressPolling() {
    _progressPollTimer?.cancel();
    _progressPollTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      try {
        if (!ServiceLocator.instance.isInitialized) return;
        final job = ServiceLocator.instance.webShareQueue
            .getActiveShare(widget.file.fileId);
        if (job == null) return;

        if (job.isComplete && job.shareUrl != null) {
          _progressPollTimer?.cancel();
          HapticFeedback.mediumImpact();
          setState(() {
            _isInProgress = false;
            _hasActiveShare = true;
            _effectiveShareUrl = job.shareUrl;
            _expiryDays = job.expiryDays ?? _expiryDays;
            _maxDownloads = job.maxDownloads ?? _maxDownloads;
          });
        } else if (job.isFailed) {
          _progressPollTimer?.cancel();
          setState(() {
            _isInProgress = false;
            _hasActiveShare = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(job.error ?? 'Upload to storage.to failed'),
              backgroundColor: Theme.of(context)
                  .extension<AppColorsExtension>()!
                  .error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          setState(() {
            _progress = job.progress;
            _currentStage = job.status == 'uploading'
                ? 'Streaming to storage.to…'
                : (job.status == 'downloading'
                    ? 'Fetching from Telegram…'
                    : 'Queued for streaming…');
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _progressPollTimer?.cancel();
    _passCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
  }

  void _handleGenerateLink() {
    HapticFeedback.mediumImpact();
    final pwd = _setPassword && _passCtrl.text.trim().isNotEmpty
        ? _passCtrl.text.trim()
        : null;
    final slug = _slugCtrl.text.trim().isNotEmpty ? _slugCtrl.text.trim() : null;

    if (widget.onGenerateLink != null) {
      widget.onGenerateLink!(pwd, _expiryDays, slug, _maxDownloads);
    } else if (widget.onCopyLink != null) {
      widget.onCopyLink!(pwd, _expiryDays, slug);
    }

    setState(() {
      _isInProgress = true;
      _progress = 0.05;
      _currentStage = 'Initializing upload stream…';
    });
    _startProgressPolling();
  }

  Future<void> _handleCancelProgress() async {
    _progressPollTimer?.cancel();
    if (ServiceLocator.instance.isInitialized) {
      await ServiceLocator.instance.webShareQueue.deleteShare(widget.file.fileId);
    }
    setState(() {
      _isInProgress = false;
      _hasActiveShare = false;
      _effectiveShareUrl = null;
    });
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          'This will immediately revoke access and expire the public link on storage.to.',
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            const SizedBox(height: 20),
            Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: ThumbnailWidget(
                    file: widget.file,
                    width: 52,
                    height: 52,
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
            const SizedBox(height: 20),
            if (_hasActiveShare && _effectiveShareUrl != null) ...[
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
              const SizedBox(height: 20),
              ShareLinkActiveActions(
                shareUrl: _effectiveShareUrl!,
                title: widget.file.name,
                expiryDays: _expiryDays,
                maxDownloads: _maxDownloads,
                onCopy: () => _handleCopyExistingLink(context, colors),
                onShare: _handleNativeShare,
                onDelete: () => _handleDeleteShare(context, colors),
              ),
            ] else if (_isInProgress) ...[
              ShareLinkProgressSection(
                progress: _progress,
                stage: _currentStage,
                onCancel: _handleCancelProgress,
              ),
            ] else ...[
              ShareLinkOptionsSection(
                expiryDays: _expiryDays,
                onExpiryDaysChanged: (days) => setState(() => _expiryDays = days),
                maxDownloads: _maxDownloads,
                onMaxDownloadsChanged: (limit) =>
                    setState(() => _maxDownloads = limit),
                setPassword: _setPassword,
                onSetPasswordChanged: (val) =>
                    setState(() => _setPassword = val),
                passwordController: _passCtrl,
                slugController: _slugCtrl,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _handleGenerateLink,
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
                    'Generate Secure Link',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
