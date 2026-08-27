/*
 * File: error_log_detail_sheet.dart
 * Description: Bottom sheet modal displaying full error log message, metadata, and copyable stack trace.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../../../core/models/error_log_record.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/badges/app_status_badge.dart';

/// Modal sheet presenting complete details and formatted stack trace for a log record.
class ErrorLogDetailSheet extends StatelessWidget {
  /// The log record being inspected.
  final ErrorLogRecord log;

  /// Constructs ErrorLogDetailSheet.
  const ErrorLogDetailSheet({super.key, required this.log});

  /// Shows the modal bottom sheet for the given log record.
  static Future<void> show(BuildContext context, ErrorLogRecord log) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ErrorLogDetailSheet(log: log),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final timeStr =
        DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(log.timestamp);

    final (levelColor, effectiveBg, effectiveBorder) = switch (log.level) {
      ErrorLogLevel.error => (
          colors.error,
          colors.error.withValues(alpha: 0.15),
          colors.error.withValues(alpha: 0.4),
        ),
      ErrorLogLevel.warning => (
          colors.warning,
          colors.warning.withValues(alpha: 0.15),
          colors.warning.withValues(alpha: 0.4),
        ),
      ErrorLogLevel.info => (
          colors.accentPrimary,
          colors.bgSurfaceInset,
          colors.borderSubtle,
        ),
    };


    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Log Details',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppStatusBadge(
                  label: log.level.name.toUpperCase(),
                  textColor: levelColor,
                  backgroundColor: effectiveBg,
                  borderColor: effectiveBorder,
                ),

                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: colors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(color: colors.borderSubtle, height: 1),

          // Scrollable Body
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                // Tag and Timestamp row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.bgSurfaceInset,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.borderSubtle),
                      ),
                      child: Text(
                        '[${log.tag}]',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        timeStr,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Main Message
                Text(
                  'Message',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  log.message,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                // Error details if present
                if (log.errorDetails != null &&
                    log.errorDetails!.isNotEmpty) ...[
                  Text(
                    'Error Details',
                    style: TextStyle(
                      color: levelColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.bgSurfaceInset,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: levelColor.withValues(alpha: 0.3)),
                    ),
                    child: SelectableText(
                      log.errorDetails!,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Metadata if present
                if (log.metadata != null && log.metadata!.isNotEmpty) ...[
                  Text(
                    'Metadata',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.bgSurfaceInset,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: SelectableText(
                      log.metadata.toString(),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Stack Trace section
                if (log.stackTrace != null && log.stackTrace!.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Stack Trace',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: log.stackTrace!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Stack trace copied to clipboard'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text('Copy Stack Trace'),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.accentPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.bgSurfaceInset,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.borderSubtle),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        log.stackTrace!,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Bottom Copy All button
                ElevatedButton.icon(
                  onPressed: () {
                    final fullText = StringBuffer()
                      ..writeln(
                          '[${log.level.name.toUpperCase()}] [${log.tag}] ${log.message}')
                      ..writeln('Timestamp: $timeStr');
                    if (log.errorDetails != null) {
                      fullText.writeln('Details: ${log.errorDetails}');
                    }
                    if (log.metadata != null) {
                      fullText.writeln('Metadata: ${log.metadata}');
                    }
                    if (log.stackTrace != null) {
                      fullText.writeln('StackTrace:\n${log.stackTrace}');
                    }

                    Clipboard.setData(
                        ClipboardData(text: fullText.toString()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Full log copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text('Copy Entire Log'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.bgSurfaceInset,
                    foregroundColor: colors.textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: colors.borderSubtle),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
