/// Display names for stored category / level codes.
const categoryLabels = {
  'tech': '科技',
  'business': '商业',
  'culture': '文化',
  'daily': '日常',
};

const levelLabels = {1: '初级', 2: '中级', 3: '高级'};

String articleMeta(String category, int level, int wordCount) =>
    '${categoryLabels[category] ?? category} · '
    '${levelLabels[level] ?? 'L$level'} · $wordCount 词';
