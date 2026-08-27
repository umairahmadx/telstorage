/*
 * File: error_logs_screen.dart
 * Description: In-app Error & Diagnostic Logs screen providing real-time log inspection, severity filtering, search, and export options.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../core/models/error_log_record.dart';
import '../../../../../core/services/error_log_service.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/dialogs/app_dialogs.dart';
import '../../../../../shared/widgets/feedback/app_empty_state.dart';
import 'widgets/error_log_filter_bar.dart';
import 'widgets/error_log_tile.dart';


/// Screen component allowing users to view, search, export, and clear application error logs.
class ErrorLogsScreen extends StatefulWidget {
  /// Constructs ErrorLogsScreen.
  const ErrorLogsScreen({super.key});

  @override
  State<ErrorLogsScreen> createState() => _ErrorLogsScreenState();
}

class _ErrorLogsScreenState extends State<ErrorLogsScreen> {
  String _searchQuery = '';
  ErrorLogLevel? _selectedLevel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final errorLogService = ErrorLogService.instance;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Error & Diagnostic Logs',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          // Export / Share diagnostics
          IconButton(
            icon: Icon(Icons.share_outlined, color: colors.textSecondary),
            tooltip: 'Export & Share Diagnostics',
            onPressed: () => _handleShareReport(context),
          ),
          // Copy all logs
          IconButton(
            icon: Icon(Icons.copy_all_rounded, color: colors.textSecondary),
            tooltip: 'Copy All Logs',
            onPressed: () => _handleCopyAllLogs(context),
          ),
          // Clear all logs
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: colors.textSecondary),
            tooltip: 'Clear Logs',
            onPressed: () => _handleClearLogs(context),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<ErrorLogRecord>>(
        valueListenable: errorLogService.logsNotifier,
        builder: (context, allLogs, _) {
          final counts = <ErrorLogLevel?, int>{
            null: allLogs.length,
            ErrorLogLevel.error:
                allLogs.where((l) => l.level == ErrorLogLevel.error).length,
            ErrorLogLevel.warning:
                allLogs.where((l) => l.level == ErrorLogLevel.warning).length,
            ErrorLogLevel.info:
                allLogs.where((l) => l.level == ErrorLogLevel.info).length,
          };

          // Filter logs by level and search query
          final filteredLogs = allLogs.reversed.where((log) {
            if (_selectedLevel != null && log.level != _selectedLevel) {
              return false;
            }
            if (_searchQuery.isNotEmpty) {
              final query = _searchQuery.toLowerCase();
              final matchesMessage =
                  log.message.toLowerCase().contains(query);
              final matchesTag = log.tag.toLowerCase().contains(query);
              final matchesDetails =
                  log.errorDetails?.toLowerCase().contains(query) ?? false;
              final matchesStack =
                  log.stackTrace?.toLowerCase().contains(query) ?? false;
              return matchesMessage ||
                  matchesTag ||
                  matchesDetails ||
                  matchesStack;
            }
            return true;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ErrorLogFilterBar(
                  searchQuery: _searchQuery,
                  onSearchChanged: (q) => setState(() => _searchQuery = q),
                  selectedLevel: _selectedLevel,
                  onLevelSelected: (lvl) =>
                      setState(() => _selectedLevel = lvl),
                  counts: counts,
                ),
              ),
              Expanded(
                child: filteredLogs.isEmpty
                    ? _buildEmptyState(colors, allLogs.isEmpty)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filteredLogs.length,
                        itemBuilder: (context, index) {
                          final log = filteredLogs[index];
                          return ErrorLogTile(
                            key: ValueKey(log.id),
                            log: log,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(AppColorsExtension colors, bool noLogsAtAll) {
    if (noLogsAtAll) {
      return const Center(
        child: AppEmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'No Logs Recorded',
          subtitle: 'Everything is running smoothly.',
        ),
      );
    }
    return const Center(
      child: AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No Matching Logs',
        subtitle: 'No log entries match your current search or filter.',
      ),
    );
  }

  Future<void> _handleShareReport(BuildContext context) async {
    final report = ErrorLogService.instance.exportDiagnosticReport();
    await SharePlus.instance.share(
      ShareParams(
        text: report,
        subject: 'TelStorage Diagnostic Report',
      ),
    );
  }


  Future<void> _handleCopyAllLogs(BuildContext context) async {
    final report = ErrorLogService.instance.exportDiagnosticReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Diagnostic report copied to clipboard'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleClearLogs(BuildContext context) async {
    final confirmed = await AppDialogs.showConfirm(
      context,
      title: 'Clear Error Logs?',
      message:
          'This will delete all stored error and diagnostic logs from your device.',
      confirmText: 'Clear All',
      isDestructive: true,
    );

    if (confirmed == true) {
      await ErrorLogService.instance.clearLogs();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All logs cleared successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
