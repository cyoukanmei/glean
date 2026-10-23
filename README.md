# 拾读 Glean

离线优先的英语阅读学习 App（Flutter，Android 真机）。按分类和难度读短文与名著选章，长按取词收藏到生词本，随时从上次的位置接着读；断网也能完成「列表 → 阅读 → 取词收藏 → 进度落库」整条链路，联网后自动同步。

- 代码：`lib/`（70 多个文件），测试：`test/`（`fvm flutter test`，全部通过）
- 设计参考页：`../docs/design/ui-reference.html`（iOS 风格，含 4 项动效的可交互演示）
- 内容与图片来源：[content/SOURCES.md](content/SOURCES.md)、[content/COVER_CREDITS.md](content/COVER_CREDITS.md)

## 目录

1. [技术选型](#1-技术选型)
2. [本地启动](#2-本地启动)
3. [架构](#3-架构)
4. [本地数据库：建表、索引与迁移](#4-本地数据库建表索引与迁移)
5. [离线、幂等与同步](#5-离线幂等与同步)
6. [动效清单](#6-动效清单)
7. [数据埋点方案](#7-数据埋点方案)
8. [登录与鉴权（Mock）](#8-登录与鉴权mock)
9. [打包、签名与上架](#9-打包签名与上架)
10. [已知缺陷与优化思路](#10-已知缺陷与优化思路)

---

## 1. 技术选型

| 方面 | 选择 | 理由 |
|---|---|---|
| 跨端框架 | **Flutter 3.44.9**（FVM 锁定在 `.fvmrc`） | 自绘引擎，动效与手势在 Android/iOS 上表现一致；`Hero`、`AnimationController`、物理模拟（`SpringSimulation`）都是一等公民，本题 30% 的动效分可以不依赖第三方动画库完成 |
| 本地存储 | **sqflite + 手写 SQL**，辅以 `shared_preferences` | 题目要求给出建表 SQL 与迁移策略；手写 SQL 让 UPSERT、keyset 分页、幂等写入都一目了然。KV 只存设置类数据（字号、主题、难度筛选、搜索历史） |
| 状态管理 | **Riverpod 3**，只做依赖注入、设置和「数据变了」的通知（`Revision` 计数器） | 页面状态留在各自 `State` 里，避免全局 store；仓库都能在测试里替换 |
| 动效 | 原生 API：`Hero`、自写 `PageRoute`、`AnimationController`、`CustomPainter`（彩纸、进度环） | 庆祝动画自绘，无 Lottie 资源需要授权或加载 |
| 测试 | `flutter_test` + `sqflite_common_ffi`（真实 SQLite 文件） | 仓库、迁移、同步、埋点在桌面 SQLite 上跑真实 SQL；组件测试用内存假仓库 |
| CI | GitHub Actions：format → analyze → test → `build apk --release`，产物上传 | `.github/workflows/ci.yml` |

只交付 Android（minSdk 30：UPSERT 需要 SQLite ≥ 3.24，Android 11 起自带）。iOS 工程可编译，未在真机验证。

## 2. 本地启动

```bash
# Flutter 版本由 FVM 锁定
fvm install
fvm flutter pub get
fvm flutter run            # 连接 Android 真机（Android 11+）
fvm flutter test           # 全部单测 / 组件测试
```

- 首次启动会把 `assets/seed/` 里的种子数据（34 篇文章、6 千多条词典）导入 SQLite，开屏期间完成，之后每次启动只读一个 19 字节的 `manifest.json` 判断是否需要重导。
- 演示账号：**demo / glean123**（登录页点提示条即可填入），也可以注册新账号。
- 种子重建（编辑 `content/` 后）：`python -I tool/build_seed.py --ecdict path/to/ecdict.csv`。

## 3. 架构

```
lib/
  app/            根组件（开屏 → 登录/首页）、底栏、外观、全局 provider
  core/
    analytics/    事件目录、SQLite 事件队列、上报、会话、曝光、分析查询
    db/           建表与迁移、种子导入
    design/       设计 token（纸感/经典两套配色 × 浅/深色）、主题、iOS 风格基础组件、进度环
    navigation/   手势可跟随的返回路由
    widgets/      封面、彩纸、骨架屏、渐入、收藏按钮…
  features/
    articles/     列表、分类、分页、搜索仓库、封面 Hero
    reader/       阅读页、进度会话、阅读设置、读完卡片
    vocab/        取词、生词本、复习卡片
    coread/       共读（本地 mock 社区）
    profile/      我的、编辑资料、提醒、埋点调试面板
    library/      收藏、稍后再读、阅读历史（我的书架）
    auth/         登录注册（mock 后端）
    sync/         同步服务与 mock 服务端
    search/       全文搜索页
```

**页面与状态**：底栏四个 Tab 放在 `IndexedStack` 里保持状态；阅读页、搜索、编辑资料等推到根 Navigator 上（底栏随之隐藏）。仓库通过 Riverpod 注入；写入后 bump 对应的 `Revision`（进度、生词、文章），关心它的页面各自重新读库。

**数据流**：

```
UI ──写──▶ Repository ──SQL──▶ SQLite（dirty=1）
                                   │
                    SyncService ◀──┘  联网/回前台/改动后 3 s/每分钟
                        │  push 脏行（带 base_version）
                        ▼
                 MockSyncServer（独立 SQLite 文件，模拟 REST）
                        │  返回合并后的记录；pull 其他设备的变更
                        ▼
                 本地按同一规则合并，dirty=0 ──▶ bump Revision ──▶ 页面刷新

Analytics.track ──▶ event_queue（SQLite）──批量──▶ MockCollector ──▶ collected_events
```

## 4. 本地数据库：建表、索引与迁移

完整 DDL 在 [`lib/core/db/schema.dart`](lib/core/db/schema.dart)（版本 4）。表关系：

```
users 1─* sessions
users 1─* reading_progress *─1 articles      （PK: user_id + article_id）
users 1─* reading_segments                    （阅读时长分段，按天统计）
users 1─* vocab                                （UNIQUE: user_id + lemma，软删除墓碑）
users 1─* article_marks *─1 articles          （收藏 / 稍后再读，PK: user_id + article_id + kind）
dict / word_forms                              （词典与屈折形式 → 原形）
event_queue → collected_events / upload_log   （埋点队列、模拟数仓、上报日志）
app_meta                                       （种子版本、同步游标）
```

关键表摘录：

```sql
CREATE TABLE reading_progress (
  user_id TEXT NOT NULL,
  article_id TEXT NOT NULL REFERENCES articles(id),
  scroll_offset REAL NOT NULL DEFAULT 0,
  anchor_para INTEGER NOT NULL DEFAULT 0,   -- 段落锚点：字号变了也能恢复
  anchor_delta REAL NOT NULL DEFAULT 0,
  font_scale REAL NOT NULL DEFAULT 1,
  progress REAL NOT NULL DEFAULT 0,
  max_progress REAL NOT NULL DEFAULT 0,
  status INTEGER NOT NULL DEFAULT 0,       -- 0 未读 1 在读 2 读完
  finished_at INTEGER,
  last_read_at INTEGER NOT NULL,
  version INTEGER NOT NULL DEFAULT 0,      -- 服务端版本（同步用）
  dirty INTEGER NOT NULL DEFAULT 1,        -- 待上传
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, article_id)
) WITHOUT ROWID;

CREATE TABLE vocab (
  id TEXT PRIMARY KEY, user_id TEXT NOT NULL,
  word TEXT NOT NULL, lemma TEXT NOT NULL, definition TEXT NOT NULL,
  article_id TEXT NOT NULL, para_index INTEGER NOT NULL,
  char_start INTEGER NOT NULL, char_end INTEGER NOT NULL, sentence TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  deleted_at INTEGER,                      -- 墓碑，删除也能同步
  version INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1,
  status INTEGER NOT NULL DEFAULT 0        -- v2：0 新词 1 认识 2 已掌握
);

CREATE TABLE event_queue (
  event_id TEXT PRIMARY KEY, name TEXT NOT NULL, ts INTEGER NOT NULL,
  session_id TEXT NOT NULL, seq INTEGER NOT NULL, user_id TEXT,
  params TEXT NOT NULL,                    -- JSON：业务参数 + 公共参数
  status INTEGER NOT NULL DEFAULT 0,       -- 0 待发 1 发送中 2 已发 3 放弃
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER NOT NULL DEFAULT 0,
  batch_id TEXT, created_at INTEGER NOT NULL
);
```

| 索引 | 用途 |
|---|---|
| `idx_articles_feed (category, level, published_at DESC, id DESC)` | 分类 + 难度筛选下的 keyset 分页，任意深度都是一次索引范围扫描 |
| `idx_progress_recent (user_id, last_read_at DESC)` | 「继续阅读」卡片取最近一篇 |
| `ux_vocab_user_lemma (user_id, lemma)` UNIQUE | 同一个词只收藏一次；删除后再收藏复用同一行 |
| `idx_vocab_list (user_id, deleted_at, created_at DESC)` | 生词本列表 |
| `idx_seg_day (user_id, local_day)` | 「我的」今日目标、本周打卡、连续天数 |
| `idx_eq_pick (status, next_attempt_at, ts)` | 上报时挑出到期的待发事件 |

**迁移策略**：`schemaV1` + `migrations[v]` 依次执行，新装与升级走同一组语句（有测试比对两条路径的最终 schema 完全一致）。sqflite 把 onCreate/onUpgrade 放在一个事务里，失败即回滚到旧版本。

- v2：`vocab` 加 `status` 列。
- v4：`article_marks` 表（收藏 / 稍后再读），同样带 `version`/`dirty`/墓碑，随同步上传。
- v3：名著需要新分类，SQLite 不能修改 CHECK 约束，所以按官方步骤重建 `articles`（建新表 → 拷数据 → 删旧表 → 改名），并给 `users` 加资料列。外键改在 `onOpen` 才打开：迁移期间若外键开着，改名会把 `reading_progress` 的外键改指向旧表。

## 5. 离线、幂等与同步

**离线优先**：所有读写都只碰本地 SQLite，网络只用于「下拉拉取新文章」（mock 远端）、同步和埋点上报。离线时顶部出现暖黄提示条，下拉刷新提示「当前离线」，事件和改动在本地排队。

**幂等与杀进程不丢进度**：

- 阅读进度是 UPSERT，`WHERE excluded.updated_at >= updated_at`，晚到的旧写入会被忽略；`max_progress`、`status` 只增不减。
- 阅读会话每 250 ms 采样一次位置，最多每秒写一次库；App 进入后台（`inactive`）立即 flush，所以被系统杀掉也最多丢最后 1 秒。
- 阅读时长按「段」记录，每次写的是该段的绝对累计值（`MAX(old, new)`），重放不会重复累计。
- 种子导入按 `content_version` 只升不降，可重复执行。
- 收藏用 `(user_id, lemma)` 唯一键：重复收藏是空操作，删除后再收藏复用同一行（id 稳定）。

**同步**（`lib/features/sync/`，模拟服务端是一个独立的 SQLite 文件，请求和响应都走 JSON）：

1. 本地写入时把行标为 `dirty=1`。
2. push：带上每行上次看到的服务端版本 `base_version`；服务端版本不一致即为冲突。
3. 服务端按下面的规则合并，返回合并后的记录和新版本号；客户端用同一规则再合并一次（期间本地又有新改动就保持 dirty）。
4. pull：按服务端变更序号游标拉取其他设备的改动并合并。

| 数据 | 冲突规则 |
|---|---|
| 阅读进度 | 按字段合并（可交换，结果与到达顺序无关）：`max_progress`、`status` 取大；`finished_at` 取早；阅读位置（offset、段落锚点、当前进度）跟随最近一次阅读 `last_read_at` |
| 生词、收藏 / 稍后再读 | 整条 last-write-wins（`updated_at`），删除是带时间的墓碑，所以「一边删、一边后来又改」会以后来的修改为准 |

触发时机：启动、每分钟、本地改动后 3 秒（合并连续写入）、回到前台、网络恢复、手动「立即同步」。游客数据不同步；首次登录时把游客数据接管到账号下。「我的 → 同步」页可看待上传数量、最近冲突，并有「模拟另一台设备修改」按钮用于演示。

## 6. 动效清单

手感在真机（三星 S21 Ultra，Android 15，120 Hz）上逐项调过。帧率验证方式：`fvm flutter run --profile` 打开性能叠加层（或 DevTools Performance），观察 UI / Raster 两条曲线不超出帧预算；关键时序（延迟、持续时间、弹跳中间值、只播放一次）在组件测试里逐帧断言，见 `test/features/reader/reader_page_test.dart`、`test/features/articles/article_feed_test.dart` 等。

| # | 动效 | 位置 | 实现 | 关键参数 |
|---|---|---|---|---|
| 1 | 共享元素转场 | 列表卡片 → 阅读页封面 | `Hero` + 自定义 `flightShuttleBuilder`：圆角从 16 插值到 0；封面在宽框里由「方图」连续过渡为「立着的书」 | 直线 `RectTween`；去程 easeOutCubic 420 ms，回程 easeInCubic 350 ms |
| 1 | 手势返回（跟手、可取消回弹） | 所有二级页 | 自写 `SwipeBackPageRoute`：页面任意位置右滑（dx > 2·|dy| 才判定，避免误触滚动）+ Android 预测性返回；松手用临界阻尼弹簧 `SpringSimulation` 从手指速度接续 | 刚度 500、阻尼比 1；超过一半或速度 ≥ 1 屏宽/秒即返回，否则回弹；拖动中曲线改为线性保证页面贴手；下层页面 0.3 视差 |
| 2 | 列表 stagger 渐入 | 首页列表首屏 | 一个 `AnimationController` 驱动前 8 项，各自 `Interval` | 每项错开 40 ms、时长 300 ms、上移 16 px，总 580 ms；之后加载的项不再动画 |
| 2 | 正文首屏淡入位移 | 阅读页 | 等路由转场结束（封面落位）后再淡入 | 延迟 80 ms，280 ms easeOutCubic，上移 12 px；取消的返回手势不会重播 |
| 3 | 进度环 / 进度条平滑推进 | 继续阅读卡、阅读页顶部 3 pt 条、底部胶囊栏、「我的」目标环 | `TweenAnimationBuilder` 从旧值补间到新值；阅读条独立 `RepaintBoundary`，滚动时只重绘这一条 | 进度环 800 ms easeOutCubic；阅读条 250 ms |
| 3 | 读完庆祝 | 阅读页（看过 90% 且读够最短时长） | 页面模糊 + 自绘彩纸（重力抛物线）+ 卡片弹出，附本篇用时、收藏数、下一篇 | 彩纸 40 片 1.6 s、重力 1800 px/s²；卡片 0.85→1 easeOutBack；触感反馈 |
| 4 | 收藏按钮形变弹跳 | 取词面板 | `TweenSequence` 缩放 + 图标描边→实心 + 底色青绿→暖金 | 1 → 0.8（80 ms）→ 1.25（140 ms）→ 1（180 ms），共 400 ms；乐观更新，按下同帧开始 |
| 4 | Tab 指示器滑动 | 首页分类胶囊、底栏悬浮胶囊、各处分段控件 | `AnimatedPositioned` 胶囊底色 | 420 ms easeOutBack（轻微过冲） |
| 4 | 骨架屏 shimmer | 首页加载 | 两层：白底分组在下，占位块 + 渐变扫光在上（扫光只作用于占位块） | 1.2 s 周期；加载 < 120 ms 不显示，一旦显示至少停留 400 ms，避免闪烁 |
| + | 其他 | — | 开屏图标过冲弹入；阅读主题 200 ms 渐变；复习卡片 3D 翻面（450 ms）与甩出；跳回原文时词底暖金闪两次；点赞心形弹性放大 | — |

性能取舍：毛玻璃（`BackdropFilter`）只用在底栏、阅读页悬浮按钮和顶栏这类小面积；进度条和彩纸各自 `RepaintBoundary`；封面图片 ≤ 720 px WebP（单张 < 90 KB），一次解码在 Hero 飞行过程中复用。

## 7. 数据埋点方案

代码：`lib/core/analytics/`；调试面板：「我的 → 埋点调试面板」。

### 7.1 事件模型

- **命名**：snake_case，`对象_动作`（`article_open`、`word_collect`）或度量（`read_duration`、`scroll_depth`）。完整目录与必填/选填参数见 [`event_spec.dart`](lib/core/analytics/event_spec.dart)；debug 包里每次 `track` 都会校验，测试会扫描代码确保所有上报的事件都在目录里。
- **公共参数**（每个事件自动附带）：`event_id`（UUID，去重键）、`ts`、`session_id`、`seq`（会话内序号）、`user_id`、`device_id`（安装级随机 id）、`app_version`、`platform`、`network`（online/offline）。

### 7.2 埋点位置

| 场景 | 事件（必填参数） |
|---|---|
| 打开 App | `app_open`(cold_start_ms)、`session_start`(reason)、`app_background`(foreground_ms) |
| 页面 | `page_view`(page) |
| 列表曝光 | `article_impression`(article_id, surface, position) |
| 分类 / 筛选 | `category_switch`(category)、`level_filter`(level) |
| 搜索 | `search`(query, results)、`search_result_open`(article_id, position) |
| 文章打开 | `article_open`(article_id, surface) |
| 阅读时长与滚动深度 | `read_duration`(article_id, active_ms, max_progress)、`scroll_depth`(article_id, depth=25/50/75/100) |
| 取词 / 收藏 / 发音 / 复习 | `word_lookup`(word, found, article_id)、`word_collect`、`word_delete`、`word_pronounce`、`word_review` |
| 读完 | `article_finish`(article_id) |
| 分享 | `article_share`、`coread_share`、`coread_like` |
| 离线命中 | `offline_hit`(surface) |
| 其他 | `login`、`register`、`logout`、`profile_update`、`reader_settings`、`appearance_set`、`reminder_set`、`sync_run` |

### 7.3 上报链路

```
track() ──立即返回（不阻塞 UI）──▶ 串行写入 event_queue（status=0）
   │
   ├ 触发上报：每 15 s / 待发满 20 条 / 进入后台 / 网络恢复 / 冷启动 3 s 后
   ▼
flush()（单飞，同时只有一个在跑）
   取 ≤ 50 条到期事件 → 标记 sending + batch_id → POST JSON → 写 upload_log
   ├ 200：标记 sent（7 天后清理）
   └ 失败/离线：attempts+1，指数退避 5 s·2^(n-1)（上限 10 min，±20% 抖动），满 8 次标记放弃
冷启动：把上次进程被杀时留在 sending 的批次退回 pending 重发；服务端按 event_id 去重，保证幂等
```

调试面板可以开「模拟上报失败（503）」观察退避重试。

### 7.4 统计口径

- **会话**：冷启动开始；进入后台超过 30 秒再回到前台，开新会话（`session_start(reason=resume, away_ms)`）。
- **阅读时长**：只计「阅读页在前台可见」且「120 秒内有交互（滚动/触摸）」的时间（一屏文字的阅读时间之内），按段累计，不足 3 秒的段不记；离开文章时上报 `read_duration`。
- **读完**：看过正文 90%，且有效时长 ≥ min(30 s, 字数 ÷ 400 词/分)。
- **曝光**：卡片可见面积 ≥ 50% 且持续 ≥ 500 ms；同一会话、同一列表只计一次。
- **滚动深度**：以正文最后一段末尾为 100%（页脚出现不会拉低进度）。

### 7.5 分析查询（SQLite JSON1）与示例输出

调试面板里实时计算这三项（Dart 实现，任何 Android SQLite 都能跑）；等价 SQL 见 [`analytics_report.dart`](lib/core/analytics/analytics_report.dart)，测试会确认 SQL 与 Dart 结果一致。

```sql
-- 近 7 日阅读时长分布
SELECT date(ts / 1000, 'unixepoch', 'localtime') AS day,
       ROUND(SUM(json_extract(params, '$.active_ms')) / 60000.0, 1) AS minutes,
       COUNT(*) AS reads
FROM collected_events
WHERE name = 'read_duration' AND ts >= :since
GROUP BY day ORDER BY day;
```

```
day         minutes  reads
2026-10-22  0.5      1
2026-10-23  3.0      1
```

```sql
-- 文章打开 → 读过半 → 读完 漏斗（按 用户×文章 去重）
WITH opened AS (SELECT DISTINCT user_id, json_extract(params,'$.article_id') a
                FROM collected_events WHERE name='article_open' AND ts >= :since),
     half   AS (SELECT DISTINCT user_id, json_extract(params,'$.article_id') a
                FROM collected_events WHERE name='scroll_depth'
                  AND json_extract(params,'$.depth') >= 50 AND ts >= :since),
     done   AS (SELECT DISTINCT user_id, json_extract(params,'$.article_id') a
                FROM collected_events WHERE name='article_finish' AND ts >= :since)
SELECT (SELECT COUNT(*) FROM opened) opened,
       (SELECT COUNT(*) FROM half JOIN opened USING (user_id, a)) read_half,
       (SELECT COUNT(*) FROM done JOIN opened USING (user_id, a)) finished;
```

```
opened  read_half  finished
3       1          1
```

```sql
-- 各列表曝光与点击
SELECT json_extract(params,'$.surface') surface,
       SUM(name='article_impression') impressions, SUM(name='article_open') opens
FROM collected_events
WHERE name IN ('article_impression','article_open') AND ts >= :since
GROUP BY surface ORDER BY impressions DESC;
```

```
surface  impressions  opens
all      4            2
tech     0            1
```

（示例输出来自 `test/core/analytics/analytics_report_test.dart` 的测试数据。）

## 8. 登录与鉴权（Mock）

- 本地 `users` 表：每个用户随机 16 字节盐，存 `sha256(salt + password)`；内置演示账号 demo / glean123。
- 登录成功生成随机 token（UUID），写入 `sessions(token, user_id, expires_at)`，有效期 7 天；客户端只在 `shared_preferences` 里保存 token。
- 启动时用 token 查 `sessions` 并校验未过期，有效则直接进首页，否则清掉 token 回登录页。退出登录删除会话。
- 真实后端时：哈希与发 token 在服务端完成（如 bcrypt/argon2 + 短期 access token + refresh token），客户端 token 存 Android Keystore / iOS Keychain。

## 9. 打包、签名与上架

```bash
fvm flutter build apk --release          # 直接安装测试
fvm flutter build appbundle --release    # 上架 Google Play（AAB）
```

- **签名**：生成上传密钥（`keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`），在 `android/key.properties` 中引用（不入库），`build.gradle.kts` 的 `release` 配置读取；Play 端启用 Play App Signing，上传密钥丢失可重置。CI 中把 keystore 以 base64 存为 Secret，构建时还原。
- **版本**：`pubspec.yaml` 的 `version: x.y.z+build`，build 号随每次上传递增（可由 CI 的 run number 生成）。
- **上架**：Google Play 内部测试 → 封闭测试 → 正式，填写数据安全表单（本 App 数据只存本机；埋点为匿名设备 id）、隐私政策、内容分级。国内商店（华为/小米/OPPO/vivo）需软著与隐私合规检测，首次启动先展示隐私政策再初始化 SDK。
- **iOS**：`flutter build ipa`，Xcode 配置 Team 与描述文件，通过 App Store Connect 上传，TestFlight 测试后提审。

## 10. 已知缺陷与优化思路

- 同步与埋点的「服务端」都是本机 SQLite 模拟，接口按 JSON 收发以保持边界；换成真实后端只需替换 `MockSyncServer.push/pull` 与 `MockCollector.post`。
- 取词按 `[A-Za-z]+` 切词：`couldn’t` 会被切成 `couldn` + `t`，名著里少数缩写与人名查不到释义（46 个）。可改为基于 ICU 的分词并补充缩写表。
- 全文搜索用 `LIKE` 粗筛 + Dart 排序，几十篇文章足够；内容量上万篇时应改为 FTS（Android 自带 FTS4）。
- 深色模式切换时整棵树重建一次（保留状态），之后的帧正常；若要零重建需把所有颜色改走 `Theme`/`InheritedWidget`。
- 每日提醒用非精确闹钟（无需「精确闹钟」权限），系统可能延后几分钟。
- 共读是本地 mock 内容（引用的原句来自种子文章），没有评论与真实社交关系。
- 只在 Android 真机验证；iOS 未测。
