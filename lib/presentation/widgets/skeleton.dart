/// Lightweight loading placeholders.
///
/// Deliberately dependency-free (no shimmer package): a single repeating
/// opacity pulse driven by one animation controller per visible skeleton
/// tree. Skeleton blocks are [ExcludeSemantics] so screen readers announce
/// "loading" once (via the surrounding [Semantics]) instead of reading out
/// anonymous gray rectangles.
library;

import 'package:flutter/material.dart';

/// Pulses its child's opacity while it represents loading content.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 1.0, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

/// One gray rounded block; pass [height] or wrap in [Expanded]/[Flexible].
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({super.key, this.width, this.height, this.radius = 10});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// A standard list-row skeleton: square thumbnail + two text lines.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SkeletonBlock(width: 56, height: 56, radius: 12),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBlock(height: 16, radius: 6),
              SizedBox(height: 10),
              SkeletonBlock(height: 12, radius: 6),
            ],
          ),
        ),
      ],
    );
  }
}

/// A product-card skeleton matching [ProductCard]'s layout: square image,
/// two title lines, rating + price rows.
class SkeletonProductCard extends StatelessWidget {
  const SkeletonProductCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: SkeletonBlock(radius: 0)),
        SizedBox(height: 12),
        SkeletonBlock(height: 14, radius: 6),
        SizedBox(height: 8),
        SkeletonBlock(height: 14, radius: 6),
        SizedBox(height: 10),
        Row(
          children: [
            SkeletonBlock(width: 40, height: 12, radius: 6),
            SizedBox(width: 8),
            SkeletonBlock(width: 56, height: 12, radius: 6),
          ],
        ),
      ],
    );
  }
}

/// Wraps a skeleton area with a single polite live-region announcement, so
/// assistive technology hears "Loading" instead of silence.
class SkeletonAnnouncer extends StatelessWidget {
  const SkeletonAnnouncer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(label: 'Loading', liveRegion: true, child: child);
  }
}
