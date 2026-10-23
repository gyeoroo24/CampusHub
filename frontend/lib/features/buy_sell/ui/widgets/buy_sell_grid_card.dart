import 'package:flutter/material.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../domain/buy_sell_item.dart';
import 'buy_sell_detail_dialog.dart';

class BuySellGridCard extends StatefulWidget {
  final ListingItem item;
  final ValueChanged<ListingStatus>? onStatusChange;

  const BuySellGridCard({
    super.key,
    required this.item,
    this.onStatusChange,
  });

  @override
  State<BuySellGridCard> createState() => _BuySellGridCardState();
}

class _BuySellGridCardState extends State<BuySellGridCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSold = item.status == ListingStatus.sold;

    Color statusColor;
    String statusLabel;

    switch (item.status) {
      case ListingStatus.available:
        statusColor = const Color(0xFF059669);
        statusLabel = 'AVAILABLE';
        break;
      case ListingStatus.reserved:
        statusColor = Colors.amber.shade800;
        statusLabel = 'RESERVED';
        break;
      case ListingStatus.sold:
        statusColor = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
        statusLabel = 'SOLD';
        break;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _isHovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: _isHovered ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: _isHovered ? 0.4 : 0.2)
                  : Colors.black.withValues(alpha: _isHovered ? 0.08 : 0.03),
              blurRadius: _isHovered ? 16 : 8,
              offset: Offset(0, _isHovered ? 6 : 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => BuySellDetailDialog(
                item: item,
                onStatusChange: widget.onStatusChange,
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image container with Hero animation & Badges
              Expanded(
                flex: 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'listing_hero_${item.id}',
                      child: Opacity(
                        opacity: isSold ? 0.6 : 1.0,
                        child: Image.network(
                          item.imageUrl,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => Container(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            child: Center(
                              child: Icon(
                                Icons.shopping_bag_outlined,
                                size: 40,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Gradient vignette overlay for better badge readability
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [
                              Colors.black.withValues(alpha: 0.35),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Category pill on top-left
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          item.category.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    // Status Pill on top-right
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          statusLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Item details (Amazon / modern e-commerce format)
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
                          Text(
                            item.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.25,
                              color: isSold ? Colors.grey : null,
                              decoration: isSold ? TextDecoration.lineThrough : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.description,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  item.location.isNotEmpty ? item.location : 'IISc Campus',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Seller info
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 8,
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                child: Text(
                                  item.seller.name.isNotEmpty ? item.seller.name[0].toUpperCase() : 'U',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  item.seller.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.verified, size: 12, color: Colors.teal.shade600),
                            ],
                          ),
                        ],
                      ),

                      // Price and Time row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${item.price.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: isSold
                                  ? Colors.grey
                                  : Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time_rounded, size: 11, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text(
                                DateTimeFormatter.timeAgo(item.createdAt),
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
