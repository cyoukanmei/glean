import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/glean_colors.dart';
import '../../../core/design/ios_widgets.dart';
import '../application/auth.dart';
import '../data/auth_repository.dart';

/// Sign in / sign up against the local mock backend. Errors appear under
/// the fields with a short shake instead of a dialog.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final auth = ref.read(authProvider.notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _signUp
          ? await auth.register(_username.text, _password.text)
          : await auth.login(_username.text, _password.text);
    } on AuthException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _error = e.message);
      _shake.forward(from: 0);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillDemo() {
    _username.text = AuthRepository.demoUsername;
    _password.text = AuthRepository.demoPassword;
    setState(() {
      _signUp = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 48, bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/brand/app-icon.png',
                      width: 64,
                      height: 64,
                    ),
                  ),
                  const SizedBox(height: 22),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _signUp ? '创建账号' : '欢迎回来',
                      key: ValueKey(_signUp),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '登录后，阅读进度和生词本会保存在这台设备上，断网也能继续读。',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: GleanColors.label2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  10 * sin(_shake.value * pi * 4) * (1 - _shake.value),
                  0,
                ),
                child: child,
              ),
              child: InsetGroup(
                children: [
                  _Field(
                    key: const Key('login-username'),
                    icon: Icons.person_outline_rounded,
                    label: '账号',
                    hint: _signUp ? '3–20 位字母或数字' : 'demo',
                    controller: _username,
                    action: TextInputAction.next,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  _Field(
                    key: const Key('login-password'),
                    icon: Icons.lock_outline_rounded,
                    label: '密码',
                    hint: _signUp ? '至少 6 位' : '••••••••',
                    controller: _password,
                    focusNode: _passwordFocus,
                    obscure: true,
                    action: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                      child: Text(
                        _error!,
                        key: const Key('login-error'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: GleanColors.red,
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: FilledButton(
                key: const Key('login-submit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : Text(_signUp ? '注册并登录' : '登录'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _signUp = !_signUp;
                        _error = null;
                      }),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: GleanColors.tint,
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(_signUp ? '已有账号，去登录' : '注册新账号'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: PressableScale(
                onTap: _fillDemo,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: GleanColors.mintSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: GleanColors.tint,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '演示账号 demo / glean123（点此填入）· 本地校验，'
                          '登录状态 7 天有效',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: GleanColors.tint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.icon,
    required this.label,
    required this.hint,
    required this.controller,
    required this.action,
    required this.onSubmitted,
    this.focusNode,
    this.obscure = false,
  });

  final IconData icon;
  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool obscure;
  final TextInputAction action;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(icon, size: 20, color: GleanColors.label2),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            child: Text(label, style: const TextStyle(fontSize: 17)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscure,
              autocorrect: false,
              enableSuggestions: !obscure,
              textInputAction: action,
              onSubmitted: onSubmitted,
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: GleanColors.label3),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}
