import 'package:flutter/material.dart';
import 'listing_bookmarks.dart';

import '../../../../core/widgets/deactivated_seller_badge.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../../../core/widgets/no_photo_placeholder.dart';
import '../../../../core/widgets/seller_trust_badge.dart';
import '../../domain/buy_sell_item.dart';
import 'buy_sell_detail_dialog.dart';
import 'price_watch.dart';

class BuySellListCard extends StatefulWidget {
  final ListingItem item;
  final ValueChanged<ListingStatus>? onStatusChange;

  const BuySellListCard({
    super.key,
    required this.item,
    this.onStatusChange,
  });

  @override
  State<BuySellListCard> createState() => _BuySellListCardState();
}

class _BuySellListCardState extends State<BuySellListCard> {
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
        statusLabel = ListingStatus.available.label.toUpperCase();
        break;
      case ListingStatus.reserved:
        statusColor = Colors.amber.shade800;
        statusLabel = ListingStatus.reserved.label.toUpperCase();
        break;
      case ListingStatus.sold:
        statusColor = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
        statusLabel = ListingStatus.sold.label.toUpperCase();
        break;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
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
                  ? Colors.black.withValues(alpha: _isHovered ? 0.35 : 0.15)
                  : Colors.black.withValues(alpha: _isHovered ? 0.08 : 0.03),
              blurRadius: _isHovered ? 12 : 6,
              offset: Offset(0, _isHovered ? 4 : 2),
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
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail with smaller status badge on top-left of pic
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Hero(
                            tag: 'listing_hero_${item.id}',
                            child: Opacity(
                              opacity: isSold ? 0.6 : 1.0,
                              child: item.imageUrl.isNotEmpty
                                  ? Image.network(
                                      item.imageUrl,
                                      width: 105,
                                      height: 85,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 105,
                                        height: 85,
                                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.broken_image_outlined, size: 24, color: Colors.grey.shade400),
                                            const SizedBox(height: 2),
                                            Text('Failed to load', style: TextStyle(fontSize: 8, color: Colors.grey.shade400)),
                                          ],
                                        ),
                                      ),
                                    )
                                  : const SizedBox(
                                      width: 105,
                                      height: 85,
                                      child: NoPhotoPlaceholder(compact: true),
                                    ),
                            ),
                          ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: ListingBookmarkIcon(listingId: item.id, size: 14),
                          ),
                          Positioned(
                            top: 5,
                            left: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                statusLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Content details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isSold ? Colors.grey : null,
                              decoration: isSold ? TextDecoration.lineThrough : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.description,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),

                          // Price - Category row with spaceBetween
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '₹${item.price.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: isSold ? Colors.grey : Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              if (item.negotiable) ...[
                                const SizedBox(width: 4),
                                const NegotiableBadge(fontSize: 9),
                              ],
                              const SizedBox(width: 6),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item.category.name,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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

                const SizedBox(height: 8),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
                const SizedBox(height: 6),

                // Bottom Row: Location (bottom left below pic) - User Name (center) - Time (bottom right below description)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Location below pic
                    Flexible(
                      flex: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              item.location.isNotEmpty ? item.location : 'IISc Campus',
                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    // User name in center
                    Flexible(
                      flex: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline_rounded, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              item.seller.name,
                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Time below description
                    Flexible(
                      flex: 3,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.access_time_rounded, size: 11, color: Colors.grey.shade500),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              DateTimeFormatter.timeAgo(item.createdAt),
                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (item.sellerDeactivated) ...[
                  DeactivatedSellerBadge(fontSize: 9),
                  const SizedBox(width: 4),
                ],
                if (item.sellerTrustTag != null) ...[
                  const SizedBox(height: 6),
                  SellerTrustBadge(tag: item.sellerTrustTag, fontSize: 9),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
