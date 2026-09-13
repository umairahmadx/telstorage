/*
 * File: error_logs_screen.dart
 * Description: In-app Error & Diagnostic Logs screen providing real-time log inspection, severity filtering, multi-select, and contextual export options.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../core/models/error_log_record.dart';
import '../../../../../core/services/error_log_service.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/dialogs/app_dialogs.dart';
import '../../../../../shared/widgets/feedback/app_empty_state.dart';
import 'widgets/error_log_detail_sheet.dart';
import 'widgets/error_log_filter_bar.dart';
import 'widgets/error_log_tile.dart';

/// Screen component allowing users to view, search, export, multi-select, and clear application error logs.
class ErrorLogsScreen extends StatefulWidget {
  /// Constructs ErrorLogsScreen.
  const ErrorLogsScreen({super.key});

  @override
  State<ErrorLogsScreen> createState() => _ErrorLogsScreenState();
}

class _ErrorLogsScreenState extends State<ErrorLogsScreen> {
  String _searchQuery = '';
  ErrorLogLevel? _selectedLevel;
  final Set<String> _selectedLogIds = {};

  bool get _isSelectionMode => _selectedLogIds.isNotEmpty;

  void _toggleSelection(String logId) {
    setState(() {
      if (_selectedLogIds.contains(logId)) {
        _selectedLogIds.remove(logId);
      } else {
        _selectedLogIds.add(logId);
      }
    });
  }

  void _selectAll(List<ErrorLogRecord> visibleLogs) {
    setState(() {
      if (_selectedLogIds.length == visibleLogs.length) {
        _selectedLogIds.clear();
      } else {
        _selectedLogIds.clear();
        _selectedLogIds.addAll(visibleLogs.map((l) => l.id));
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedLogIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final errorLogService = ErrorLogService.instance;

    return ValueListenableBuilder<List<ErrorLogRecord>>(
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
            final matchesMessage = log.message.toLowerCase().contains(query);
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

        final activeCategoryLabel = switch (_selectedLevel) {
          null => 'All',
          ErrorLogLevel.error => 'Error',
          ErrorLogLevel.warning => 'Warning',
          ErrorLogLevel.info => 'Info',
        };

        return PopScope(
          canPop: !_isSelectionMode,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _isSelectionMode) {
              _clearSelection();
            }
          },
          child: Scaffold(
            backgroundColor: colors.bgPrimary,
            appBar: AppBar(
              backgroundColor: colors.bgPrimary,
              elevation: 0,
              leading: IconButton(
                icon: Icon(
                  _isSelectionMode
                      ? Icons.close_rounded
                      : Icons.arrow_back_rounded,
                  color: colors.textPrimary,
                ),
                onPressed: _isSelectionMode
                    ? _clearSelection
                    : () => Navigator.pop(context),
              ),
              title: Text(
                _isSelectionMode
                    ? '${_selectedLogIds.length} Selected'
                    : 'Error & Diagnostic Logs',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
              actions: _isSelectionMode
                  ? [
                      // Select All / Deselect All
                      IconButton(
                        icon: Icon(
                          _selectedLogIds.length == filteredLogs.length &&
                                  filteredLogs.isNotEmpty
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                          color: colors.textSecondary,
                        ),
                        tooltip: _selectedLogIds.length == filteredLogs.length
                            ? 'Deselect All'
                            : 'Select All',
                        onPressed: () => _selectAll(filteredLogs),
                      ),
                      // Share Selected
                      IconButton(
                        icon: Icon(Icons.share_outlined,
                            color: colors.textSecondary),
                        tooltip: 'Share Selected',
                        onPressed: () {
                          final selected = filteredLogs
                              .where((l) => _selectedLogIds.contains(l.id))
                              .toList();
                          _handleShareLogs(context, selected);
                        },
                      ),
                      // Copy Selected
                      IconButton(
                        icon: Icon(Icons.copy_rounded,
                            color: colors.textSecondary),
                        tooltip: 'Copy Selected',
                        onPressed: () {
                          final selected = filteredLogs
                              .where((l) => _selectedLogIds.contains(l.id))
                              .toList();
                          _handleCopyLogs(context, selected, isSelection: true);
                        },
                      ),
                    ]
                  : [
                      // Share filtered logs
                      IconButton(
                        icon: Icon(Icons.share_outlined,
                            color: colors.textSecondary),
                        tooltip: 'Export & Share Diagnostics',
                        onPressed: () =>
                            _handleShareLogs(context, filteredLogs),
                      ),
                      // Copy filtered logs
                      IconButton(
                        icon: Icon(Icons.copy_all_rounded,
                            color: colors.textSecondary),
                        tooltip: 'Copy $activeCategoryLabel Logs',
                        onPressed: () => _handleCopyLogs(
                          context,
                          filteredLogs,
                          category: activeCategoryLabel,
                        ),
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
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: ErrorLogFilterBar(
                    searchQuery: _searchQuery,
                    onSearchChanged: (q) => setState(() {
                      _searchQuery = q;
                      _selectedLogIds.clear();
                    }),
                    selectedLevel: _selectedLevel,
                    onLevelSelected: (lvl) => setState(() {
                      _selectedLevel = lvl;
                      _selectedLogIds.clear();
                    }),
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
                            final isSelected = _selectedLogIds.contains(log.id);
                            return ErrorLogTile(
                              key: ValueKey(log.id),
                              log: log,
                              isSelected: isSelected,
                              isSelectionMode: _isSelectionMode,
                              onTap: () {
                                if (_isSelectionMode) {
                                  _toggleSelection(log.id);
                                } else {
                                  ErrorLogDetailSheet.show(context, log);
                                }
                              },
                              onLongPress: () {
                                _toggleSelection(log.id);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
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

  Future<void> _handleShareLogs(
    BuildContext context,
    List<ErrorLogRecord> logsToShare,
  ) async {
    if (logsToShare.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No logs available to share'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final report = ErrorLogService.instance.exportDiagnosticReport(logsToShare);
    await SharePlus.instance.share(
      ShareParams(
        text: report,
        subject: 'TelStorage Diagnostic Report',
      ),
    );
  }

  Future<void> _handleCopyLogs(
    BuildContext context,
    List<ErrorLogRecord> logsToCopy, {
    String? category,
    bool isSelection = false,
  }) async {
    if (logsToCopy.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No logs available to copy'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final report = ErrorLogService.instance.exportDiagnosticReport(logsToCopy);
    await Clipboard.setData(ClipboardData(text: report));

    if (isSelection) {
      _clearSelection();
    }

    if (context.mounted) {
      final msg = isSelection
          ? '${logsToCopy.length} selected logs copied to clipboard'
          : category != null
              ? '${logsToCopy.length} $category logs copied to clipboard'
              : '${logsToCopy.length} logs copied to clipboard';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
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
      _clearSelection();
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
