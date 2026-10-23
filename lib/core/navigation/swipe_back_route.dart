import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Page route whose swipe-back follows the finger and can be cancelled.
///
/// Two inputs drive the same route animation:
///  * an in-app rightward drag anywhere on the page, direction-gated so a
///    diagonal flick while reading still scrolls instead of going back;
///  * Android's system predictive back (the edge swipe), received through
///    [WidgetsBindingObserver] the same way Flutter's own
///    PredictiveBackPageTransitionsBuilder does.
///
/// On release the page settles with a critically damped spring that starts
/// at the finger's velocity, so there is no speed jump between drag and
/// settle. While a gesture is in progress the transition maps the animation
/// linearly, so the page stays under the finger.
class SwipeBackPageRoute<T> extends PageRoute<T> {
  SwipeBackPageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  /// Same thresholds as Flutter's Cupertino back gesture (cupertino/route.dart):
  /// a fling of at least one screen width per second decides by direction,
  /// otherwise the page pops once dragged past halfway.
  static const double minFlingVelocity = 1.0;
  static const double popThreshold = 0.5;

  /// Critically damped (ratio 1): the fastest settle without overshoot. The
  /// route animation is clamped to [0, 1], so an underdamped spring could not
  /// visibly bounce; it would just stop hard at the bound.
  static final SpringDescription spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 500,
  );

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 350);

  /// Also required for gesture-driven Hero flights back to this page.
  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is SwipeBackPageRoute && !nextRoute.fullscreenDialog;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _SwipeBackTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      linear: popGestureInProgress,
      child: _SystemBackListener(
        route: this,
        child: _SwipeBackDetector(route: this, child: child),
      ),
    );
  }

  // In-app drag. Values are fractions of the page width; positive velocity
  // points to the right (towards popping).

  /// The recognizer also reports a cancel for pointers that never became a
  /// drag (e.g. the scroll view won); only a started drag may be ended.
  bool _dragging = false;

  void _dragStart() {
    _dragging = true;
    navigator!.didStartUserGesture();
  }

  void _dragUpdate(double delta) {
    if (_dragging) controller!.value -= delta;
  }

  void _dragEnd(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final bool pop;
    if (!isCurrent) {
      // Something else navigated mid-drag; follow whether we are still here.
      pop = !isActive;
    } else if (velocity.abs() >= minFlingVelocity) {
      pop = velocity > 0;
    } else {
      pop = 1 - controller!.value > popThreshold;
    }
    _settle(pop: pop, velocity: velocity);
  }

  // System predictive back. Start and update keep TransitionRoute's
  // behaviour (controller.value = 1 - progress); commit and cancel replace
  // its fixed-duration animations with the same spring as the in-app drag.

  @override
  void handleCommitBackGesture() => _settle(pop: true, velocity: 0);

  @override
  void handleCancelBackGesture() => _settle(pop: false, velocity: 0);

  void _settle({required bool pop, required double velocity}) {
    final c = controller!;
    // The route animation runs opposite to the finger: dragging right lowers
    // it, so a rightward velocity is a negative animation velocity.
    final simulation = SpringSimulation(
      spring,
      c.value,
      pop ? 0 : 1,
      -velocity,
      snapToEnd: true,
    );
    if (pop) {
      if (isCurrent) navigator!.pop();
      // pop() starts a plain reverse; take it over unless it already ended.
      if (c.isAnimating) c.animateBackWith(simulation);
    } else {
      c.animateWith(simulation);
    }

    // Keep userGestureInProgress (linear mapping, Hero gesture flight) until
    // the page has settled.
    if (c.isAnimating) {
      late final AnimationStatusListener onStatus;
      onStatus = (status) {
        if (status.isAnimating) return;
        c.removeStatusListener(onStatus);
        navigator?.didStopUserGesture();
      };
      c.addStatusListener(onStatus);
    } else {
      navigator?.didStopUserGesture();
    }
  }
}

/// Incoming page slides in from the right over a slightly parallaxed
/// previous page, with a soft edge shadow.
class _SwipeBackTransition extends StatefulWidget {
  const _SwipeBackTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.linear,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;

  /// True while a back gesture is driving the animation.
  final bool linear;
  final Widget child;

