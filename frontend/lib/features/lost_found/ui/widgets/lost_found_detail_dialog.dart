import 'package:flutter/material.dart';
import '../../domain/lost_found_item.dart';
import '../../../../core/widgets/photo_carousel.dart';

class LostFoundDetailDialog extends StatelessWidget {
  final LostFoundItem item;

  const LostFoundDetailDialog({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLost = item.type == PostType.lost;
    final themeColor = isLost ? Colors.pinkAccent.shade700 : Colors.teal.shade700;
    final screenHeight = MediaQuery.of(context).size.height;
    // Square carousel size — caps at 500, fills dialog on small screens (identical to BnS)
    final carouselSize = (screenHeight * 0.4).clamp(0.0, 500.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: screenHeight * 0.8),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Photo carousel (square) ──────────────────────────────────
              Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: PhotoCarousel(
                      imageUrls: item.imageUrls,
                      size: carouselSize,
                    ),
                  ),
                  // Close button
                  Positioned(
                    top: 10,
                    left: 10,
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                  // Status / Type badge
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: themeColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isLost ? 'LOST ITEM' : 'FOUND ITEM',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Details ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(item.category, style: const TextStyle(fontSize: 11)),
                          backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.location,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.eventTime,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    const Text('Description', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      ),
                    ),
                    const Divider(height: 28),
                    // Reporter info card (matching BnS seller info card)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: themeColor,
                            child: Text(
                              item.reporterContact.isNotEmpty
                                  ? item.reporterContact[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.reporterContact,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: themeColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Contact info: ${item.reporterContact}')),
                              );
                            },
                            icon: const Icon(Icons.email_outlined, size: 16),
                            label: const Text('Contact'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
