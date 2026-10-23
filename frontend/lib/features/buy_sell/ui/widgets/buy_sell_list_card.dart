import 'package:flutter/material.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../domain/buy_sell_item.dart';
import 'buy_sell_detail_dialog.dart';

class BuySellListCard extends StatelessWidget {
  final ListingItem item;
  final ValueChanged<ListingStatus>? onStatusChange;

  const BuySellListCard({
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
        cardBg = isDark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5);
        borderColor = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8);
        statusColor = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
        statusLabel = 'SOLD OUT';
        break;
    }

    return Card(
      color: cardBg,
      elevation: isSold ? 0 : 1,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
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
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Opacity(
                  opacity: isSold ? 0.6 : 1.0,
                  child: Image.network(
                    item.imageUrl,
                    width: 120,
                    height: 100,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: 300,
                    errorBuilder: (_, __, ___) => Container(
                      width: 120,
                      height: 100,
                      color: isDark ? const Color(0xFF27272A) : Colors.grey[300],
                      child: const Icon(Icons.shopping_bag_outlined, size: 30),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isSold ? Colors.grey : null,
                              decoration: isSold ? TextDecoration.lineThrough : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: statusColor, width: 1),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '₹${item.price.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: isSold ? Colors.grey : Colors.indigo.shade600,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Chip(
                          label: Text(
                            item.category.name,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSold
                            ? Colors.grey
                            : (isDark ? Colors.grey[300] : Colors.grey[700]),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Seller: ${item.seller.name} • ${item.location.isNotEmpty ? item.location : 'Campus'}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time_rounded, size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 4),
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
      ),
    );
  }
}
