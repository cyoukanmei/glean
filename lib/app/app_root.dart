import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/glean_colors.dart';
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
      child: child,
    );
  }
}

/// Flutter-side splash, picking up from the system one (same background,
/// icon in the middle): the icon pops in with a slight overshoot, the name
/// rises in 350 ms later. It stays until the seed import is done, but at
/// least long enough for the animation to finish.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.ready, required this.onDone});

  final Future<void> ready;
  final VoidCallback onDone;

  static const minDuration = Duration(milliseconds: 1200);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  late final Animation<double> _icon = _c.drive(
    CurveTween(curve: const Interval(0, 0.75, curve: Curves.easeOutBack)),
  );
  late final Animation<double> _text = _c.drive(
    CurveTween(curve: const Interval(0.4, 1, curve: Curves.easeOutCubic)),
  );

  @override
  void initState() {
    super.initState();
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
    // Material gives the texts a proper default style outside a Scaffold.
    return Material(
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.6, end: 1.0).animate(_icon),
            child: FadeTransition(
              opacity: _c.drive(CurveTween(curve: const Interval(0, 0.3))),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x8C0F766E),
                      blurRadius: 36,
                      offset: Offset(0, 18),
                      spreadRadius: -12,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/brand/app-icon.png',
                    width: 104,
                    height: 104,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          AnimatedBuilder(
            animation: _text,
            builder: (context, child) => Opacity(
              opacity: _text.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - _text.value)),
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
                    letterSpacing: 2,
                    color: GleanColors.label,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'GLEAN · 拾起每一个词',
                  style: TextStyle(
                    fontSize: 15,
                    letterSpacing: 1.2,
                    color: GleanColors.label2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
