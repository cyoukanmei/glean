import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_tab.dart';

/// System back (the edge swipe) on the home tabs. Flutter would finish the
/// activity, which feels like the app was killed: reopening shows the
/// splash again. Instead back returns to 书架 first, then asks for a second
/// swipe within [window], and then only sends the app to the background.
class HomeBackGuard extends ConsumerStatefulWidget {
  const HomeBackGuard({super.key, required this.child, this.exit});

  final Widget child;

  /// Leaves the app; defaults to moving the task to the background.
  final Future<void> Function()? exit;

  static const window = Duration(seconds: 2);
  static const _channel = MethodChannel('glean/app');

  @override
  ConsumerState<HomeBackGuard> createState() => _HomeBackGuardState();
}

class _HomeBackGuardState extends ConsumerState<HomeBackGuard> {
  DateTime? _armedAt;

  Future<void> _onBack() async {
    final tabs = ref.read(homeTabProvider.notifier);
    if (ref.read(homeTabProvider) != HomeTab.shelf) {
      tabs.go(HomeTab.shelf);
      return;
    }
    final now = clock.now();
    if (_armedAt case final at?
        when now.difference(at) < HomeBackGuard.window) {
      _armedAt = null;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await (widget.exit ?? _toBackground)();
      return;
    }
    _armedAt = now;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('再滑一次退出拾读'),
          duration: HomeBackGuard.window,
        ),
      );
  }

  static Future<void> _toBackground() async {
    try {
      await HomeBackGuard._channel.invokeMethod<bool>('moveTaskToBack');
    } on MissingPluginException {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: widget.child,
    );
  }
}
