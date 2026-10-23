import 'package:flutter/material.dart';

/// Thin strip that slides open when the device goes offline and closes when
/// it comes back, so the switch to local-only content is visible but quiet.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: offline
          ? Material(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 18,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '离线模式 · 正在显示本地内容',
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
