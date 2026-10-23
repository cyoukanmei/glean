import 'package:glean/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(p)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('defaults to all levels', () async {
    final c = await _container({});
    expect(c.read(levelFilterProvider), {1, 2, 3});
  });

  test('toggling persists and is restored on next launch', () async {
    final c = await _container({});
    c.read(levelFilterProvider.notifier).toggle(2);
    expect(c.read(levelFilterProvider), {1, 3});

    final prefs = await SharedPreferences.getInstance();
    final restored = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(restored.dispose);
    expect(restored.read(levelFilterProvider), {1, 3});
  });

  test('the last selected level cannot be turned off', () async {
    final c = await _container({
      'feed.levels': ['3'],
    });
    c.read(levelFilterProvider.notifier).toggle(3);
    expect(c.read(levelFilterProvider), {3});
  });

  test('garbage in prefs falls back to all levels', () async {
    final c = await _container({
      'feed.levels': ['x', '9'],
    });
    expect(c.read(levelFilterProvider), {1, 2, 3});
  });

  test('select keeps one level, null restores all', () async {
    final c = await _container({});
    c.read(levelFilterProvider.notifier).select(2);
    expect(c.read(levelFilterProvider), {2});
    c.read(levelFilterProvider.notifier).select(null);
    expect(c.read(levelFilterProvider), {1, 2, 3});
  });
}
