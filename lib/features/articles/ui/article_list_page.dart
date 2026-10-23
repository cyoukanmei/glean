import 'package:flutter/material.dart';

import '../../../core/navigation/swipe_back_route.dart';
import '../../reader/ui/reader_page.dart';
import '../data/article_repository.dart';
import 'cover_hero.dart';

class ArticleListPage extends StatefulWidget {
  const ArticleListPage({super.key, required this.repository});

  final ArticleRepository repository;

  @override
  State<ArticleListPage> createState() => _ArticleListPageState();
}

class _ArticleListPageState extends State<ArticleListPage> {
  late final Future<List<ArticleSummary>> _articles = widget.repository.list();

  void _open(ArticleSummary article) {
    Navigator.of(context).push(
      SwipeBackPageRoute<void>(
        settings: RouteSettings(name: '/article/${article.id}'),
        builder: (_) =>
            ReaderPage(article: article, repository: widget.repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('English Reader')),
      body: FutureBuilder(
        future: _articles,
        builder: (context, snap) {
          final articles = snap.data;
          if (articles == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: articles.length,
            itemBuilder: (context, i) => _ArticleCard(
              article: articles[i],
              onTap: () => _open(articles[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article, required this.onTap});

  final ArticleSummary article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(
              dimension: 84,
              child: CoverHero(
                article: article,
                borderRadius: CoverHero.listRadius,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.summary,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${article.category} · L${article.level} · '
                    '${article.wordCount} words',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
