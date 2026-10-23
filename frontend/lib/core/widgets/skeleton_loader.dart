import 'package:flutter/material.dart';

/// A shimmering skeleton placeholder widget that mimics modern product/card loading states.
class ShimmerLoadingCard extends StatefulWidget {
  final bool isList;
  const ShimmerLoadingCard({super.key, this.isList = false});

  @override
  State<ShimmerLoadingCard> createState() => _ShimmerLoadingCardState();
}

class _ShimmerLoadingCardState extends State<ShimmerLoadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _animation = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final highlightColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final gradient = LinearGradient(
          begin: Alignment(_animation.value - 1, 0),
          end: Alignment(_animation.value + 1, 0),
          colors: [baseColor, highlightColor, baseColor],
          stops: const [0.1, 0.5, 0.9],
        );

        if (widget.isList) {
          return Container(
            height: 110,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                // Image skeleton
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: gradient,
                  ),
                ),
                const SizedBox(width: 14),
                // Text skeletons
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 14,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: gradient,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: gradient,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            height: 18,
                            width: 70,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: gradient,
                            ),
                          ),
                          Container(
                            height: 12,
                            width: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: gradient,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Grid skeleton
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image placeholder
              Expanded(
                flex: 9,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    gradient: gradient,
                  ),
                ),
              ),
              // Content placeholder
              Expanded(
                flex: 11,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 14,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: gradient,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 11,
                            width: 170,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: gradient,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 10,
                            width: 110,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: gradient,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: gradient,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                height: 10,
                                width: 80,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  gradient: gradient,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            height: 18,
                            width: 65,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: gradient,
                            ),
                          ),
                          Container(
                            height: 10,
                            width: 50,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: gradient,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A responsive grid of skeleton cards for initial loading states.
class SkeletonGrid extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;

  const SkeletonGrid({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth > 1150
            ? 4
            : constraints.maxWidth > 750
                ? 3
                : constraints.maxWidth > 500
                    ? 2
                    : 1;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            childAspectRatio: count == 1 ? 1.05 : 0.72,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) => const ShimmerLoadingCard(isList: false),
        );
      },
    );
  }
}

/// A list of skeleton cards for initial loading states in list view mode.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  const SkeletonList({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      itemBuilder: (context, index) => const ShimmerLoadingCard(isList: true),
    );
  }
}
