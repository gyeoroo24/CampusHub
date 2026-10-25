import 'package:flutter/material.dart';
import '../../../../core/enums/view_mode.dart';
import '../../domain/buy_sell_item.dart';
import 'buy_sell_grid_card.dart';
import 'buy_sell_list_card.dart';

class BuySellCard extends StatelessWidget {
  final ListingItem item;
  final ViewMode viewMode;
  final ValueChanged<ListingStatus> onStatusChange;

  const BuySellCard({
    super.key,
    required this.item,
    required this.viewMode,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    if (viewMode == ViewMode.list) {
      return BuySellListCard(
        item: item,
        onStatusChange: onStatusChange,
      );
    }

    return BuySellGridCard(
      item: item,
      onStatusChange: onStatusChange,
    );
  }
}
