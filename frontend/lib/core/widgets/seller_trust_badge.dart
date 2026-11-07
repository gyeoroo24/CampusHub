import 'package:flutter/material.dart';

/// Shows "Negative Seller" / "Blocked Seller" for a listing whose seller has crossed a
/// moderator-confirmed-removal threshold. Renders nothing for every other
/// seller - there is no positive badge, only this warning, and it's never shown for its own sake.
class SellerTrustBadge extends StatelessWidget {
  final String? tag; // 'negative' | 'blocked' | null
  final double fontSize;

  const SellerTrustBadge({super.key, required this.tag, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    if (tag != 'negative' && tag != 'blocked') return const SizedBox.shrink();
    final blocked = tag == 'blocked';
    final color = blocked ? Colors.red.shade700 : Colors.orange.shade800;
    final label = blocked ? 'Blocked Seller' : 'Negative Seller';
    return Tooltip(
      message: blocked
          ? 'This seller has had a listing removed for an illegal or repeatedly prohibited item.'
          : 'This seller has had multiple listings removed by a moderator.',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: fontSize * 0.7, vertical: fontSize * 0.3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: fontSize + 2, color: color),
            SizedBox(width: fontSize * 0.3),
            Text(label, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
