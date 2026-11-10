import 'package:flutter/material.dart';

/// The Herdr app's highlight colour (sheprd's sidebar, `#a78bfa`).
const hcHighlightColor = Color(0xFFA78BFA);

/// An agent row the user highlighted in the Herdr app (CON-137): a violet
/// bar on its left and a light tint, as the app's sidebar draws it. Only a
/// look; [child] keeps its own taps.
class HcHighlight extends StatelessWidget {
  const HcHighlight({
    required this.highlighted,
    required this.child,
    this.radius = 8,
    super.key,
  });

  final bool highlighted;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (!highlighted) return child;
    return Material(
      key: const ValueKey('hc-highlight'),
      // The app's tint: the colour at 0x1a (about 10%).
      color: hcHighlightColor.withAlpha(0x1a),
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          child,
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: SizedBox(
              width: 2.5,
              child: ColoredBox(color: hcHighlightColor),
            ),
          ),
        ],
      ),
    );
  }
}
