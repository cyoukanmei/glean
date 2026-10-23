import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../../auth/application/auth.dart';
import '../../auth/data/auth_repository.dart';
import '../data/avatar_store.dart';
import 'user_avatar.dart';

/// 编辑资料: avatar (photo or preset), nickname, signature, daily goal.
/// Nothing is written until 保存; leaving discards a newly picked photo.
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  static const goals = [10, 15, 20, 30];

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final AuthUser _user = ref.read(authProvider)!;

  /// Read up front: dispose() must not touch `ref`.
  late final AvatarStore _store;
  late final _name = TextEditingController(text: _user.name);
  late final _bio = TextEditingController(text: _user.bio ?? '');
  late String? _avatar = _user.avatar;
  late int _goal = _user.dailyGoalMinutes;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  /// Avatar change animation: the new picture pops in.
  int _avatarVersion = 0;

  @override
  void initState() {
    super.initState();
    _store = ref.read(avatarStoreProvider);
  }

  @override
  void dispose() {
    // A photo picked but never saved would be left behind.
    if (!_saved && _avatar != _user.avatar) _store.discard(_avatar);
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _setAvatar(String? avatar) {
    // Drop an earlier unsaved pick when it is replaced.
    if (_avatar != _user.avatar) _store.discard(_avatar);
    setState(() {
      _avatar = avatar;
      _avatarVersion++;
    });
  }

  Future<void> _changeAvatar() async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('更换头像'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'gallery'),
            child: const Text('从相册选择'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'preset'),
            child: const Text('选择预设头像'),
          ),
          if (_avatar != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, 'reset'),
              child: const Text('恢复默认'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'gallery':
        try {
          final picked = await _store.pickFromGallery(_user.id);
          if (picked != null && mounted) _setAvatar(picked);
        } catch (e) {
          debugPrint('[profile] pick failed: $e');
          if (mounted) setState(() => _error = '没能读取这张照片，换一张试试');
        }
      case 'preset':
        final i = await showModalBottomSheet<int>(
          context: context,
          showDragHandle: true,
          backgroundColor: GleanColors.sheet,
          builder: (_) =>
              _PresetGrid(selected: UserAvatar.presetIndex(_avatar)),
        );
        if (i != null && mounted) _setAvatar('preset:$i');
      case 'reset':
        _setAvatar(null);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final previous = _user.avatar;
    try {
      await ref
          .read(authProvider.notifier)
          .updateProfile(
            displayName: _name.text,
            avatar: _avatar,
            bio: _bio.text,
            dailyGoalMinutes: _goal,
          );
      _saved = true;
      if (previous != _avatar) {
        await _store.discard(previous);
      }
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('资料已保存')));
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    color: GleanColors.tint,
                    tooltip: '返回',
                  ),
                  const Expanded(
                    child: Text(
                      '编辑资料',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('profile-save'),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const CupertinoActivityIndicator()
                        : Text(
                            '保存',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: GleanColors.tint,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  const SizedBox(height: 16),
                  Center(
                    child: PressableScale(
                      onTap: _changeAvatar,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          TweenAnimationBuilder<double>(
                            key: ValueKey(_avatarVersion),
                            tween: Tween(
                              begin: _avatarVersion == 0 ? 1 : 0.7,
                              end: 1,
                            ),
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeOutBack,
                            builder: (context, s, child) =>
                                Transform.scale(scale: s, child: child),
                            // Flies up from the avatar on 我的.
                            child: Hero(
                              tag: 'me-avatar',
                              child: UserAvatar(
                                key: const Key('profile-avatar'),
                                user: _user,
                                avatar: _avatar,
                                size: 96,
                              ),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: GleanColors.tint,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: GleanColors.background,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.photo_camera_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '点击更换头像',
                      style: TextStyle(fontSize: 13, color: GleanColors.label2),
                    ),
                  ),
                  const _Caption('基本信息'),
                  InsetGroup(
                    children: [
                      _Field(
                        label: '昵称',
                        child: TextField(
                          key: const Key('profile-name'),
                          controller: _name,
                          maxLength: AuthRepository.maxNameLength,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                            isDense: true,
                            hintText: '给自己起个名字',
                          ),
                        ),
                      ),
                      _Field(
                        label: '签名',
                        child: TextField(
                          key: const Key('profile-bio'),
                          controller: _bio,
                          maxLength: AuthRepository.maxBioLength,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                            isDense: true,
                            hintText: '一句话介绍自己',
                          ),
                        ),
                      ),
                      _Field(
                        label: '账号',
                        child: Text(
                          _user.username,
                          style: TextStyle(
                            fontSize: 16,
                            color: GleanColors.label2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const _Caption('每日阅读目标'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: IosSegmented<int>(
                      value: _goal,
                      items: {
                        for (final g in {...EditProfilePage.goals, _goal})
                          g: '$g 分钟',
                      },
                      onChanged: (g) => setState(() => _goal = g),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
                            child: Text(
                              _error!,
                              key: const Key('profile-error'),
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: GleanColors.red,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 7),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: GleanColors.label2),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 16),
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(fontSize: 16)),
          ),
          Expanded(child: child),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _PresetGrid extends StatelessWidget {
  const _PresetGrid({required this.selected});

  final int? selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '选择预设头像',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < avatarPresets.length; i++)
                  PressableScale(
                    key: Key('preset-$i'),
                    onTap: () => Navigator.pop(context, i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i == selected
                              ? GleanColors.tint
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: PresetAvatar(index: i, size: 60),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
