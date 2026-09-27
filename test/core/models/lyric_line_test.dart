/*
 * File: lyric_line_test.dart
 * Description: Unit tests for LyricLine model and LRC parser verifying timestamp calculation, metadata stripping, and chronological ordering.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/lyric_line.dart';

void main() {
  group('LyricLine Model & Parser Tests', () {
    test('parses standard 2-digit millisecond timestamps', () {
      const lrc = '''
[ti:Sample Song]
[ar:Sample Artist]
[00:12.34]First line of lyrics
[01:05.50]Second line of lyrics
''';

      final lines = LyricLine.parseLrc(lrc);
      expect(lines.length, equals(2));
      expect(lines[0].timestamp, equals(const Duration(seconds: 12, milliseconds: 340)));
      expect(lines[0].text, equals('First line of lyrics'));
      expect(lines[1].timestamp, equals(const Duration(minutes: 1, seconds: 5, milliseconds: 500)));
      expect(lines[1].text, equals('Second line of lyrics'));
    });

    test('parses 3-digit millisecond timestamps', () {
      const lrc = '[02:14.678]High precision line';
      final lines = LyricLine.parseLrc(lrc);
      expect(lines.length, equals(1));
      expect(lines[0].timestamp, equals(const Duration(minutes: 2, seconds: 14, milliseconds: 678)));
      expect(lines[0].text, equals('High precision line'));
    });

    test('parses multiple timestamps per line and sorts chronologically', () {
      const lrc = '[01:00.00][00:20.00]Repeated refrain';
      final lines = LyricLine.parseLrc(lrc);
      expect(lines.length, equals(2));
      expect(lines[0].timestamp, equals(const Duration(seconds: 20)));
      expect(lines[0].text, equals('Repeated refrain'));
      expect(lines[1].timestamp, equals(const Duration(minutes: 1)));
      expect(lines[1].text, equals('Repeated refrain'));
    });

    test('strips metadata tags like [al:], [by:], [offset:]', () {
      const lrc = '''
[al:Greatest Hits]
[by:LyricMaster]
[offset:+200]
[00:05.00]Valid line
''';
      final lines = LyricLine.parseLrc(lrc);
      expect(lines.length, equals(1));
      expect(lines[0].text, equals('Valid line'));
    });

    test('parses plain unsynchronized lyrics with zero timestamps', () {
      const plain = '''
Line 1
Line 2
Line 3
''';
      final lines = LyricLine.parsePlain(plain);
      expect(lines.length, equals(3));
      expect(lines[0].text, equals('Line 1'));
      expect(lines[0].timestamp, equals(Duration.zero));
    });

    test('returns empty list for empty input', () {
      expect(LyricLine.parseLrc(''), isEmpty);
      expect(LyricLine.parseLrc('   \n  \r\n '), isEmpty);
      expect(LyricLine.parsePlain(''), isEmpty);
    });
  });
}
