import 'dart:convert';

import 'package:flutter/services.dart';

/// A bundled cover picture (Wikimedia Commons, see assets/covers/manifest.json
/// and content/SOURCES.md for credits).
class CoverImage {
  const CoverImage({
    required this.asset,
    required this.aspect,
    required this.dominant,
    required this.artist,
    required this.license,
  });

  final String asset;

  /// Width / height.
  final double aspect;

  /// Average colour of the bottom of the picture; tints the backdrop a
  /// portrait cover stands on.
  final Color dominant;
  final String artist;
  final String license;

  bool get portrait => aspect < 0.95;
}

/// Article id -> cover picture, read once at startup from the manifest.
/// Articles without one (e.g. newly fetched) fall back to a drawn jacket.
class CoverCatalog {
  const CoverCatalog(this._covers);

  static CoverCatalog instance = const CoverCatalog({});

  final Map<String, CoverImage> _covers;

  CoverImage? operator [](String articleId) => _covers[articleId];

  static Future<void> load(AssetBundle bundle) async {
    final json =
        jsonDecode(await bundle.loadString('assets/covers/manifest.json'))
            as Map<String, dynamic>;
    instance = CoverCatalog({
      for (final MapEntry(:key, :value) in json.entries)
        if (value case final Map<String, dynamic> v)
          key: CoverImage(
            asset: 'assets/covers/${v['file']}',
            aspect: (v['width'] as num) / (v['height'] as num),
            dominant: Color(
              int.parse((v['dominant'] as String).substring(1), radix: 16) |
                  0xFF000000,
            ),
            artist: v['artist'] as String? ?? '',
            license: v['license'] as String? ?? '',
          ),
    });
  }
}
