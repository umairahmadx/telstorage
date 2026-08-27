/*
 * File: downloads_shared_section.dart
 * Description: Section rendering active public web share links with clipboard copying, sharing, and revocation.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../core/models/web_share_job.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/typography/app_section_label.dart';
import '../viewmodel/downloads_view_model.dart';

/// Renders shared web link items with URL copy, external share sheet, and revocation actions.
class DownloadsSharedSection extends StatelessWidget {
  final List<WebShareJob> sharedLinks;
  final void Function(String url) onCopyUrl;
  final void Function(String url) onShareUrl;
  final void Function(String fileId, String fileName) onDeleteShareLink;

  const DownloadsSharedSection({
    super.key,
    required this.sharedLinks,
    required this.onCopyUrl,
    required this.onShareUrl,
    required this.onDeleteShareLink,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    if (sharedLinks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSectionLabel(
          label: 'Shared Links (${sharedLinks.length})',
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        ),
        ...sharedLinks.map((job) {
          final file = context.read<TransferCubit>().getFile(job.fileId);
          final name = file?.name ?? 'Shared File';
          final url = job.shareUrl ?? '';

          return ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.accentPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.link_rounded,
                  color: colors.accentPrimary, size: 22),
            ),
            title: Text(
              name,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              url,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.copy_rounded,
                      color: colors.accentPrimary, size: 20),
                  tooltip: 'Copy Link',
                  onPressed: () => onCopyUrl(url),
                ),
                IconButton(
                  icon: Icon(Icons.share_outlined,
                      color: colors.textSecondary, size: 20),
                  tooltip: 'Share',
                  onPressed: () => onShareUrl(url),
                ),
                IconButton(
                  icon: Icon(Icons.link_off_rounded,
                      color: colors.error, size: 20),
                  tooltip: 'Delete Link',
                  onPressed: () => onDeleteShareLink(job.fileId, name),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
