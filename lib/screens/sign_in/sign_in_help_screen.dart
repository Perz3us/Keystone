import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

class SignInHelpScreen extends StatefulWidget {
  const SignInHelpScreen({
    super.key,
    required this.routerLabel,
    required this.address,
    this.openReset = false,
  });

  final String routerLabel;
  final String address;

  final bool openReset;

  @override
  State<SignInHelpScreen> createState() => _SignInHelpScreenState();
}

class _SignInHelpScreenState extends State<SignInHelpScreen> {
  late int? _open = widget.openReset ? 1 : null;

  Future<void> _openLuci() => launchUrl(
    Uri.parse('http://${widget.address}/cgi-bin/luci'),
    mode: LaunchMode.externalApplication,
  );

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final body = KeystoneType.body(ks.tx2);
    final items = <(String, Widget)>[
      (
        "Keystone can't find my router",
        Text(
          "Check this phone is on the router's Wi-Fi, not mobile data, "
          "and that the router's lights are on.",
          style: body,
        ),
      ),
      (
        "I don't know the password",
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'If you never set one, leave it empty and tap Sign in.',
              style: body,
            ),
            const SizedBox(height: 10),
            for (final (i, step) in const [
              'Keep the router switched on.',
              'Press and hold the reset button on the back for about '
                  '10 seconds, until the lights flash.',
              'Wait 2 to 3 minutes for it to restart, then Connect with '
                  'no password.',
            ].indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 20, child: Text('${i + 1}.', style: body)),
                    Expanded(child: Text(step, style: body)),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'This erases all its settings, including your Wi-Fi name and '
              'password.',
              style: body.copyWith(
                color: ks.warnTx,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      (
        'Which address should I use?',
        Text(
          'Usually 192.168.1.1. If yours is different, use Other router to '
          'enter it.',
          style: body,
        ),
      ),
      (
        'What can Keystone change?',
        Text(
          'It signs in the same way LuCI does. Nothing changes until you '
          'choose it.',
          style: body,
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 100,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.chevron_left_rounded, color: ks.tx),
          label: Text('Back', style: KeystoneType.body(ks.tx)),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  Text('Help connecting', style: KeystoneType.title(ks.tx)),
                  const SizedBox(height: 6),
                  Text(
                    'For an ${widget.routerLabel} at ${widget.address}',
                    style: KeystoneType.body(ks.mu),
                  ),
                  const SizedBox(height: 14),
                  for (final (i, (q, a)) in items.indexed)
                    _Row(
                      question: q,
                      answer: a,
                      open: _open == i,
                      last: i == items.length - 1,
                      onTap: () =>
                          setState(() => _open = _open == i ? null : i),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _openLuci,
                  style: FilledButton.styleFrom(
                    backgroundColor: ks.tint,
                    foregroundColor: ks.tx,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Open LuCI in a browser',
                    style: KeystoneType.bodyStrong(ks.tx),
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

class _Row extends StatelessWidget {
  const _Row({
    required this.question,
    required this.answer,
    required this.open,
    required this.last,
    required this.onTap,
  });

  final String question;
  final Widget answer;
  final bool open;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final side = BorderSide(color: ks.line);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: side, bottom: last ? side : BorderSide.none),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        question,
                        style: KeystoneType.body(
                          ks.tx,
                        ).copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: const Cubic(0.25, 1, 0.5, 1),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: ks.mu,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Padding(padding: const EdgeInsets.only(bottom: 16), child: answer),
        ],
      ),
    );
  }
}
