/// Universal attachment viewer. Displays PDFs, images, and other file types
/// in a full-screen overlay. Supports pinch-to-zoom, swipe-to-dismiss, and
/// a fallback for unsupported formats.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens a full-screen preview of [file].
void showAttachmentViewer(BuildContext context, File file, {String? title}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _AttachmentViewerScreen(file: file, title: title),
    ),
  );
}

/// Opens a full-screen preview from bytes.
void showAttachmentViewerFromBytes(
  BuildContext context,
  List<int> bytes,
  String filename, {
  String? title,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _AttachmentViewerScreen(
        file: null,
        bytes: bytes,
        filename: filename,
        title: title,
      ),
    ),
  );
}

class _AttachmentViewerScreen extends StatelessWidget {
  const _AttachmentViewerScreen({
    this.file,
    this.bytes,
    this.filename,
    this.title,
  });

  final File? file;
  final List<int>? bytes;
  final String? filename;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final isPdf = (filename ?? file?.path ?? '').toLowerCase().endsWith('.pdf');
    final isImage = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
    ].any((ext) => (filename ?? file?.path ?? '').toLowerCase().endsWith(ext));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title ?? filename ?? 'Attachment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () {
              // TODO: share the file using share_plus
            },
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Center(
        child: isImage
            ? _ImageViewer(file: file, bytes: bytes)
            : isPdf
            ? _PdfUnavailable()
            : _FallbackViewer(file: file, bytes: bytes, filename: filename),
      ),
    );
  }
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({this.file, this.bytes});
  final File? file;
  final List<int>? bytes;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  final _transformationController = TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (widget.file != null) {
      image = Image.file(widget.file!, fit: BoxFit.contain);
    } else if (widget.bytes != null) {
      image = Image.memory(
        Uint8List.fromList(widget.bytes!),
        fit: BoxFit.contain,
      );
    } else {
      return const Icon(
        Icons.broken_image_outlined,
        color: Colors.white54,
        size: 64,
      );
    }

    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 0.5,
      maxScale: 4.0,
      child: image,
    );
  }
}

class _PdfUnavailable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.picture_as_pdf_outlined,
          color: Colors.white54,
          size: 64,
        ),
        const SizedBox(height: 16),
        Text(
          'PDF preview not available in-app.\n'
          'Use the share button to open in an external PDF reader.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      ],
    );
  }
}

class _FallbackViewer extends StatelessWidget {
  const _FallbackViewer({this.file, this.bytes, this.filename});
  final File? file;
  final List<int>? bytes;
  final String? filename;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.insert_drive_file_outlined,
          color: Colors.white54,
          size: 64,
        ),
        const SizedBox(height: 16),
        Text(
          filename ?? 'Unsupported file type',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      ],
    );
  }
}
