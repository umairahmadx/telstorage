/*
 * File: downloads_shared_section.dart
 * Description: Section rendering active public web share links with clipboard copying, sharing, and revocation.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../core/models/web_share_job.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/app_surface_card.dart';
import '../../../../../../shared/widgets/thumbnail_widget.dart';
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
          final name = file?.name ?? job.name;
          final url = job.shareUrl ?? '';

          final Widget leadingWidget;
          if (file != null) {
            leadingWidget = SizedBox(
              width: 44,
              height: 44,
              child: ThumbnailWidget(
                file: file,
                width: 44,
                height: 44,
              ),
            );
          } else {
            final badge = SmartBadgeInfo.resolve(name, '', colors);
            leadingWidget = Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: badge.bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(badge.icon, color: badge.iconColor, size: 22),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppSurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              borderRadius: BorderRadius.circular(12),
              borderColor: colors.borderSubtle,
              child: Row(
                children: [
                  leadingWidget,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
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
                          job.isComplete
                              ? url
                              : (job.status == 'uploading'
                                  ? 'Uploading to Web… ${(job.progress * 100).toInt()}%'
                                  : (job.status == 'downloading'
                                      ? 'Preparing share… ${(job.progress * 100).toInt()}%'
                                      : 'Queued for share…')),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (job.isComplete && url.isNotEmpty)
                    Row(
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
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.cancel_outlined,
                              color: colors.error, size: 20),
                          tooltip: 'Cancel Share',
                          onPressed: () => onDeleteShareLink(job.fileId, name),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
