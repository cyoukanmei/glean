import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Empty / offline / done states: a designer illustration over a short
/// message. SVGs stay sharp at any size; text is rendered by Flutter so it
/// follows the theme and stays translatable.
class StateIllustration extends StatelessWidget {
  const StateIllustration({
    super.key,
    required this.asset,
    required this.title,
    this.message,
    this.width = 200,
  });

  static const emptyArticles = 'assets/illustrations/empty-articles.svg';
  static const emptyVocabulary = 'assets/illustrations/empty-vocabulary.svg';
  static const offline = 'assets/illustrations/offline.svg';
  static const readingComplete = 'assets/illustrations/reading-complete.svg';
  static const reading = 'assets/illustrations/reading.webp';

  final String asset;
  final String title;
  final String? message;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picture = asset.endsWith('.svg')
        ? SvgPicture.asset(asset, width: width)
        : Image.asset(asset, width: width, fit: BoxFit.contain);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        picture,
        const SizedBox(height: 12),
        Text(title, style: theme.textTheme.titleMedium),
        if (message != null) ...[
          const SizedBox(height: 4),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
