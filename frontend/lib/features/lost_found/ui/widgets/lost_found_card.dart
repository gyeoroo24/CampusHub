import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/contact_actions.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../../../core/widgets/no_photo_placeholder.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../domain/lost_found_item.dart';
import '../../../messages/ui/messages_screen.dart';
import 'lost_found_detail_dialog.dart';

class LostFoundCard extends StatefulWidget {
  final LostFoundItem item;
  final ValueChanged<ReportStatus>? onStatusChange;

  const LostFoundCard({
    super.key,
    required this.item,
    this.onStatusChange,
  });

  @override
  State<LostFoundCard> createState() => _LostFoundCardState();
}

class _LostFoundCardState extends State<LostFoundCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLost = item.kind == PostType.lost;

    Color badgeColor;
    String statusLabel;

    if (item.status == ReportStatus.closed) {
      badgeColor = Colors.grey.shade600;
      statusLabel = ReportStatus.closed.label.toUpperCase();
    } else {
      badgeColor = isLost ? Colors.pinkAccent.shade700 : Colors.teal.shade700;
      statusLabel = isLost ? 'LOST' : 'FOUND';
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
                ? badgeColor.withValues(alpha: 0.6)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: _isHovered ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: _isHovered ? 0.35 : 0.15)
                  : Colors.black.withValues(alpha: _isHovered ? 0.08 : 0.03),
              blurRadius: _isHovered ? 12 : 6,
              offset: Offset(0, _isHovered ? 5 : 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => LostFoundDetailDialog(item: item),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo with Hero animation and Badges
              Expanded(
                flex: 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'report_hero_${item.id}',
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
                          : NoPhotoPlaceholder(
                              message: isLost ? 'No photo of lost item' : 'No photo attached',
                            ),
                    ),
                    // Top gradient overlay for badge contrast
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [
                              Colors.black.withValues(alpha: 0.4),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Status Badge
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(6),
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
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                    // Incident time pill on top right
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          DateTimeFormatter.timeAgo(item.occurredAt),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category, title and description share whatever height the card has left and are
                      // clipped, never overflowing, when a long title pushes the rest down.
                      Expanded(
                        child: ClipRect(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Category Tag right above title
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.0),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.category.name,
                                  style: TextStyle(
                                    color: badgeColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),

                              // Title
                              Text(
                                item.displayTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  height: 1.25,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),

                              // Description taking remaining white space
                              Flexible(
                                child: Text(
                                  item.description.isNotEmpty ? item.description : 'No distinguishing description provided.',
                                  style: TextStyle(
                                    fontSize: 11.0,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    height: 1.25,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),

                    // Reporter and Location row (consistent with BnS: username on top, location under username)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_outline_rounded, size: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      item.reporter.name,
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
                                  Flexible(
                                    child: Text(
                                      item.location.isNotEmpty ? item.location : 'Campus',
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
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Message the owner/finder (in-app chat) first; email and phone as small extras.
                    // Signed-in users only; not on your own post.
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

/// The card's contact row: a "Message" button that opens the chat with whoever posted this report,
/// about it, plus email and (if given) phone as icon buttons.
class _ContactBar extends ConsumerWidget {
  final LostFoundItem item;
  final bool isDark;

  const _ContactBar({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null || user.isGuest || user.isOwnerOf(item.reporter.id)) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    final phone = item.reporterContact?.phone?.trim() ?? '';
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
              onPressed: () => openChatAbout(context, ref, {
                item.kind == PostType.lost ? 'lost_report_id' : 'found_report_id': item.id,
              }),
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
            final email = item.reporterContact?.email ??
                '${item.reporter.name.toLowerCase().replaceAll(' ', '.')}@iisc.ac.in';
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
