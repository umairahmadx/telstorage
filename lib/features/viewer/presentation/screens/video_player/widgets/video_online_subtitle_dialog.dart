/*
 * File: video_online_subtitle_dialog.dart
 * Description: Search dialog querying OpenSubtitles with language filtering, ISP block detection, and direct download integration.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/services/subtitle_service.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Dialog allowing users to search online subtitles and load them directly into playback.
class VideoOnlineSubtitleDialog extends StatefulWidget {
  final String videoTitle;
  final ValueChanged<String> onSubtitleDownloaded;

  const VideoOnlineSubtitleDialog({
    super.key,
    required this.videoTitle,
    required this.onSubtitleDownloaded,
  });

  static Future<void> show(
    BuildContext context, {
    required String videoTitle,
    required ValueChanged<String> onSubtitleDownloaded,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => VideoOnlineSubtitleDialog(
        videoTitle: videoTitle,
        onSubtitleDownloaded: onSubtitleDownloaded,
      ),
    );
  }

  @override
  State<VideoOnlineSubtitleDialog> createState() => _VideoOnlineSubtitleDialogState();
}

class _VideoOnlineSubtitleDialogState extends State<VideoOnlineSubtitleDialog> {
  late final TextEditingController _queryController;
  String _selectedLanguage = 'en';
  bool _isLoading = false;
  List<SubtitleSearchResult> _results = const [];
  String? _downloadingId;
  String? _errorMessage;
  bool _isIspBlocked = false;

  static const Map<String, String> _languages = {
    'all': 'All Languages',
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'ar': 'Arabic',
    'hi': 'Hindi',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'zh': 'Chinese',
    'ja': 'Japanese',
    'ko': 'Korean',
  };

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(
      text: SubtitleService.cleanTitleForSearch(widget.videoTitle),
    );
    _performSearch();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isIspBlocked = false;
    });

    try {
      final results = await SubtitleService.instance.searchSubtitles(
        query: _queryController.text,
        language: _selectedLanguage,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } on SubtitleIspBlockedException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isIspBlocked = true;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Search error: $e';
      });
    }
  }

  Future<void> _downloadAndApply(SubtitleSearchResult item) async {
    setState(() => _downloadingId = item.id);
    try {
      final path = await SubtitleService.instance.downloadOpenSubtitle(
        fileId: item.fileId,
        downloadUrl: item.downloadUrl,
      );
      if (!mounted) return;
      widget.onSubtitleDownloaded(path);
      Navigator.of(context).pop();
    } on SubtitleIspBlockedException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _isIspBlocked = true;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingId = null;
        _errorMessage = 'Download failed. Please check network.';
      });
    }
  }

  Future<void> _pickLocalFile() async {
    final path = await SubtitleService.instance.pickLocalSubtitleFile();
    if (path != null && mounted) {
      widget.onSubtitleDownloaded(path);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Dialog(
      backgroundColor: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.borderSubtle),
      ),
      child: Container(
        width: 480,
        height: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AppIcons.subtitles, color: colors.accentPrimary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Search Subtitles Online',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(AppIcons.close, color: colors.textTertiary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search title...',
                      hintStyle: TextStyle(color: colors.textTertiary),
                      prefixIcon: Icon(AppIcons.search, color: colors.textTertiary, size: 18),
                      filled: true,
                      fillColor: colors.bgSurfaceInset,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: colors.bgSurfaceInset,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedLanguage,
                    dropdownColor: colors.bgSurface,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    icon: Icon(AppIcons.dropdownArrow, color: colors.textSecondary, size: 18),
                    items: _languages.entries.map((e) {
                      return DropdownMenuItem(value: e.key, child: Text(e.value));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedLanguage = val);
                        _performSearch();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: colors.accentPrimary))
                  : _isIspBlocked
                      ? Center(
                          child: SingleChildScrollView(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.bgSurfaceInset,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: colors.borderSubtle),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield_outlined, color: colors.accentPrimary, size: 36),
                                  const SizedBox(height: 10),
                                  Text(
                                    'ISP Block Detected',
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'OpenSubtitles is blocked by your internet provider in compliance with local court orders.\n\nTurn on a VPN or Private DNS (1.1.1.1) to unblock, or load a subtitle from local storage.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: colors.accentPrimary,
                                    ),
                                    onPressed: _pickLocalFile,
                                    icon: Icon(Icons.folder_open_rounded, size: 18, color: colors.bgPrimary),
                                    label: Text(
                                      'Load from Storage',
                                      style: TextStyle(color: colors.bgPrimary, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : _errorMessage != null
                          ? Center(
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.textSecondary),
                              ),
                            )
                          : _results.isEmpty
                              ? Center(
                                  child: Text(
                                    'No subtitles found.',
                                    style: TextStyle(color: colors.textSecondary),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _results.length,
                                  separatorBuilder: (_, __) => Divider(color: colors.borderSubtle, height: 1),
                                  itemBuilder: (ctx, idx) {
                                    final item = _results[idx];
                                    final isDownloading = _downloadingId == item.id;

                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      title: Text(
                                        item.title,
                                        style: TextStyle(color: colors.textPrimary, fontSize: 13),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '${item.language.toUpperCase()} • ${item.downloadCount} downloads',
                                        style: TextStyle(color: colors.textTertiary, fontSize: 11),
                                      ),
                                      trailing: isDownloading
                                          ? SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                color: colors.accentPrimary,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(AppIcons.download, color: colors.accentPrimary, size: 20),
                                      onTap: isDownloading ? null : () => _downloadAndApply(item),
                                    );
                                  },
                                ),
            ),
          ],
        ),
      ),
    );
  }
}
