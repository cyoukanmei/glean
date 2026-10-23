/// Display names for stored category / level codes.
const categoryLabels = {
  'tech': '科技',
  'business': '商业',
  'culture': '文化',
  'daily': '日常',
  'classic': '名著',
};

const levelLabels = {1: '初级', 2: '中级', 3: '高级'};

/// Learner reading speed used for "N 分钟" estimates.
const learnerWordsPerMinute = 150;

/// Estimated reading minutes for [words], at least 1.
int readingMinutes(int words) =>
    (words / learnerWordsPerMinute).ceil().clamp(1, 999);

/// Counts the way Chinese apps show them: 3421, 1.2万, 12万.
String compactCount(int n) {
  if (n < 10000) return '$n';
  final w = n / 10000;
  return '${w < 10 ? w.toStringAsFixed(1).replaceAll('.0', '') : w.round()}万';
}

String articleMeta(String category, int level, int wordCount) =>
    '${categoryLabels[category] ?? category} · '
    '${levelLabels[level] ?? 'L$level'} · $wordCount 词';
