import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../../core/widgets/article_cover.dart';
import '../../../core/widgets/cover_catalog.dart';
import '../../articles/data/article_repository.dart';

/// One slide of the 书城 banner: an activity or a piece of news over the
/// picture of a related article.
class StoreBannerItem {
  const StoreBannerItem({
    required this.id,
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.article,
    required this.onTap,
  });

  /// Analytics name.
  final String id;

  /// Small label on top (活动 / 新上架 / 榜单).
  final String tag;
  final String title;
  final String subtitle;

  /// Supplies the background picture.
  final ArticleSummary article;
  final VoidCallback onTap;
}

/// Auto-playing banner carousel. Slides advance every [interval] and loop
/// around; a drag pauses the timer until the finger lifts. The picture
/// drifts against the swipe for a little depth, and the active dot
/// stretches into a bar.
class StoreBanner extends StatefulWidget {
  const StoreBanner({super.key, required this.items});

  final List<StoreBannerItem> items;

  static const height = 156.0;
  static const interval = Duration(milliseconds: 4500);

  @override
  State<StoreBanner> createState() => _StoreBannerState();
}

class _StoreBannerState extends State<StoreBanner> {
  /// Starts far from 0 so the carousel can loop both ways.
  static const _origin = 1000;

  final _controller = PageController(initialPage: _origin);
  Timer? _timer;
  int _page = _origin;

  int get _count => widget.items.length;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    if (_count < 2) return;
    _timer = Timer.periodic(StoreBanner.interval, (_) {
      if (!_controller.hasClients) return;
      _controller.nextPage(
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: StoreBanner.height,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _timer?.cancel();
              } else if (n is ScrollEndNotification) {
                _start();
              }
              return false;
            },
            child: PageView.builder(
              key: const Key('store-banner'),
              controller: _controller,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (context, p) {
                final item = widget.items[p % _count];
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final page = _controller.position.haveDimensions
                        ? _controller.page ?? p.toDouble()
                        : p.toDouble();
                    return _Slide(item: item, drift: p - page);
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _count; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: i == _page % _count ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page % _count
                      ? GleanColors.tint
                      : GleanColors.label3,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.item, required this.drift});

  final StoreBannerItem item;

  /// -1..1: how far this slide is from the centre, for the parallax.
  final double drift;

  @override
  Widget build(BuildContext context) {
    final a = item.article;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: PressableScale(
        pressedScale: 0.98,
        onTap: () {
          Analytics.track('banner_click', {'banner': item.id});
          item.onTap();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: GleanColors.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Wider than the slide so it can drift without showing edges.
                OverflowBox(
                  maxWidth: double.infinity,
                  child: FractionalTranslation(
                    translation: Offset(drift.clamp(-1.0, 1.0) * 0.12, 0),
                    child: FractionallySizedBox(
                      widthFactor: 1.3,
                      child: ArticleCover(
                        seed: a.id,
                        title: a.title,
                        image: CoverCatalog.instance[a.id],
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        GleanColors.tintDeep.withValues(alpha: 0.94),
                        GleanColors.tintDeep.withValues(alpha: 0.6),
                        GleanColors.tintDeep.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 120, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: GleanColors.gold,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            item.tag,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xD9FFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
