/*
 * File: recent_files_section.dart
 * Description: Section component rendering recently accessed/uploaded files using centralized AppFileTile.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/navigation/navigation_intent.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/tiles/app_file_tile.dart';
import 'package:telstorage/shared/widgets/typography/app_section_label.dart';

/// Section widget rendering list of recent file items using centralized AppFileTile.
class RecentFilesSection extends StatelessWidget {
  /// List of recent FileRecords.
  final List<FileRecord> files;

  /// Callback when user taps more options button on a file.
  final ValueChanged<FileRecord> onMore;

  /// Constructs RecentFilesSection.
  const RecentFilesSection({
    super.key,
    required this.files,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Column(
      children: [
        AppSectionLabel(
          label: 'Recent Files',
          actionText: 'View all',
          padding: const EdgeInsets.only(bottom: 12),
          onActionTap: () => ServiceLocator.instance.navigation
              .navigateTo(AppDestination.files),
        ),
        if (files.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Text(
                'No recent files',
                style: TextStyle(color: colors.textTertiary),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: files.length,
            itemBuilder: (context, i) {
              final file = files[i];
              return AppFileTile(
                key: ValueKey(file.fileId),
                file: file,
                onTap: () => onMore(file),
                onActionTap: () => onMore(file),
              );
            },
          ),
      ],
    );
  }
}
