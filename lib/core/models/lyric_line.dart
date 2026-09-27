/*
 * File: lyric_line.dart
 * Description: Data model and parser for synchronized and plain LRC lyrics with timestamp indexing.
 */

/// Represents a single synchronized lyric line with timestamp and display text.
class LyricLine {
  /// Playback offset timestamp where this lyric line begins.
  final Duration timestamp;

  /// Text content of this lyric line.
  final String text;

  /// Constructs a LyricLine.
  const LyricLine({
    required this.timestamp,
    required this.text,
  });

  /// Regular expression matching standard LRC timestamp tags like [mm:ss.xx] or [mm:ss.xxx].
  static final RegExp _timestampRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]');

  /// Parses a raw .lrc string into a chronologically sorted list of [LyricLine]s.
  static List<LyricLine> parseLrc(String rawLrc) {
    if (rawLrc.trim().isEmpty) return const [];

    final lines = rawLrc.split(RegExp(r'\r?\n'));
    final parsed = <LyricLine>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Skip metadata tags like [ti:], [ar:], [al:], etc.
      if (RegExp(r'^\[(ti|ar|al|by|offset|length|re|ve):', caseSensitive: false).hasMatch(line)) {
        continue;
      }

      final matches = _timestampRegex.allMatches(line).toList();
      if (matches.isEmpty) continue;

      // Extract lyric text after removing all timestamp tags
      final text = line.replaceAll(_timestampRegex, '').trim();

      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final subStr = match.group(3) ?? '0';
        int milliseconds = 0;
        if (subStr.length == 1) {
          milliseconds = (int.tryParse(subStr) ?? 0) * 100;
        } else if (subStr.length == 2) {
          milliseconds = (int.tryParse(subStr) ?? 0) * 10;
        } else {
          milliseconds = int.tryParse(subStr) ?? 0;
        }

        final duration = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        parsed.add(LyricLine(
          timestamp: duration,
          text: text,
        ));
      }
    }

    parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return parsed;
  }

  /// Parses plain unsynchronized lyrics into sequential [LyricLine]s with zero duration.
  static List<LyricLine> parsePlain(String plainText) {
    if (plainText.trim().isEmpty) return const [];
    final lines = plainText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return lines
        .map((text) => LyricLine(timestamp: Duration.zero, text: text))
        .toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricLine &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          text == other.text;

  @override
  int get hashCode => timestamp.hashCode ^ text.hashCode;

  @override
  String toString() =>
      '[${timestamp.inMinutes}:${(timestamp.inSeconds % 60).toString().padLeft(2, '0')}.${(timestamp.inMilliseconds % 1000).toString().padLeft(3, '0')}] $text';
}
