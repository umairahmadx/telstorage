/*
 * File: error_log_tile.dart
 * Description: Interactive list tile presenting error log summary, tag, timestamp, and severity indicator.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../../core/models/error_log_record.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/app_surface_card.dart';
import 'error_log_detail_sheet.dart';

/// Card tile rendering a single error or diagnostic log entry.
class ErrorLogTile extends StatelessWidget {
  /// The log record to display.
  final ErrorLogRecord log;

  /// Constructs ErrorLogTile.
  const ErrorLogTile({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final timeStr = DateFormat('HH:mm:ss').format(log.timestamp);

    final (iconData, statusColor) = switch (log.level) {
      ErrorLogLevel.error => (Icons.error_rounded, colors.error),
      ErrorLogLevel.warning => (Icons.warning_rounded, colors.warning),
      ErrorLogLevel.info => (Icons.info_rounded, colors.accentPrimary),
    };


    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSurfaceCard(
        color: colors.bgSurface,
        radius: 14,
        borderColor: colors.borderSubtle,
        onTap: () => ErrorLogDetailSheet.show(context, log),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Icon Container
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, color: statusColor, size: 18),
            ),
            const SizedBox(width: 12),

            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tag and Timestamp row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.bgSurfaceInset,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.borderSubtle),
                        ),
                        child: Text(
                          log.tag,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        timeStr,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Message
                  Text(
                    log.message,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Error snippet if available
                  if (log.errorDetails != null &&
                      log.errorDetails!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      log.errorDetails!,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
