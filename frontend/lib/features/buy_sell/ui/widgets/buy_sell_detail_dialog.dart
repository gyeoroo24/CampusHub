import 'package:flutter/material.dart';

import '../../../../core/widgets/deactivated_seller_badge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'listing_bookmarks.dart';
import '../../../../core/utils/contact_actions.dart';
import '../../../../core/utils/error_text.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../../../core/utils/web_history_support.dart';
import '../../../../core/widgets/photo_carousel.dart';
import '../../../../core/widgets/report_content_dialog.dart';
import '../../../../core/widgets/seller_trust_badge.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../auth/ui/auth_dialog.dart';
import '../../../messages/ui/messages_screen.dart';
import '../../domain/buy_sell_item.dart';
import '../../providers/buy_sell_providers.dart';
import 'edit_listing_dialog.dart';
import 'price_watch.dart';

class BuySellDetailDialog extends ConsumerWidget {
  final ListingItem item;
  final ValueChanged<ListingStatus>? onStatusChange;

  /// Give the dialog its own browser-history entry, so browser back closes it. Off when the dialog is
  /// a router page (`/buy/<id>`, listing_links.dart): the router already owns that history entry, and a
  /// second one made closing the dialog step back onto the listing's address and reopen it.
  final bool ownHistoryEntry;

