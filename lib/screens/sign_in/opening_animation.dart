import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/keystone_mark.dart';

class OpeningAnimation extends StatefulWidget {
  const OpeningAnimation({super.key, this.onHoldDone});

  final VoidCallback? onHoldDone;

  @override
  State<OpeningAnimation> createState() => _OpeningAnimationState();
}

class _OpeningAnimationState extends State<OpeningAnimation>
    with SingleTickerProviderStateMixin {
  static const _total = 1500.0;
  static const _ease = Cubic(0.25, 1, 0.5, 1);

  late final AnimationController _c =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onHoldDone?.call();
      });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (MediaQuery.of(context).disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _c.value = 1);
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _part(double fromMs, double toMs) {
    final t = ((_c.value * _total - fromMs) / (toMs - fromMs)).clamp(0.0, 1.0);
    return _ease.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    const ks = KeystoneColors.dark;
    return Scaffold(
      backgroundColor: ks.bg,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final words = _part(350, 550);
          final shineT = (_c.value * _total - 600) / 400;
          return Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Hero(
                      tag: 'keystone-mark',
                      child: KeystoneMark(
                        width: 120,
                        settle: _part(0, 250),
                        keyDrop: _part(250, 450),
                        shine: shineT >= 0 && shineT <= 1 ? shineT : -1,
                        stoneColor: const Color(0xFFA9AEB6),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Opacity(
                      opacity: words,
                      child: Transform.translate(
                        offset: Offset(0, (1 - words) * 6),
                        child: Text(
                          'Keystone',
                          style: KeystoneType.sheetTitle(
                            const Color(0xFFD3D6DB),
                          ).copyWith(fontSize: 24),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 44,
                child: Opacity(
                  opacity: words,
                  child: Text(
                    'by perz3us',
                    textAlign: TextAlign.center,
                    style: KeystoneType.secondary(ks.mu),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
