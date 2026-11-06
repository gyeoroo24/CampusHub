import 'package:flutter/material.dart';

/// An intentional, aesthetic placeholder displayed when a post has no photos attached,
/// distinguishing intentional photo absence from network/load errors.
class NoPhotoPlaceholder extends StatelessWidget {
  /// When true, renders a concise thumbnail layout suitable for list tiles.
  final bool compact;

  /// Optional custom message (defaults to 'No photos attached' or 'No photo').
  final String? message;

  /// Optional icon size override.
  final double? iconSize;

  const NoPhotoPlaceholder({
    super.key,
    this.compact = false,
    this.message,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
          );

    final iconColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
    final textColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final subtextColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = compact || constraints.maxHeight < 120;

        if (isCompact) {
          return Container(
            decoration: BoxDecoration(gradient: bgGradient),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.no_photography_outlined,
                  size: iconSize ?? (constraints.maxHeight < 90 ? 20 : 24),
                  color: iconColor,
                ),
                const SizedBox(height: 3),
                Text(
                  message ?? 'No photo',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: constraints.maxHeight < 90 ? 9.5 : 10.5,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(gradient: bgGradient),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF334155).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.no_photography_outlined,
                  size: iconSize ?? 30,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message ?? 'No photos attached',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                  letterSpacing: 0.2,
                ),
              ),
              if (constraints.maxHeight >= 160) ...[
                const SizedBox(height: 2),
                Text(
                  'The author did not attach images',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: subtextColor,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
