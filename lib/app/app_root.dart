import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/application/auth.dart';
import '../features/auth/ui/login_page.dart';
import 'home_shell.dart';
import 'providers.dart';

/// Splash on cold start, then the login page or the home shell depending on
/// the session. Signing in or out cross-fades between the two; the shell is
/// keyed by user so every page reloads for the new account.
class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final Widget child;
    if (!_splashDone) {
      child = SplashPage(
        ready: ref.watch(seedReadyProvider),
        onDone: () => setState(() => _splashDone = true),
      );
    } else if (user == null) {
      child = const LoginPage(key: ValueKey('login'));
    } else {
      child = HomeShell(key: ValueKey('home-${user.id}'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Every page fills the screen; the default stack would let the splash
      // shrink to its content and show the dark window around it.
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: child,
    );
  }
}

/// Flutter-side splash on the illustration's cream, which the system splash
/// also shows, so the handoff is invisible: the still life fades in while
/// settling from slightly larger, then the name rises in below it. It stays
/// until the seed import is done, but at least long enough for the
/// animation to finish.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.ready, required this.onDone});

  final Future<void> ready;
  final VoidCallback onDone;

  static const minDuration = Duration(milliseconds: 1600);

  /// The illustration's paper colour (also the native splash background).
  static const cream = Color(0xFFFAF1E2);
  static const green = Color(0xFF24574A);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  static const _art = AssetImage('assets/brand/splash.webp');

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _artIn = _c.drive(
    CurveTween(curve: const Interval(0, 0.6, curve: Curves.easeOutCubic)),
  );
  late final Animation<double> _text = _c.drive(
    CurveTween(curve: const Interval(0.45, 1, curve: Curves.easeOutCubic)),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Start once the picture is decoded, so its fade is never half-skipped
    // while the first frames wait for the image.
    precacheImage(_art, context).whenComplete(() {
      if (mounted) _c.forward();
    });
    _waitThenLeave();
  }

  Future<void> _waitThenLeave() async {
    try {
      await (widget.ready, Future<void>.delayed(SplashPage.minDuration)).wait;
    } catch (_) {
      // A failed seed import still opens the app; lists show their error.
    }
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final art = (size.width * 0.86).clamp(0.0, 440.0);
    // Material gives the texts a proper default style outside a Scaffold.
    return Material(
      color: SplashPage.cream,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _artIn,
            builder: (context, child) => Opacity(
              opacity: _artIn.value,
              child: Transform.scale(
                scale: 1.06 - 0.06 * _artIn.value,
                child: child,
              ),
            ),
            child: Image(
              key: const Key('splash-art'),
              image: _art,
              width: art,
              height: art,
            ),
          ),
          AnimatedBuilder(
            animation: _text,
            builder: (context, child) => Opacity(
              opacity: _text.value,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - _text.value)),
                child: child,
              ),
            ),
            child: const Column(
              children: [
                Text(
                  '拾读',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: SplashPage.green,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'GLEAN · 拾起每一个词',
                  style: TextStyle(
                    fontSize: 14,
                    letterSpacing: 2,
                    color: Color(0xA0473D30),
                  ),
                ),
              ],
            ),
          ),
          // Keeps the group optically centred (the art has empty paper on
          // top, the text sits below).
          SizedBox(height: size.height * 0.06),
        ],
      ),
    );
  }
}
