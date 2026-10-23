import 'package:flutter/material.dart';

/// A square photo carousel with dot indicators and arrow navigation.
/// Shows [BoxFit.contain] so the full image is always visible regardless of
/// its aspect ratio. Falls back to a placeholder when [imageUrls] is empty.
class PhotoCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final double size;
  final String? heroTag;

  const PhotoCarousel({
    super.key,
    required this.imageUrls,
    this.size = 300,
    this.heroTag,
  });

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Colors.transparent;
    final dotIndicatorColor = isDark ? Colors.white : const Color.fromARGB(255, 59, 61, 64);

    if (widget.imageUrls.isEmpty) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Container(
          color: bgColor,
          child: Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey[400]),
        ),
      );
    }

    final count = widget.imageUrls.length;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: [
          // Page view
          PageView.builder(
            controller: _pageController,
            itemCount: count,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, i) {
              Widget img = Image.network(
                widget.imageUrls[i],
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: Colors.grey[400],
                ),
              );

              if (i == 0 && widget.heroTag != null) {
                img = Hero(
                  tag: widget.heroTag!,
                  child: img,
                );
              }

              return Container(
                color: bgColor,
                child: img,
              );
            },
          ),

          // Left arrow
          if (count > 1 && _currentPage > 0)
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(
                  icon: Icons.chevron_left,
                  onTap: () => _goTo(_currentPage - 1),
                ),
              ),
            ),

          // Right arrow
          if (count > 1 && _currentPage < count - 1)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(
                  icon: Icons.chevron_right,
                  onTap: () => _goTo(_currentPage + 1),
                ),
              ),
            ),

          // Dot indicators
          if (count > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(count, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _currentPage ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == _currentPage
                          ? dotIndicatorColor
                          : dotIndicatorColor.withValues(alpha: 0.5),
                    ),
                  );
                }),
              ),
            ),

          // Photo count badge (top-right)
          if (count > 1)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_currentPage + 1} / $count',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
