import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/app/providers.dart';
import 'package:glean/core/design/glean_colors.dart';
import 'package:glean/features/reader/application/reader_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(p)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('defaults: 18.5 pt, standard spacing, paper, follow system', () async {
    final s = (await _container({})).read(readerSettingsProvider);
    expect(s.fontSize, ReaderSettings.defaultFontSize);
    expect(s.spacing, LineSpacing.standard);
    expect(s.layoutScale, 1);
    expect(s.effectiveTheme(systemDark: false), ReaderTheme.paper);
    expect(s.effectiveTheme(systemDark: true), ReaderTheme.night);
  });

  test('choices persist; picking a theme stops following the system', () async {
    final c = await _container({});
    c.read(readerSettingsProvider.notifier)
      ..setFontSize(22)
      ..setSpacing(LineSpacing.loose)
      ..setTheme(ReaderTheme.sepia);

    final restored = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
      ],
    );
    addTearDown(restored.dispose);
    final s = restored.read(readerSettingsProvider);
    expect(s.fontSize, 22);
    expect(s.spacing, LineSpacing.loose);
    expect(s.effectiveTheme(systemDark: true), ReaderTheme.sepia);
    expect(s.layoutScale, greaterThan(1));
  });

  test('out-of-range or unknown values fall back', () async {
    final s = (await _container({
      'reader.fontSize': 99.0,
      'reader.theme': 'neon',
    })).read(readerSettingsProvider);
    expect(s.fontSize, ReaderSettings.maxFontSize);
    expect(s.theme, ReaderTheme.paper);
  });
}
