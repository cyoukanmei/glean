/// The event catalogue: every event the app sends, with its required and
/// optional business parameters. Common parameters (device_id, user_id,
/// session_id, seq, app_version, platform, network, ts) are added to every
/// event by [AnalyticsService] and are not listed here.
///
/// Naming: snake_case `<object>_<action>` (article_open, word_collect) or a
/// measured quantity (read_duration, scroll_depth).
class EventSpec {
  const EventSpec(
    this.description, {
    this.required = const {},
    this.optional = const {},
  });

  final String description;
  final Set<String> required;
  final Set<String> optional;
}

const eventSpecs = <String, EventSpec>{
  // App and session
  'app_open': EventSpec('冷启动打开 App', required: {'cold_start_ms'}),
  'session_start': EventSpec(
    '新会话开始（冷启动，或后台超过 30 秒后回到前台）',
    required: {'reason'},
    optional: {'away_ms'},
  ),
  'app_background': EventSpec('App 进入后台', required: {'foreground_ms'}),
  'page_view': EventSpec('底栏切换页面', required: {'page'}),
  'login': EventSpec('登录成功', required: {'user'}),
  'register': EventSpec('注册成功', required: {'user'}),
  'logout': EventSpec('退出登录'),
  'profile_update': EventSpec('保存个人资料', optional: {'goal'}),

  // Lists
  'article_impression': EventSpec(
    '列表卡片曝光：可见面积 ≥ 50% 且持续 ≥ 500 ms，同一会话同一列表只记一次',
    required: {'article_id', 'surface', 'position'},
  ),
  'category_switch': EventSpec('切换分类', required: {'category'}),
  'level_filter': EventSpec('切换难度筛选', required: {'level'}),
  'search': EventSpec(
    '提交搜索（防抖后的关键词）',
    required: {'query', 'results'},
    optional: {'from_history'},
  ),
  'search_result_open': EventSpec(
    '从搜索结果打开文章',
    required: {'article_id', 'position'},
  ),
  'offline_hit': EventSpec('离线时下拉刷新，展示本地内容', required: {'surface'}),
  'shelf_filter': EventSpec('书架切换筛选（全部/在读/收藏/稍后/读完）', required: {'filter'}),
  'banner_click': EventSpec('点击书城 banner', required: {'banner'}),
  'store_entry': EventSpec('点击书城快捷入口', required: {'entry'}),
  'rank_switch': EventSpec('切换榜单', required: {'board'}),

  // Reading
  'article_open': EventSpec(
    '打开文章',
    required: {'article_id', 'surface'},
    optional: {'jump'},
  ),
  'scroll_depth': EventSpec(
    '阅读滚动深度首次达到 25/50/75/100%',
    required: {'article_id', 'depth'},
  ),
  'read_duration': EventSpec(
    '离开文章时上报本次有效阅读时长（前台可见且有交互，见 ReadingSession）',
    required: {'article_id', 'active_ms', 'max_progress'},
  ),
  'article_finish': EventSpec('读完（看过 90% 且读够最短时长）', required: {'article_id'}),
  'article_share': EventSpec('分享文章标题', required: {'article_id'}),
  'article_mark': EventSpec(
    '收藏 / 稍后再读（on=false 为取消）',
    required: {'article_id', 'kind', 'on', 'surface'},
  ),
  'reader_settings': EventSpec('修改阅读设置', required: {'setting', 'value'}),

  // Words
  'word_lookup': EventSpec('长按取词', required: {'word', 'found', 'article_id'}),
  'word_collect': EventSpec(
    '收藏生词',
    required: {'lemma', 'article_id', 'surface'},
  ),
  'word_delete': EventSpec(
    '删除生词',
    required: {'lemma', 'surface'},
    optional: {'article_id'},
  ),
  'word_pronounce': EventSpec('播放发音', required: {'word', 'surface'}),
  'word_review': EventSpec('复习卡片打分', required: {'lemma', 'status'}),

  // AI
  'ai_guide_open': EventSpec('展开 AI 导读', required: {'article_id'}),
  'quiz_open': EventSpec('打开阅读理解', required: {'article_id', 'surface'}),
  'quiz_answer': EventSpec(
    '回答一道阅读理解题',
    required: {'article_id', 'index', 'correct'},
  ),
  'quiz_complete': EventSpec(
    '完成阅读理解',
    required: {'article_id', 'correct', 'total'},
  ),
  'ai_explain': EventSpec(
    '取词面板 AI 解释（source: cache / api / error）',
    required: {'lemma', 'source'},
    optional: {'latency_ms'},
  ),

  // Community
  'coread_like': EventSpec('社区帖子点赞', required: {'post', 'like'}),
  'coread_comment': EventSpec(
    '发表评论（reply 为回复某条评论）',
    required: {'post'},
    optional: {'reply'},
  ),
  'coread_comment_like': EventSpec('评论点赞', required: {'comment', 'like'}),
  'coread_share': EventSpec(
    '分享金句到社区',
    required: {'article_id'},
    optional: {'surface'},
  ),

  'appearance_set': EventSpec('切换外观（跟随系统/浅色/深色）', required: {'value'}),

  // Sync and reminders
  'sync_run': EventSpec(
    '一次同步完成',
    required: {'pushed', 'pulled', 'conflicts', 'ok'},
  ),
  'reminder_set': EventSpec(
    '设置每日阅读提醒（exact：是否为准点闹钟）',
    required: {'enabled'},
    optional: {'time', 'exact'},
  ),
};

/// Problems with [params] for [name]: unknown event, missing required or
/// unexpected keys. Empty when the event matches the catalogue.
List<String> validateEvent(String name, Map<String, Object?> params) {
  final spec = eventSpecs[name];
  if (spec == null) return ['unknown event "$name"'];
  return [
    for (final key in spec.required)
      if (!params.containsKey(key)) 'missing required "$key"',
    for (final key in params.keys)
      if (!spec.required.contains(key) && !spec.optional.contains(key))
        'unexpected "$key"',
  ];
}
