import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../../../core/widgets/photo_carousel.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../auth/ui/auth_dialog.dart';
import '../../domain/buy_sell_item.dart';
import '../../providers/buy_sell_providers.dart';

class BuySellDetailDialog extends ConsumerWidget {
  final ListingItem item;
  final ValueChanged<ListingStatus>? onStatusChange;

  const BuySellDetailDialog({
    super.key,
    required this.item,
    this.onStatusChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final carouselSize = (screenHeight * 0.38).clamp(220.0, 480.0);
    final currentUser = ref.watch(currentUserProvider);
    final isOwner = currentUser != null && currentUser.isOwnerOf(item.seller.id);
    final canModerate = currentUser != null && (currentUser.canModerateBuySell || currentUser.isAdmin);

    Color statusColor;
    switch (item.status) {
      case ListingStatus.available:
        statusColor = const Color(0xFF10B981);
        break;
      case ListingStatus.reserved:
        statusColor = Colors.amber.shade700;
        break;
      case ListingStatus.sold:
        statusColor = const Color(0xFF64748B);
        break;
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 580, maxHeight: screenHeight * 0.85),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Photo carousel (square / responsive) ──────────────────────
              Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: PhotoCarousel(
                      imageUrls: item.photoUrls,
                      size: carouselSize,
                      heroTag: 'listing_hero_${item.id}',
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
                  // Status badge
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.status.name.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
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
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(
                            item.category.name,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '₹${item.price.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.location.isNotEmpty ? item.location : 'IISc Campus',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Listed ${DateTimeFormatter.timeAgo(item.createdAt)} (${DateTimeFormatter.fullDateTime(item.createdAt)})',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    const Text('Description', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      item.description.isNotEmpty ? item.description : 'No additional description provided.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      ),
                    ),
                    const Divider(height: 28),

                    // ── Owner Controls (Change Status) ─────────────────────────
                    if (isOwner) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Listing Owner Controls',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: ListingStatus.values.map((status) {
                                final isSelected = item.status == status;
                                return ChoiceChip(
                                  label: Text(status.name.toUpperCase()),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected && onStatusChange != null) {
                                      onStatusChange!(status);
                                      Navigator.pop(context);
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Seller Contact Section (PRD Scenario 1 Privacy) ────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: item.sellerContact != null
                          ? Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: theme.colorScheme.primary,
                                  child: Text(
                                    item.seller.name.isNotEmpty ? item.seller.name[0].toUpperCase() : 'S',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.seller.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        item.sellerContact!.email,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (item.sellerContact!.phone != null)
                                        Text(
                                          item.sellerContact!.phone!,
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: item.sellerContact!.email));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Copied email: ${item.sellerContact!.email}')),
                                    );
                                  },
                                  icon: const Icon(Icons.copy_rounded, size: 14),
                                  label: const Text('Contact'),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.lock_outline_rounded, size: 18, color: Colors.amber.shade800),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Seller Contact Details Protected',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Seller: ${item.seller.name} • Contact information is visible to authenticated IISc students only.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final signedIn = await AuthDialog.ensureSignedIn(
                                        context,
                                        ref,
                                        title: 'Sign In to View Contact Info',
                                        message: 'Sign in with your @iisc.ac.in account to view seller details.',
                                      );
                                      if (signedIn && context.mounted) {
                                        Navigator.pop(context);
                                        ref.invalidate(buySellListingsProvider);
                                      }
                                    },
                                    icon: const Icon(Icons.login_rounded, size: 16),
                                    label: const Text('Sign in with IISc Email to Reveal Contact'),
                                  ),
                                ),
                              ],
                            ),
                    ),

                    // ── Moderator Removal (FR-10) ──────────────────────────────
                    if (canModerate) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                          onPressed: () => _confirmModeratorDelete(context, ref),
                          icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                          label: const Text('Moderator: Remove Listing'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmModeratorDelete(BuildContext context, WidgetRef ref) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Listing (Moderation)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'As a moderator, you can remove this listing. Please provide a reason for the audit log:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for removal',
                hintText: 'e.g. Prohibited item, duplicate, or spam',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              Navigator.pop(ctx); // Close prompt
              Navigator.pop(context); // Close detail dialog
              await ref.read(buySellRepositoryProvider).deleteListing(
                    item.id,
                    reason: reasonController.text.trim(),
                  );
              ref.invalidate(buySellListingsProvider);
            },
            child: const Text('Confirm Remove'),
          ),
        ],
      ),
    );
  }
}
