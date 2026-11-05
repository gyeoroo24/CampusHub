import 'package:flutter/material.dart';

/// Shown on a listing, report or wanted post whose author has deactivated their account. The post stays up;
/// messages to its author are turned off.
class DeactivatedSellerBadge extends StatelessWidget {
  final double fontSize;

  const DeactivatedSellerBadge({super.key, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF64748B);
    return Tooltip(
      message: 'This person has deactivated their CampusHub account. You can\'t message them.',
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
            Icon(Icons.person_off_outlined, size: fontSize + 2, color: color),
            SizedBox(width: fontSize * 0.3),
            Text('Deactivated account',
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
