import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Renders EcoScan images from native files, Web data URLs, blob URLs or HTTPS.
class AppImage extends StatelessWidget {
  const AppImage({
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback,
    super.key,
  });

  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final placeholder = fallback ?? const Icon(Icons.image_outlined);
    if (source.isEmpty) return placeholder;

    if (source.startsWith('data:image/')) {
      final bytes = _decodeDataUrl(source);
      if (bytes == null) return placeholder;
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      );
    }

    if (source.startsWith('https://') ||
        source.startsWith('http://') ||
        (kIsWeb && source.startsWith('blob:'))) {
      return Image.network(
        source,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => placeholder,
      );
    }

    if (source.startsWith('firebase-storage://')) {
      return _FirebaseStorageImage(
        path: source.substring('firebase-storage://'.length),
        width: width,
        height: height,
        fit: fit,
        fallback: placeholder,
      );
    }

    if (kIsWeb) return placeholder;
    return Image.file(
      File(source),
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
  }

  static Uint8List? _decodeDataUrl(String value) {
    final comma = value.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(value.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }
}

class _FirebaseStorageImage extends StatefulWidget {
  const _FirebaseStorageImage({
    required this.path,
    required this.width,
    required this.height,
    required this.fit,
    required this.fallback,
  });

  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget fallback;

  @override
  State<_FirebaseStorageImage> createState() => _FirebaseStorageImageState();
}

class _FirebaseStorageImageState extends State<_FirebaseStorageImage> {
  late Future<Uint8List?> _image;

  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void didUpdateWidget(covariant _FirebaseStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _image = _load();
  }

  Future<Uint8List?> _load() async {
    try {
      return await FirebaseStorage.instance.ref(widget.path).getData(
        10 * 1024 * 1024,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _image,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes == null || bytes.isEmpty) return widget.fallback;
      return Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => widget.fallback,
      );
    },
  );
}
