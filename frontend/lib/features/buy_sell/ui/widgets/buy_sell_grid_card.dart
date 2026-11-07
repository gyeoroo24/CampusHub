import 'package:flutter/material.dart';

import '../../../../core/widgets/deactivated_seller_badge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'listing_bookmarks.dart';
import '../../../../core/utils/contact_actions.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../../../core/widgets/no_photo_placeholder.dart';
import '../../../../core/widgets/seller_trust_badge.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../domain/buy_sell_item.dart';
import '../../../messages/ui/messages_screen.dart';
import 'price_watch.dart';
import '../listing_links.dart';

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
          onTap: () => showListingDetail(context, item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image container with Hero animation & Badges
              Expanded(
                flex: 11,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'listing_hero_${item.id}',
                      child: Opacity(
                        opacity: isSold ? 0.6 : 1.0,
                        child: item.imageUrl.isNotEmpty
                            ? Image.network(
                                item.imageUrl,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => Container(
                                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.broken_image_outlined,
                                          size: 32,
                                          color: Colors.grey.shade400,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Failed to load',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : const NoPhotoPlaceholder(),
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
                    // Status Pill on top-left
                    Positioned(
                      top: 10,
                      left: 10,
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
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: ListingBookmarkIcon(listingId: item.id),
                    ),
                    // Time pill on top-right
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time_rounded, size: 11, color: Colors.white70),
                            const SizedBox(width: 3),
                            Text(
                              DateTimeFormatter.timeAgo(item.createdAt),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Item details
              Expanded(
                flex: 12,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category Tag right above title
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.category.name,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Title
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
                      const SizedBox(height: 4),

                      // Description taking remaining white space
                      Expanded(
                        child: Text(
                          item.description.isNotEmpty ? item.description : 'No additional description provided.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Price and Seller Info (Username in place of time, location under username)
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
                                  Icon(Icons.person_outline_rounded, size: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                                  const SizedBox(width: 3),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 110),
                                    child: Text(
                                      item.seller.name,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on_outlined, size: 11, color: Colors.grey.shade500),
                                  const SizedBox(width: 2),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 110),
                                    child: Text(
                                      item.location.isNotEmpty ? item.location : 'IISc Campus',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
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
                              if (item.negotiable) const NegotiableBadge(fontSize: 9),
                            ],
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
                      const SizedBox(height: 8),

                      // Message the seller (in-app chat) first; email and phone as small extras.
                      // Signed-in users only; not on your own listing.
                      _ContactBar(item: item, isDark: isDark),
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

/// The card's contact row: a "Message" button that opens the chat with the seller about this
/// listing, plus email and (if given) phone as icon buttons.
class _ContactBar extends ConsumerWidget {
  final ListingItem item;
  final bool isDark;

  const _ContactBar({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null || user.isGuest || user.isOwnerOf(item.seller.id)) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    final phone = item.sellerContact?.phone?.trim() ?? '';
    final side = BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));
    Widget iconButton(IconData icon, String tooltip, VoidCallback onPressed) => SizedBox(
          width: 34,
          height: 30,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              side: side,
            ),
            child: Tooltip(message: tooltip, child: Icon(icon, size: 15, color: primary)),
          ),
        );
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              key: ValueKey('card_message_${item.id}'),
              // A sold item takes no new chats, but the seller can still be emailed.
              onPressed: item.status == ListingStatus.sold ? null : () => openChatAboutListing(context, ref, item.id),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
              label: const Text('Message', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          iconButton(Icons.email_outlined, 'Email', () {
            final email = item.sellerContact?.email ??
                '${item.seller.name.toLowerCase().replaceAll(' ', '.')}@iisc.ac.in';
            contactBy(context, email: email);
          }),
          if (phone.isNotEmpty) ...[
            const SizedBox(width: 6),
            iconButton(Icons.phone_outlined, 'Call', () => contactBy(context, phone: phone)),
          ],
        ],
      ),
    );
  }
}
