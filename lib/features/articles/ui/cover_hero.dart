import 'package:flutter/material.dart';

import '../../../core/widgets/article_cover.dart';
import '../../../core/widgets/cover_catalog.dart';
import '../data/article_repository.dart';
import 'labels.dart';

/// An article's cover on a list: the shared element the reader opens from.
///
/// Mounted covers register themselves, so opening the reader can find where
/// the tapped cover is on screen ([rectOf]) and open it as a book from
/// there (see BookOpenTransition); while that book is off the list,
/// [lifted] hides the original so there is only one.
class CoverHero extends StatefulWidget {
  const CoverHero({
    super.key,
    required this.article,
    required this.surface,
    required this.borderRadius,
  });

  final ArticleSummary article;

  /// Which list the card lives in (e.g. a category tab). The same article can
  /// sit in several kept-alive tabs at once, so the tag must include it.
  final String surface;
  final double borderRadius;

  static const listRadius = 16.0;

  static Object tagFor(String surface, String articleId) =>
      'cover-$surface-$articleId';

  /// Tag of the cover currently travelling as a book, hidden on its list.
  static final lifted = ValueNotifier<Object?>(null);

  static final _mounted = <Object, _CoverHeroState>{};

  /// The cover shown for [articleId] on [surface], in global coordinates,
  /// with its corner radius; null when it is not laid out on screen.
  static (Rect, double)? rectOf(String surface, String articleId) {
    final state = _mounted[tagFor(surface, articleId)];
    final box = state?.context.findRenderObject();
    if (state == null || box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final view = View.of(state.context);
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    if (!screen.overlaps(rect)) return null;
    return (rect, state.widget.borderRadius);
  }

  /// The cover picture of [article] at [radius] (the flying book).
  static Widget coverOf(ArticleSummary article, double radius) => ArticleCover(
    seed: article.id,
    title: article.title,
    band:
        article.author?.toUpperCase() ??
        'GLEAN · ${categoryLabels[article.category] ?? article.category}',
    footer: article.author != null
        ? '拾读 · 名著'
        : '${levelLabels[article.level] ?? ''} · ${article.wordCount} 词',
    image: CoverCatalog.instance[article.id],
    borderRadius: BorderRadius.circular(radius),
  );

  @override
  State<CoverHero> createState() => _CoverHeroState();
}

class _CoverHeroState extends State<CoverHero> {
  Object get _tag => CoverHero.tagFor(widget.surface, widget.article.id);

  @override
  void initState() {
    super.initState();
    CoverHero._mounted[_tag] = this;
  }

  @override
  void didUpdateWidget(CoverHero old) {
    super.didUpdateWidget(old);
    final oldTag = CoverHero.tagFor(old.surface, old.article.id);
    if (CoverHero._mounted[oldTag] == this) CoverHero._mounted.remove(oldTag);
    CoverHero._mounted[_tag] = this;
  }

  @override
  void dispose() {
    if (CoverHero._mounted[_tag] == this) CoverHero._mounted.remove(_tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: CoverHero.lifted,
      builder: (context, lifted, child) =>
          Opacity(opacity: lifted == _tag ? 0 : 1, child: child),
      child: CoverHero.coverOf(widget.article, widget.borderRadius),
    );
  }
}
