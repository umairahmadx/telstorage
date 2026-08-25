/*
 * File: share_link_sheet.dart
 * Description: Modal bottom sheet for configuring and generating public web share URLs with expiry, passwords, QR codes, and real thumbnail previews.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/models/file_record.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_icons.dart';
import 'thumbnail_widget.dart';
import 'qr_dialog.dart';

/// Modal bottom sheet providing public web link sharing controls with dynamic Get URL / Copy Link states.
class ShareLinkSheet extends StatefulWidget {
  /// File to be shared.
  final FileRecord file;

  /// Optional pre-existing share URL.
  final String? shareUrl;

  /// Callback to enqueue/generate public share link.
  final Function(String? password, int expiryDays, String? vanitySlug) onCopyLink;

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
        final existing =
            ServiceLocator.instance.webShareQueue.getActiveShare(widget.file.fileId);
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
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM yyyy')
        .format(DateTime.now().add(Duration(days: _expiryDays)));

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
                          color: colors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.file.formattedSize,
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // If active share URL exists, display it in a clean card
          if (_hasActiveShare && _effectiveShareUrl != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: colors.accentPrimary.withValues(alpha: 0.3)),
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
          Text('Expires',
              style: TextStyle(color: colors.textSecondary, fontSize: 14)),
          const SizedBox(height: 12),
          PopupMenuButton<int>(
            onSelected: (days) => setState(() => _expiryDays = days),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 1, child: Text('In 1 day')),
              const PopupMenuItem(value: 3, child: Text('In 3 days')),
              const PopupMenuItem(value: 7, child: Text('In 7 days')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: colors.bgSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.calendar,
                      size: 20, color: colors.textTertiary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('In $_expiryDays days',
                            style: TextStyle(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600)),
                        Text(dateStr,
                            style: TextStyle(
                                color: colors.textTertiary, fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(AppIcons.dropdownArrow,
                      color: colors.textTertiary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Password (Optional)',
              style: TextStyle(color: colors.textSecondary, fontSize: 14)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(AppIcons.lock,
                    size: 20, color: colors.textTertiary),
                const SizedBox(width: 16),
                Expanded(
                  child: Text('Set password',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w500)),
                ),
                Switch(
                  value: _setPassword,
                  onChanged: (v) => setState(() => _setPassword = v),
                  activeTrackColor: colors.accentPrimary,
                  activeThumbColor: colors.bgPrimary,
                ),
              ],
            ),
          ),
          if (_setPassword) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter password',
                hintStyle: TextStyle(color: colors.textTertiary),
                filled: true,
                fillColor: colors.bgSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('Custom Vanity Link (Optional)',
              style: TextStyle(color: colors.textSecondary, fontSize: 14)),
          const SizedBox(height: 12),
          TextField(
            controller: _slugCtrl,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              prefixText: 'storage.to/v/',
              prefixStyle: TextStyle(
                  color: colors.accentPrimary, fontWeight: FontWeight.bold),
              hintText: 'my-custom-alias',
              hintStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.bgSurface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _hasActiveShare
                      ? () => _handleCopyExistingLink(context, colors)
                      : () => widget.onCopyLink(
                            _setPassword ? _passCtrl.text : null,
                            _expiryDays,
                            _slugCtrl.text.trim().isNotEmpty
                                ? _slugCtrl.text.trim()
                                : null,
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accentPrimary,
                    foregroundColor: colors.bgPrimary,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: Icon(_hasActiveShare
                      ? Icons.copy_rounded
                      : Icons.cloud_upload_outlined),
                  label: Text(
                    _hasActiveShare ? 'Copy Link' : 'Get URL',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              if (_hasActiveShare && _effectiveShareUrl != null) ...[
                const SizedBox(width: 12),
                Material(
                  color: colors.bgSurface,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => QrDialog(
                        data: _effectiveShareUrl!,
                        title: 'Share File QR',
                      ),
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: Center(
                        child: Icon(
                          AppIcons.qrCode,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
}
