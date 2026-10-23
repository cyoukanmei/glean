import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/analytics/analytics.dart';
import '../../articles/data/article_repository.dart';
import '../data/marks_repository.dart';

/// Sets or clears a mark, records it, and tells pages to reload.
Future<void> setMark(
  WidgetRef ref,
  ArticleSummary article,
  MarkKind kind, {
  required bool on,
  required String surface,
}) async {
  await ref
      .read(marksRepositoryProvider)
      .set(ref.read(currentUserIdProvider), article.id, kind, on: on);
  Analytics.track('article_mark', {
    'article_id': article.id,
    'kind': kind.name,
    'on': on,
    'surface': surface,
  });
  ref.read(marksRevisionProvider.notifier).bump();
}

/// Long-press menu on an article card: 收藏 and 稍后再读, each toggling.
Future<void> showArticleActions(
  BuildContext context,
  WidgetRef ref,
  ArticleSummary article, {
  required String surface,
}) async {
  HapticFeedback.mediumImpact();
  final marks = await ref
      .read(marksRepositoryProvider)
      .of(ref.read(currentUserIdProvider), article.id);
  if (!context.mounted) return;
  final picked = await showCupertinoModalPopup<MarkKind>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      actions: [
        for (final kind in MarkKind.values)
          CupertinoActionSheetAction(
            key: Key('action-${kind.name}'),
            onPressed: () => Navigator.pop(context, kind),
            child: Text(
              marks.contains(kind)
                  ? (kind == MarkKind.favorite ? '取消收藏' : '移出稍后再读')
                  : kind == MarkKind.favorite
                  ? '收藏'
                  : '稍后再读',
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  final on = !marks.contains(picked);
  await setMark(ref, article, picked, on: on, surface: surface);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(on ? '已加入「${picked.label}」' : '已移出「${picked.label}」'),
      ),
    );
}
