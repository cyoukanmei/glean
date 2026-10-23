/// Milliseconds since epoch. Injected into repositories so tests can control
/// time and ordering of writes.
typedef Clock = int Function();

int systemClock() => DateTime.now().millisecondsSinceEpoch;
