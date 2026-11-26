import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

bool looksLikeCapsLock(String typed) {
  final letters = typed.runes
      .map(String.fromCharCode)
      .where((c) => c.toUpperCase() != c.toLowerCase())
      .toList();
  return letters.length >= 3 && letters.every((c) => c == c.toUpperCase());
}

Future<void> showPasswordSheet(
  BuildContext context, {
  required String user,
  required Future<bool> Function(String password) onSubmit,
  required VoidCallback onChangeUser,
  required VoidCallback onShowReset,
}) {
  final ks = context.ks;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: ks.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SafeArea(
      top: false,
      child: _PasswordSheet(
        user: user,
        onSubmit: onSubmit,
        onChangeUser: onChangeUser,
        onShowReset: onShowReset,
      ),
    ),
  );
}

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({
    required this.user,
    required this.onSubmit,
    required this.onChangeUser,
    required this.onShowReset,
  });

  final String user;
  final Future<bool> Function(String password) onSubmit;
  final VoidCallback onChangeUser;
  final VoidCallback onShowReset;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  int _failedTries = 0;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.onSubmit(_text.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _failedTries++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final wrong = _failedTries > 0;
    final caps = !wrong && looksLikeCapsLock(_text.text);
    final border = wrong
        ? Border.all(color: ks.bad, width: 2)
        : _focus.hasFocus
        ? Border.all(color: ks.ac, width: 2)
        : Border.all(color: ks.line);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ks.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Stack(
            alignment: Alignment.center,
            children: [
              Text('Router password', style: KeystoneType.sheetTitle(ks.tx)),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: ks.mu, size: 20),
                ),
              ),
            ],
          ),
          if (!wrong) ...[
            const SizedBox(height: 2),
            Text(
              'The one you use for LuCI in a browser.',
              textAlign: TextAlign.center,
              style: KeystoneType.body(ks.mu),
            ),
          ],
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: const Cubic(0.25, 1, 0.5, 1),
            decoration: BoxDecoration(
              color: ks.node,
              borderRadius: BorderRadius.circular(16),
              border: border,
            ),
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    autofocus: true,
                    obscureText: _obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _submit(),
                    style: KeystoneType.body(ks.tx).copyWith(fontSize: 17),
                    cursorColor: ks.ac,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 18),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: ks.mu,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          if (caps)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.keyboard_capslock_rounded,
                    size: 18,
                    color: ks.warnTx,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Typing in capitals. Is Caps Lock on?',
                      style: KeystoneType.body(
                        ks.warnTx,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          if (wrong)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: ks.bad,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: "That password didn't work. ",
                                style: KeystoneType.body(
                                  ks.bad,
                                ).copyWith(fontWeight: FontWeight.w500),
                              ),
                              TextSpan(
                                text: 'What you typed is kept.',
                                style: KeystoneType.body(ks.tx2),
                              ),
                            ],
                          ),
                        ),
                        if (_failedTries >= 2)
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Still stuck? ',
                                style: KeystoneType.body(ks.tx2),
                              ),
                              TextButton(
                                onPressed: widget.onShowReset,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(44, 44),
                                ),
                                child: Text(
                                  'How to reset it',
                                  style: KeystoneType.bodyStrong(ks.tx)
                                      .copyWith(
                                        decoration: TextDecoration.underline,
                                        decorationColor: ks.line,
                                      ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'As ', style: KeystoneType.body(ks.mu)),
                    TextSpan(
                      text: widget.user,
                      style: KeystoneType.body(
                        ks.tx2,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: widget.onChangeUser,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(
                  'Change',
                  style: KeystoneType.body(
                    ks.ac,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: ks.tx,
                foregroundColor: ks.bg,
                disabledBackgroundColor: ks.tint,
                disabledForegroundColor: ks.tx2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ks.tx2,
                      ),
                    )
                  : Text('Sign in', style: KeystoneType.bodyStrong(ks.bg)),
            ),
          ),
        ],
      ),
    );
  }
}
