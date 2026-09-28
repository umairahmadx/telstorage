/*
 * File: device_file_breadcrumbs.dart
 * Description: Interactive breadcrumb navigation bar showing parent directory hierarchy
 * and allowing rapid jumping to any ancestor folder.
 */

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_colors_extension.dart';
import '../../../../core/theme/app_icons.dart';

/// Horizontal breadcrumb navigation component displaying directory ancestry chips.
class DeviceFileBreadcrumbs extends StatelessWidget {
  /// Current active directory path.
  final String currentPath;

  /// Root directory path representing the base navigation boundary.
  final String rootPath;

  /// Callback when a breadcrumb segment is tapped.
  final ValueChanged<String> onNavigate;

  /// Constructs DeviceFileBreadcrumbs.
  const DeviceFileBreadcrumbs({
    super.key,
    required this.currentPath,
    required this.rootPath,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();
    final segments = _computeSegments();

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: segments.length,
        separatorBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            AppIcons.chevronRight,
            size: 14,
            color: colors?.textTertiary ?? Colors.white24,
          ),
        ),
        itemBuilder: (context, index) {
          final segment = segments[index];
          final isCurrent = index == segments.length - 1;

          return Material(
            color: isCurrent
                ? (colors?.bgSurfaceInset ?? Colors.white10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: isCurrent ? null : () => onNavigate(segment.path),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (index == 0) ...[
                      Icon(
                        AppIcons.storage,
                        size: 14,
                        color: isCurrent
                            ? (colors?.brandPrimary ?? AppColors.primary)
                            : (colors?.textSecondary ?? Colors.white70),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      segment.name,
                      style: TextStyle(
                        color: isCurrent
                            ? (colors?.brandPrimary ?? AppColors.primary)
                            : (colors?.textSecondary ?? Colors.white70),
                        fontSize: 12,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<_BreadcrumbSegment> _computeSegments() {
    final segments = <_BreadcrumbSegment>[];
    segments.add(_BreadcrumbSegment(name: 'Storage', path: rootPath));

    if (currentPath == rootPath || !currentPath.startsWith(rootPath)) {
      return segments;
    }

    final relative = currentPath.substring(rootPath.length);
    final parts = relative.split('/').where((p) => p.isNotEmpty).toList();

    var accumulated = rootPath;
    for (final part in parts) {
      accumulated = '$accumulated/$part';
      segments.add(_BreadcrumbSegment(name: part, path: accumulated));
    }

    return segments;
  }
}

class _BreadcrumbSegment {
  final String name;
  final String path;

  _BreadcrumbSegment({required this.name, required this.path});
}