  const BuySellDetailDialog({
    super.key,
    required this.item,
    this.onStatusChange,
    this.ownHistoryEntry = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The feed's summary has no description or seller contact: show it at once, then the full listing.
    final full = ref.watch(listingDetailProvider(this.item.id));
    final item = full.valueOrNull ?? this.item;
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

    return ModalHistoryWrapper(
      enabled: ownHistoryEntry,
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        surfaceTintColor: Colors.transparent,
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
                  // Report button (not for the listing's own owner)
                  if (!isOwner)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: CircleAvatar(
                        backgroundColor: Colors.black.withValues(alpha: 0.6),
                        child: IconButton(
                          tooltip: 'Report this listing',
                          icon: const Icon(Icons.flag_outlined, color: Colors.white, size: 18),
                          onPressed: () => ReportContentDialog.show(
                            context,
                            ref,
                            targetType: 'listing',
                            targetId: item.id,
                            itemLabel: 'this listing',
                          ),
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
                        item.status.label.toUpperCase(),
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
                    // Category Badge Pill (Small, above title)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        item.category.name,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Title
                    Text(
                      item.title,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 14),

                    // Description (without "Description" heading)
                    Text(
                      item.description.isNotEmpty ? item.description : 'No additional description provided.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Price and Seller-Location Row (between title & description)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_outline_rounded, size: 15, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(
                                  item.seller.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                            if (item.sellerDeactivated) ...[
                              DeactivatedSellerBadge(fontSize: 10),
                              const SizedBox(width: 4),
                            ],
                            if (item.sellerTrustTag != null) ...[
                              const SizedBox(height: 4),
                              SellerTrustBadge(tag: item.sellerTrustTag, fontSize: 10),
                            ],
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on_outlined, size: 15, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Text(
                                  item.location.isNotEmpty ? item.location : 'IISc Campus',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${item.price.toStringAsFixed(0)}',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (item.negotiable) const NegotiableBadge(fontSize: 11),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ── Status & Owner Controls (Original Author Only) ─────────────────────────
                    // Only the seller edits a listing; moderators and the admin can remove it (below).
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Listing Owner Controls',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                      icon: const Icon(Icons.edit_outlined, size: 14),
                                      label: const Text('Edit', style: TextStyle(fontSize: 12)),
                                      onPressed: () => _openEditDialog(context, ref),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red.shade700,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                      icon: const Icon(Icons.delete_outline_rounded, size: 14),
                                      label: const Text('Delete', style: TextStyle(fontSize: 12)),
                                      onPressed: () => _confirmOwnerDelete(context, ref),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: ListingStatus.values.map((status) {
                                final isSelected = item.status == status;
                                return ChoiceChip(
                                  label: Text(status.label),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected && !isSelected) _changeStatus(context, ref, status);
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (item.heldForReview) const HeldForReviewBanner(),

                    // ── In-app messaging (joins the chat with this person) ─────
                    if (!isOwner && item.status != ListingStatus.sold) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('message_seller'),
                          onPressed: () => openChatAboutListing(context, ref, item.id),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: const Text('Message seller'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: ListingBookmarkButton(listingId: item.id)),
                      // Price watch (future plan §2.3), signed-in buyers only.
                      if (currentUser != null && !currentUser.isGuest) ...[
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: WatchPriceButton(item: item)),
                      ],
                      const SizedBox(height: 12),
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
                      child: (item.sellerContact != null && currentUser != null && !currentUser.isGuest)
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
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        contactBy(context, email: item.sellerContact!.email);
                                      },
                                      icon: const Icon(Icons.email_outlined, size: 14),
                                      label: const Text('Email'),
                                    ),
                                    if (item.sellerContact!.phone != null &&
                                        item.sellerContact!.phone!.trim().isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          contactBy(context, phone: item.sellerContact!.phone!);
                                        },
                                        icon: const Icon(Icons.phone_outlined, size: 14),
                                        label: const Text('Call'),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            )
                          : (currentUser != null && !currentUser.isGuest && full.isLoading)
                              ? Row(
                                  children: [
                                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                    const SizedBox(width: 10),
                                    Text('Loading contact details…', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  ],
                                )
                              : (currentUser != null && !currentUser.isGuest)
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.person_off_outlined, size: 18, color: Colors.amber.shade800),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text(
                                            'Seller Account Inactive',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Seller: ${item.seller.name} • This account is currently deactivated by campus administration. Contact information is unavailable.',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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

                    // ── Moderator Removal (FR-10, for non-owners) ───────────────────
                    if (canModerate && !isOwner) ...[
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

                    // ── Listed Timestamp (Bottom of modal) ────────────────────
                    const SizedBox(height: 18),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time_rounded, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 6),
                          Text(
                            'Listed ${DateTimeFormatter.timeAgo(item.createdAt)} (${DateTimeFormatter.fullDateTime(item.createdAt)})',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
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
    ));
  }

  Future<void> _openEditDialog(BuildContext context, WidgetRef ref) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => EditListingDialog(item: item),
    );
    if (updated == true && context.mounted) {
      Navigator.pop(context);
    }
  }

  /// Saves the new status, then updates the card in the feed and the profile. The dialog stays
  /// open on failure, with the reason.
  Future<void> _changeStatus(BuildContext context, WidgetRef ref, ListingStatus status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(buySellRepositoryProvider).updateStatus(item.id, status);
      ref.read(buySellPaginationProvider.notifier).updateItemStatusLocally(item.id, status);
      ref.invalidate(listingDetailProvider(item.id));
      ref.invalidate(myBuySellListingsProvider);
      if (context.mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text('Marked as ${status.label.toLowerCase()}.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't change the status: ${errorText(e)}"),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  /// Removes the listing, waiting for the server before closing anything.
  Future<void> _remove(BuildContext context, WidgetRef ref, BuildContext promptContext,
      {String? reason, String? severity}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(buySellRepositoryProvider).deleteListing(item.id, reason: reason, severity: severity);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't remove the listing: ${errorText(e)}"),
        backgroundColor: Colors.red.shade700,
      ));
      return;
    }
    if (promptContext.mounted) Navigator.pop(promptContext);
    if (context.mounted) Navigator.pop(context);
    ref.read(buySellPaginationProvider.notifier).removeItemLocally(item.id);
    ref.invalidate(buySellListingsProvider);
    ref.invalidate(myBuySellListingsProvider);
    messenger.showSnackBar(const SnackBar(
      content: Text('Listing removed from the marketplace.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _confirmOwnerDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Listing', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Delete this listing? It will no longer appear in the marketplace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => _remove(context, ref, ctx),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmModeratorDelete(BuildContext context, WidgetRef ref) {
    final reasonController = TextEditingController();
    var severity = 'non_severe';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Remove Listing (Moderation)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The seller is told the reason. If someone reported this listing, removing it also '
                'counts as a strike on the seller\'s record (they can appeal).',
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
              const SizedBox(height: 12),
              const Text('If it was reported, how serious is it?',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              RadioGroup<String>(
                groupValue: severity,
                onChanged: (v) => setDialogState(() => severity = v ?? severity),
                child: const Column(children: [
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: 'non_severe',
                    title: Text('Non-severe (scam, misleading, duplicate)'),
                    subtitle: Text('Counts toward the strike ladder'),
                  ),
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: 'severe',
                    title: Text('Severe (illegal: drugs, weapons)'),
                    subtitle: Text('Blocks the seller from posting immediately'),
                  ),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => _remove(context, ref, ctx, reason: reasonController.text.trim(), severity: severity),
              child: const Text('Confirm Remove'),
            ),
          ],
        ),
      ),
    );
  }
}
