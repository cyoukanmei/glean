import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Window-size classes. The app is laid out for phones; from [wide] up (a
/// desktop browser, a tablet in landscape) the tabs move to a side bar,
/// lists get more columns and text keeps a comfortable line length.
abstract final class Layout {
  /// Window width from which the side bar replaces the tab bar.
  static const wide = 900.0;

  /// Tab pages with grids (书架, 书城).
  static const gridMaxWidth = 1120.0;

  /// Lists, settings and other one-column pages.
  static const pageMaxWidth = 760.0;

  /// The reader's text column (about 70 characters a line).
  static const readingMaxWidth = 720.0;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;

  /// Width of the reader's text column in a window [width] wide: the whole
  /// width on phones and tablets, [readingMaxWidth] in a wide window.
  static double readingWidth(double width) =>
      width >= wide ? readingMaxWidth : width;
}

/// Centres [child] at most [maxWidth] wide. The margins pass the mouse wheel
/// on to the child, so a page scrolls wherever the pointer is, as on the web.
class CenteredColumn extends StatelessWidget {
  const CenteredColumn({
    super.key,
    required this.maxWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // Same tree at every width, so resizing keeps the page's state.
        final width = min(box.maxWidth, maxWidth);
        final margin = (box.maxWidth - width) / 2;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) {
            final x = event.localPosition.dx;
            if (event is! PointerScrollEvent ||
                (x >= margin && x <= margin + width)) {
              return;
            }
            // Re-sent just inside the column's edge, where the scroll view
            // picks it up (after this event's dispatch has finished).
            final inside = x.clamp(margin + 1, margin + width - 1);
            final moved = event.copyWith(
              position: event.position + Offset(inside - x, 0),
            );
            scheduleMicrotask(
              () => GestureBinding.instance.handlePointerEvent(moved),
            );
          },
          child: Center(
            child: SizedBox(width: width, child: child),
          ),
        );
      },
    );
  }
}
