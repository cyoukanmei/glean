/// Database schema history.
///
/// A fresh install runs [schemaV1] and then every entry in [migrations], so a
/// new database and an upgraded one always go through the same statements.
library;

const int kSchemaVersion = 3;

const List<String> schemaV1 = [
  '''
  CREATE TABLE app_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )''',
  '''
  CREATE TABLE users (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    salt TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE sessions (
    token TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE articles (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    summary TEXT,
    cover TEXT,
    category TEXT NOT NULL
      CHECK (category IN ('tech', 'business', 'culture', 'daily')),
    level INTEGER NOT NULL CHECK (level BETWEEN 1 AND 3),
    body TEXT NOT NULL, -- JSON array of paragraphs
    word_count INTEGER NOT NULL,
    published_at INTEGER NOT NULL,
    content_version INTEGER NOT NULL DEFAULT 1
  )''',
  // Category/level filter plus keyset pagination on (published_at, id).
  'CREATE INDEX idx_articles_feed '
      'ON articles(category, level, published_at DESC, id DESC)',
  '''
  CREATE TABLE reading_progress (
    user_id TEXT NOT NULL,
    article_id TEXT NOT NULL REFERENCES articles(id),
    scroll_offset REAL NOT NULL DEFAULT 0,
    anchor_para INTEGER NOT NULL DEFAULT 0,
    anchor_delta REAL NOT NULL DEFAULT 0,
    font_scale REAL NOT NULL DEFAULT 1,
    progress REAL NOT NULL DEFAULT 0,
    max_progress REAL NOT NULL DEFAULT 0,
    status INTEGER NOT NULL DEFAULT 0, -- 0 unread, 1 reading, 2 finished
    finished_at INTEGER,
    last_read_at INTEGER NOT NULL,
    version INTEGER NOT NULL DEFAULT 0,
    dirty INTEGER NOT NULL DEFAULT 1,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, article_id)
  ) WITHOUT ROWID''',
  'CREATE INDEX idx_progress_recent '
      'ON reading_progress(user_id, last_read_at DESC)',
  '''
  CREATE TABLE reading_segments (
    segment_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    article_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    started_at INTEGER NOT NULL,
    active_ms INTEGER NOT NULL,
    local_day TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )''',
  'CREATE INDEX idx_seg_article ON reading_segments(user_id, article_id)',
  'CREATE INDEX idx_seg_day ON reading_segments(user_id, local_day)',
  '''
  CREATE TABLE dict (
    word TEXT PRIMARY KEY,
    phonetic TEXT,
    definition TEXT NOT NULL
  ) WITHOUT ROWID''',
  // Inflected form -> dictionary headword, e.g. "running" -> "run".
  '''
  CREATE TABLE word_forms (
    form TEXT PRIMARY KEY,
    lemma TEXT NOT NULL
  ) WITHOUT ROWID''',
  '''
  CREATE TABLE vocab (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    word TEXT NOT NULL,
    lemma TEXT NOT NULL,
    definition TEXT NOT NULL,
    article_id TEXT NOT NULL,
    para_index INTEGER NOT NULL,
    char_start INTEGER NOT NULL,
    char_end INTEGER NOT NULL,
    sentence TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    version INTEGER NOT NULL DEFAULT 0,
    dirty INTEGER NOT NULL DEFAULT 1
  )''',
  // One row per (user, lemma): collecting twice is a no-op, collecting after
  // a delete revives the same row.
  'CREATE UNIQUE INDEX ux_vocab_user_lemma ON vocab(user_id, lemma)',
  'CREATE INDEX idx_vocab_list ON vocab(user_id, deleted_at, created_at DESC)',
  '''
  CREATE TABLE event_queue (
    event_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    ts INTEGER NOT NULL,
    session_id TEXT NOT NULL,
    seq INTEGER NOT NULL,
    user_id TEXT,
    params TEXT NOT NULL,
    status INTEGER NOT NULL DEFAULT 0, -- 0 pending, 1 sending, 2 sent, 3 dead
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at INTEGER NOT NULL DEFAULT 0,
    batch_id TEXT,
    created_at INTEGER NOT NULL
  )''',
  'CREATE INDEX idx_eq_pick ON event_queue(status, next_attempt_at, ts)',
  // Stands in for the analytics warehouse; event_id dedupes retried uploads.
  '''
  CREATE TABLE collected_events (
    event_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    ts INTEGER NOT NULL,
    session_id TEXT NOT NULL,
    user_id TEXT,
    params TEXT NOT NULL,
    received_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE upload_log (
    batch_id TEXT PRIMARY KEY,
    sent_at INTEGER NOT NULL,
    count INTEGER NOT NULL,
    http_status INTEGER,
    error TEXT,
    duration_ms INTEGER
  )''',
];

/// Statements that move the schema from version `key - 1` to `key`.
const Map<int, List<String>> migrations = {
  // v2: vocabulary learning status (0 new .. 3 known).
  2: ['ALTER TABLE vocab ADD COLUMN status INTEGER NOT NULL DEFAULT 0'],
  // v3: classic novels (new category + author) and editable profiles.
  //
  // SQLite cannot change a CHECK constraint in place, so articles is rebuilt
  // the documented way: copy into a new table, drop the old one, rename.
  // Foreign keys are only switched on after migrations (AppDatabase.onOpen),
  // so reading_progress's REFERENCES articles(id) simply resolves to the new
  // table.
  3: [
    '''
  CREATE TABLE articles_new (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    summary TEXT,
    cover TEXT,
    category TEXT NOT NULL
      CHECK (category IN ('tech', 'business', 'culture', 'daily', 'classic')),
    level INTEGER NOT NULL CHECK (level BETWEEN 1 AND 3),
    body TEXT NOT NULL, -- JSON array of paragraphs
    word_count INTEGER NOT NULL,
    published_at INTEGER NOT NULL,
    content_version INTEGER NOT NULL DEFAULT 1,
    author TEXT
  )''',
    'INSERT INTO articles_new (id, title, summary, cover, category, level, '
        'body, word_count, published_at, content_version) '
        'SELECT id, title, summary, cover, category, level, body, word_count, '
        'published_at, content_version FROM articles',
    'DROP TABLE articles',
    'ALTER TABLE articles_new RENAME TO articles',
    'CREATE INDEX idx_articles_feed '
        'ON articles(category, level, published_at DESC, id DESC)',
    'ALTER TABLE users ADD COLUMN display_name TEXT',
    'ALTER TABLE users ADD COLUMN avatar TEXT',
    'ALTER TABLE users ADD COLUMN bio TEXT',
    'ALTER TABLE users ADD COLUMN daily_goal_min INTEGER NOT NULL DEFAULT 15',
  ],
};
