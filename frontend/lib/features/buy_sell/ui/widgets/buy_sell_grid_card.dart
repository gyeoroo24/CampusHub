import 'package:flutter/material.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../domain/buy_sell_item.dart';
import 'buy_sell_detail_dialog.dart';

class BuySellGridCard extends StatelessWidget {
  final ListingItem item;
  final ValueChanged<ListingStatus>? onStatusChange;

  const BuySellGridCard({
    super.key,
    required this.item,
    this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSold = item.status == ListingStatus.sold;

    Color cardBg;
    Color borderColor;
    Color statusColor;
    String statusLabel;

    switch (item.status) {
      case ListingStatus.available:
        cardBg = isDark ? const Color(0xFF062E1B) : const Color(0xFFF0FDF4); // Light Green
        borderColor = isDark ? const Color(0xFF065F46) : const Color(0xFFA7F3D0);
        statusColor = const Color(0xFF059669);
        statusLabel = 'AVAILABLE';
        break;
      case ListingStatus.reserved:
        cardBg = isDark ? const Color(0xFF2E2406) : const Color(0xFFFEFCE8); // Off-Yellow
        borderColor = isDark ? Colors.amber.shade800 : Colors.amber.shade300;
        statusColor = Colors.amber.shade800;
        statusLabel = 'RESERVED';
        break;
      case ListingStatus.sold:
        // Neutral greys (no blue tint)
        cardBg = isDark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5);
        borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8);
        statusColor = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
        statusLabel = 'SOLD OUT';
        break;
    }

    return Card(
      color: cardBg,
      clipBehavior: Clip.antiAlias,
      elevation: isSold ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => BuySellDetailDialog(
              item: item,
              onStatusChange: onStatusChange,
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Opacity(
                    opacity: isSold ? 0.6 : 1.0,
                    child: Image.network(
                      item.imageUrl,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: 600,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: const Center(child: Icon(Icons.image, size: 40)),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
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
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          children: [
                            Text(
                              '₹${item.sellingPrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: isSold ? Colors.grey : Colors.indigo,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              'Cost Price: ₹${item.costPrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                decoration: TextDecoration.lineThrough,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Chip(
                          label: Text(item.category, style: const TextStyle(fontSize: 10)),
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.location,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSold
                          ? Colors.grey
                          : (isDark ? Colors.grey[300] : Colors.grey[700]),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'By ${item.sellerEmail}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time_rounded, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Text(
                            DateTimeFormatter.timeAgo(item.createdAt),
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
