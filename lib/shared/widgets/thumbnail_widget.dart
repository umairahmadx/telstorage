import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../core/models/file_record.dart';
import '../../core/services/service_locator.dart';

class ThumbnailWidget extends StatefulWidget {
  final FileRecord file;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget fallback;

  const ThumbnailWidget({
    super.key,
    required this.file,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    required this.fallback,
  });

  @override
  State<ThumbnailWidget> createState() => _ThumbnailWidgetState();
}

class _ThumbnailWidgetState extends State<ThumbnailWidget> {
  late Future<dynamic> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = ServiceLocator.instance.thumbnailRepository.getThumbnailData(widget.file);
  }

  @override
  void didUpdateWidget(covariant ThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.fileId != widget.file.fileId ||
        oldWidget.file.thumbnailFileId != widget.file.thumbnailFileId) {
      _thumbnailFuture = ServiceLocator.instance.thumbnailRepository.getThumbnailData(widget.file);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.file.thumbnailFileId == null) {
      return widget.fallback;
    }

    return FutureBuilder<dynamic>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
          final data = snapshot.data;
          ImageProvider imageProvider;
          if (kIsWeb && data is Uint8List) {
            imageProvider = MemoryImage(data);
          } else if (!kIsWeb && data is String) {
            imageProvider = FileImage(File(data));
          } else {
            return widget.fallback;
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image(
              image: imageProvider,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              errorBuilder: (_, __, ___) => widget.fallback,
            ),
          );
        }

        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }
}
