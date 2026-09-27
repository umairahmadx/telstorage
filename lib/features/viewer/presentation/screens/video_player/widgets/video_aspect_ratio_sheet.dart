/*
 * File: video_aspect_ratio_sheet.dart
 * Description: Modal bottom sheet for choosing video aspect ratio display modes (Best Fit, Fill Screen, 16:9, 4:3, Original).
 */

import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../models/video_aspect_ratio_mode.dart';

/// Modal bottom sheet allowing users to switch video aspect ratio presets.
class VideoAspectRatioSheet extends StatelessWidget {
  /// Currently selected aspect ratio mode.
  final VideoAspectRatioMode currentMode;

  /// Callback when a new aspect ratio mode is selected.
  final ValueChanged<VideoAspectRatioMode> onModeSelected;

  /// Constructs VideoAspectRatioSheet.
  const VideoAspectRatioSheet({
    super.key,
    required this.currentMode,
    required this.onModeSelected,
  });

  /// Displays the aspect ratio selection sheet.
  static void show(
    BuildContext context, {
    required VideoAspectRatioMode currentMode,
    required ValueChanged<VideoAspectRatioMode> onModeSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VideoAspectRatioSheet(
        currentMode: currentMode,
        onModeSelected: onModeSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.aspect_ratio_rounded, color: colors.accentPrimary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Aspect Ratio',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(AppIcons.close, color: colors.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: VideoAspectRatioMode.values.map((mode) {
                  final isSelected = mode == currentMode;
                  return Material(
                    color: Colors.transparent,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      title: Text(
                        mode.label,
                        style: TextStyle(
                          color: isSelected ? colors.accentPrimary : colors.textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_rounded, color: colors.accentPrimary, size: 20)
                          : null,
                      onTap: () {
                        onModeSelected(mode);
                        Navigator.of(context).pop();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
