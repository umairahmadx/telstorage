import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/file_record.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_icons.dart';
import 'qr_dialog.dart';

class ShareLinkSheet extends StatefulWidget {
  final FileRecord file;
  final String? shareUrl;
  final Function(String? password, int expiryDays, String? vanitySlug) onCopyLink;

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

  @override
  void dispose() {
    _passCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
              _buildFileIcon(colors),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.file.name,
                      style: TextStyle(
                          fontSize: 18,
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
          const SizedBox(height: 32),
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
                borderRadius: BorderRadius.circular(20),
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
          const SizedBox(height: 24),
          Text('Password (Optional)',
              style: TextStyle(color: colors.textSecondary, fontSize: 14)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(AppIcons.lock,
                    size: 20, color: colors.textTertiary),
                const SizedBox(width: 16),
                Expanded(
                  child: Text('Set password',
                      style: TextStyle(
                          color: colors.textPrimary, fontWeight: FontWeight.w500)),
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
          const SizedBox(height: 24),
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
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => widget.onCopyLink(
                    _setPassword ? _passCtrl.text : null,
                    _expiryDays,
                    _slugCtrl.text.trim().isNotEmpty ? _slugCtrl.text.trim() : null,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accentPrimary,
                    foregroundColor: colors.bgPrimary,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(AppIcons.link),
                  label: const Text('Copy Link',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: widget.shareUrl == null
                    ? null
                    : () => showDialog(
                          context: context,
                          builder: (_) => QrDialog(
                              data: widget.shareUrl!, title: 'Share File QR'),
                        ),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.bgSurface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    AppIcons.qrCode,
                    color:
                        widget.shareUrl == null ? colors.textTertiary : colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildFileIcon(AppColorsExtension colors) {
    Color iconColor = colors.fileVideo;
    if (widget.file.isPdf) iconColor = colors.filePdf;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: iconColor.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(widget.file.isPdf ? 'PDF' : 'FILE',
          style: TextStyle(
              color: iconColor, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}
