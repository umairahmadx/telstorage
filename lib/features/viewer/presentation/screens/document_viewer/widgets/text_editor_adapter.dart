/*
 * File: text_editor_adapter.dart
 * Description: High-performance text and code editor widget using re_editor and re_highlight with language detection, line numbers gutter, and edit toggle.
 */

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/core/theme/app_colors_extension.dart';
import '../viewmodel/document_viewer_viewmodel.dart';

/// Text and code viewer/editor adapter widget.
class TextEditorAdapter extends StatefulWidget {
  /// Active ViewModel.
  final DocumentViewerViewModel viewModel;

  /// Constructs TextEditorAdapter.
  const TextEditorAdapter({super.key, required this.viewModel});

  @override
  State<TextEditorAdapter> createState() => _TextEditorAdapterState();
}

class _TextEditorAdapterState extends State<TextEditorAdapter> {
  late CodeLineEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(
      widget.viewModel.textContent,
    );
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant TextEditorAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.textContent != _controller.text) {
      _controller.text = widget.viewModel.textContent;
    }
  }

  void _onTextChanged() {
    if (widget.viewModel.isEditMode) {
      widget.viewModel.updateTextContent(_controller.text);
    }
  }

  @override
  void dispose() {
    _focusNode.unfocus();
    _focusNode.dispose();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  String _detectLanguage(String filename) {
    final ext = p.extension(filename).toLowerCase().replaceFirst('.', '');
    const map = {
      'dart': 'dart', 'py': 'python', 'js': 'javascript', 'ts': 'typescript',
      'json': 'json', 'xml': 'xml', 'html': 'html', 'css': 'css',
      'yaml': 'yaml', 'yml': 'yaml', 'md': 'markdown', 'sql': 'sql',
      'sh': 'bash', 'bat': 'batch', 'swift': 'swift', 'kt': 'kotlin',
      'java': 'java', 'c': 'c', 'cpp': 'cpp', 'h': 'c', 'rs': 'rust',
      'go': 'go', 'rb': 'ruby', 'php': 'php', 'lua': 'lua',
    };
    return map[ext] ?? 'plaintext';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).extension<AppColorsExtension>();
    final lang = _detectLanguage(widget.viewModel.currentFile.name);
    final mode = builtinAllLanguages[lang] ?? builtinAllLanguages['plaintext']!;

    return Container(
      color: colors?.bgPrimary ?? AppColors.grey900,
      child: CodeEditor(
        controller: _controller,
        focusNode: _focusNode,
        readOnly: !widget.viewModel.isEditMode,
        showCursorWhenReadOnly: false,
        wordWrap: true,
        style: CodeEditorStyle(
          fontSize: 13,
          fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
          codeTheme: CodeHighlightTheme(
            languages: {lang: CodeHighlightThemeMode(mode: mode)},
            theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
          ),
        ),
        indicatorBuilder: (context, editingCtrl, chunkCtrl, notifier) {
          return Row(
            children: [
              DefaultCodeLineNumber(
                controller: editingCtrl,
                notifier: notifier,
              ),
              const SizedBox(width: 8),
            ],
          );
        },
      ),
    );
  }
}
