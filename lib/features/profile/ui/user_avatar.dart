import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../auth/data/auth_repository.dart';

/// Built-in avatars: an emoji on a gradient.
const avatarPresets = [
  ('📚', [Color(0xFF99F6E4), GleanColors.tint]),
  ('🦉', [Color(0xFFFDE68A), Color(0xFFD97706)]),
  ('🌿', [Color(0xFFBBF7D0), Color(0xFF15803D)]),
  ('🍵', [Color(0xFFFED7AA), Color(0xFFC2410C)]),
  ('🐱', [Color(0xFFFBCFE8), Color(0xFFDB2777)]),
  ('🌙', [Color(0xFFC7D2FE), Color(0xFF4338CA)]),
  ('☕', [Color(0xFFE7D7C9), Color(0xFF7C5A3C)]),
  ('🦊', [Color(0xFFFECACA), Color(0xFFB91C1C)]),
];

/// The user's avatar: their photo, a preset, or the first letter of their
/// name. [avatar] overrides the user's saved one (used while editing).
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.avatar,
    this.size = 36,
  });

  final AuthUser? user;
  final String? avatar;
  final double size;

  static int? presetIndex(String? avatar) {
    if (avatar == null || !avatar.startsWith('preset:')) return null;
    final i = int.tryParse(avatar.substring(7));
    return i != null && i >= 0 && i < avatarPresets.length ? i : null;
  }

  @override
  Widget build(BuildContext context) {
    final value = avatar ?? user?.avatar;
    if (value != null && value.startsWith('file:')) {
      return ClipOval(
        child: Image.file(
          File(value.substring(5)),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _initial(),
        ),
      );
    }
    if (presetIndex(value) case final i?) {
      return PresetAvatar(index: i, size: size);
    }
    return _initial();
  }

  Widget _initial() => InitialAvatar(
    initial: (user?.name ?? '读').characters.first.toUpperCase(),
    size: size,
  );
}

class PresetAvatar extends StatelessWidget {
  const PresetAvatar({super.key, required this.index, this.size = 36});

  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (emoji, colors) = avatarPresets[index];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.5, height: 1)),
    );
  }
}
