import 'dart:convert';
import 'dart:io';

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
