// Frame-time evidence on a real device, in profile mode:
//
//   fvm flutter drive --profile --driver=test_driver/perf_driver.dart \
//     --target=integration_test/perf_test.dart -d <device>
//
// flutter drive may uninstall the app before installing the profile build,
// which clears its local data: use a test device. The test signs in with the
// demo account if needed, drives the motion-heavy paths (tabs, 书城 feed,
// card -> reader transition with swipe-back, 书架 grid) and writes
// build/perf_summary.json:
// for each scenario the engine's frame timings (FrameMonitor) against the
// display's real budget (8.3 ms on a 120 Hz panel) and against the usual
// 16.7 ms. (binding.watchPerformance also wants a VM timeline, which is not
// available over wireless adb, so the timings are collected directly.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/perf/frame_monitor.dart';
import 'package:glean/features/articles/ui/article_card.dart';
import 'package:glean/main.dart' as app;
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> idle(WidgetTester tester, [int ms = 600]) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 150 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(f, findsWidgets);
  }

  /// Runs [action] and stores its frame statistics under [key].
  Future<void> measure(
    String key,
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    FrameMonitor.instance.reset();
    await action();
    // The engine reports frame timings in batches, about once a second.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final samples = FrameMonitor.instance.samples;
    (binding.reportData ??= {})[key] = {
      'display': FrameStats.of(samples, hz: FrameMonitor.refreshRate).toJson(),
      'budget_16ms': FrameStats.of(samples, hz: 60).toJson(),
    };
  }

  testWidgets('frame timings of scrolling, transitions and tabs', (
    tester,
  ) async {
    app.main();
    final login = find.byKey(const Key('login-submit'));
    final home = find.byKey(const Key('shelf-search'));
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (login.evaluate().isNotEmpty || home.evaluate().isNotEmpty) break;
    }
    if (login.evaluate().isNotEmpty) {
      await tester.tap(find.textContaining('演示账号'));
      await tester.pump();
      await tester.tap(login);
    }
    await waitFor(tester, home);
    await idle(tester, 1500);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;

    await measure('tab_switch', tester, () async {
      for (var round = 0; round < 2; round++) {
        for (final tab in ['书城', '社区', '单词本', '我的', '书架']) {
          await tester.tap(find.text(tab).last);
          await idle(tester, 700);
        }
      }
    });

    await tester.tap(find.text('书城').last);
    await idle(tester, 1500);
    Finder feed() => find.byType(CustomScrollView).first;
    await measure('store_feed_scroll', tester, () async {
      for (var i = 0; i < 4; i++) {
        await tester.fling(feed(), const Offset(0, -800), 3000);
        await idle(tester, 1000);
      }
      for (var i = 0; i < 4; i++) {
        await tester.fling(feed(), const Offset(0, 800), 3000);
        await idle(tester, 1000);
      }
    });

    // Bring the first article cards on screen, under the banner and ranking.
    await tester.drag(feed(), Offset(0, -size.height * 0.75));
    await idle(tester, 800);
    await measure('open_and_swipe_back', tester, () async {
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byType(ArticleCard).at(i));
        await idle(tester, 1200);
        if (i == 0) {
          // A short drag that is let go: the page springs back.
          await tester.timedDragFrom(
            Offset(24, size.height / 2),
            Offset(size.width * 0.25, 0),
            const Duration(milliseconds: 400),
          );
          await idle(tester, 800);
        }
        await tester.timedDragFrom(
          Offset(24, size.height / 2),
          Offset(size.width * 0.75, 0),
          const Duration(milliseconds: 350),
        );
        await idle(tester, 1000);
      }
    });

    // The shelf now holds at least the books just opened.
    await tester.tap(find.text('书架').last);
    await idle(tester, 1200);
    await measure('shelf_grid_scroll', tester, () async {
      for (var i = 0; i < 3; i++) {
        await tester.fling(feed(), const Offset(0, -700), 2500);
        await idle(tester, 900);
      }
      for (var i = 0; i < 3; i++) {
        await tester.fling(feed(), const Offset(0, 700), 2500);
        await idle(tester, 900);
      }
    });
  });
}