  @override
  State<_SwipeBackTransition> createState() => _SwipeBackTransitionState();
}

class _SwipeBackTransitionState extends State<_SwipeBackTransition> {
  static const _parallax = 0.3;

  CurvedAnimation? _incoming;
  CurvedAnimation? _outgoing;

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  @override
  void didUpdateWidget(_SwipeBackTransition old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation ||
        old.secondaryAnimation != widget.secondaryAnimation ||
        old.linear != widget.linear) {
      _dispose();
      _setUp();
    }
  }

  void _setUp() {
    if (widget.linear) return;
    _incoming = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _outgoing = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  void _dispose() {
    _incoming?.dispose();
    _outgoing?.dispose();
    _incoming = _outgoing = null;
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _incoming ?? widget.animation;
    final outgoing = _outgoing ?? widget.secondaryAnimation;
    return SlideTransition(
      position: outgoing.drive(
        Tween(begin: Offset.zero, end: const Offset(-_parallax, 0)),
      ),
      child: SlideTransition(
        position: incoming.drive(
          Tween(begin: const Offset(1, 0), end: Offset.zero),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Listens for in-app back swipes on the whole page.
class _SwipeBackDetector extends StatefulWidget {
  const _SwipeBackDetector({required this.route, required this.child});

  final SwipeBackPageRoute<dynamic> route;
  final Widget child;

  @override
  State<_SwipeBackDetector> createState() => _SwipeBackDetectorState();
}

class _SwipeBackDetectorState extends State<_SwipeBackDetector> {
  late final _DirectionalDragRecognizer _recognizer;

  double get _width => context.size!.width;

  @override
  void initState() {
    super.initState();
    // Block bodies: an arrow body inside a cascade would swallow the next
    // `..` section.
    _recognizer = _DirectionalDragRecognizer(debugOwner: this)
      // Count movement from touch-down, so once the gesture is recognised the
      // page sits exactly under the finger instead of lagging by the slop.
      ..dragStartBehavior = DragStartBehavior.down
      ..onStart = (_) {
        widget.route._dragStart();
      }
      ..onUpdate = (d) {
        widget.route._dragUpdate(d.primaryDelta! / _width);
      }
      ..onEnd = (d) {
        widget.route._dragEnd(d.velocity.pixelsPerSecond.dx / _width);
      }
      ..onCancel = () {
        widget.route._dragEnd(0);
      };
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.route.popGestureEnabled) _recognizer.addPointer(event);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}

/// Horizontal drag that only enters the gesture arena's race when the motion
/// is clearly rightward: dx > [dominance] * |dy|.
///
/// A plain horizontal recognizer wins as soon as |dx| passes the touch slop,
/// so a diagonal flick (say 20 px right, 15 px down) while reading would be
/// taken as "back". With the gate, the vertical scroll wins such flicks.
class _DirectionalDragRecognizer extends HorizontalDragGestureRecognizer {
  _DirectionalDragRecognizer({super.debugOwner});

  static const double dominance = 2;

  Offset _moved = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _moved = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _moved += event.delta;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return super.hasSufficientGlobalDistanceToAccept(
          pointerDeviceKind,
          deviceTouchSlop,
        ) &&
        _moved.dx > dominance * _moved.dy.abs();
  }
}

/// Forwards Android's system predictive back gesture to [route].
class _SystemBackListener extends StatefulWidget {
  const _SystemBackListener({required this.route, required this.child});

  final SwipeBackPageRoute<dynamic> route;
  final Widget child;

  @override
  State<_SystemBackListener> createState() => _SystemBackListenerState();
}

class _SystemBackListenerState extends State<_SystemBackListener>
    with WidgetsBindingObserver {
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = widget.route;
    if (backEvent.isButtonEvent ||
        !route.isCurrent ||
        !route.popGestureEnabled) {
      return false;
    }
    _active = true;
    route.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (_active) {
      widget.route.handleUpdateBackGestureProgress(
        progress: 1 - backEvent.progress,
      );
    }
  }

  @override
  void handleCommitBackGesture() {
    if (!_active) return;
    _active = false;
    widget.route.handleCommitBackGesture();
  }

  @override
  void handleCancelBackGesture() {
    if (!_active) return;
    _active = false;
    widget.route.handleCancelBackGesture();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
