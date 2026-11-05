import 'package:flutter/material.dart';

import '../../../../core/widgets/deactivated_seller_badge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/contact_actions.dart';
import '../../../../core/utils/error_text.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../../../core/utils/web_history_support.dart';
import '../../../../core/widgets/photo_carousel.dart';
import '../../../../core/widgets/report_content_dialog.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../auth/ui/auth_dialog.dart';
import '../../../messages/ui/messages_screen.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';
import 'edit_report_dialog.dart';
import 'possible_matches_section.dart';

class LostFoundDetailDialog extends ConsumerWidget {
  final LostFoundItem item;
  final ValueChanged<ReportStatus>? onStatusChange;

  const LostFoundDetailDialog({
    super.key,
    required this.item,
    this.onStatusChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The feed's summary has no reporter contact or photos: show it at once, then the full report.
    final full = ref.watch(lostFoundDetailProvider((id: this.item.id, kind: this.item.kind)));
    final item = full.valueOrNull ?? this.item;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLost = item.kind == PostType.lost;
    final themeColor = isLost ? const Color(0xFFE11D48) : const Color(0xFF0D9488);
    final screenHeight = MediaQuery.of(context).size.height;
    final carouselSize = (screenHeight * 0.38).clamp(220.0, 480.0);
    final currentUser = ref.watch(currentUserProvider);
    final isOwner = currentUser != null && currentUser.isOwnerOf(item.reporter.id);
    final canModerate = currentUser != null && (currentUser.canModerateLostFound || currentUser.isAdmin);

    return ModalHistoryWrapper(
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
              // ── Photo carousel (square) ──────────────────────────────────
              Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: PhotoCarousel(
                      imageUrls: item.photoUrls,
                      size: carouselSize,
                      heroTag: 'report_hero_${item.id}',
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
                  // Report button (not for the report's own author)
                  if (!isOwner)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: CircleAvatar(
                        backgroundColor: Colors.black.withValues(alpha: 0.6),
                        child: IconButton(
                          tooltip: 'Report this post',
                          icon: const Icon(Icons.flag_outlined, color: Colors.white, size: 18),
                          onPressed: () => ReportContentDialog.show(
                            context,
                            ref,
                            targetType: isLost ? 'lost_report' : 'found_report',
                            targetId: item.id,
                            itemLabel: 'this report',
                          ),
                        ),
                      ),
                    ),
                  // Status / Type badge
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: themeColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isLost ? 'LOST REPORT' : 'FOUND REPORT',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  // Current Status Badge
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.status.label.toUpperCase(),
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

              // ── Details ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Badge Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: themeColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        item.category.name,
                        style: TextStyle(
                          color: themeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Main Headline / Title
                    Text(
                      item.displayTitle,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.3),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.location.isNotEmpty ? item.location : 'Campus Location Not Specified',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
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
                            'Occurred: ${DateTimeFormatter.fullDateTime(item.occurredAt)} (${DateTimeFormatter.timeAgo(item.occurredAt)})',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    Text(
                      item.description.isNotEmpty ? item.description : 'No distinguishing description provided.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      ),
                    ),
                    const Divider(height: 28),

                    // ── Possible matches (FR-9): only on your own report ──
                    if (isOwner || (currentUser?.isAdmin ?? false)) PossibleMatchesSection(item: item),

                    // ── Status & Owner Controls (Original Reporter Only) ───────────────
                    // The backend lets the admin edit anyone's report too.
                    if (isOwner || (currentUser?.isAdmin ?? false)) ...[
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
                                  isOwner ? 'Report Owner Controls' : 'Admin Controls',
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
                              children: ReportStatus.values.map((status) {
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

                    // ── In-app messaging (joins the chat with this person) ─────
                    if (!isOwner) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('message_reporter'),
                          onPressed: () => openChatAbout(context, ref, {
                            item.kind == PostType.lost ? 'lost_report_id' : 'found_report_id': item.id,
                          }),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: Text(item.kind == PostType.lost ? 'Message the owner' : 'Message the finder'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Reporter Contact Section (Privacy Protection) ──────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: (item.reporterContact != null && currentUser != null && !currentUser.isGuest)
                          ? Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: themeColor,
                                  child: Text(
                                    item.reporter.name.isNotEmpty
                                        ? item.reporter.name[0].toUpperCase()
                                        : 'R',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (item.reporterDeactivated) ...[
                                        const DeactivatedSellerBadge(fontSize: 10),
                                        const SizedBox(height: 4),
                                      ],
                                      Text(
                                        item.reporter.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        item.reporterContact!.email,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (item.reporterContact!.phone != null)
                                        Text(
                                          item.reporterContact!.phone!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: themeColor,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () {
                                        contactBy(context, email: item.reporterContact!.email);
                                      },
                                      icon: const Icon(Icons.email_outlined, size: 14),
                                      label: const Text('Email'),
                                    ),
                                    if (item.reporterContact!.phone != null &&
                                        item.reporterContact!.phone!.trim().isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: themeColor,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () {
                                          contactBy(context, phone: item.reporterContact!.phone!);
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
                                            'Reporter Account Inactive',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Reported by: ${item.reporter.name} • This account is currently deactivated by campus administration. Contact information is unavailable.',
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
                                            'Reporter Contact Details Protected',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Reported by: ${item.reporter.name} • Contact details are only visible to authenticated IISc members.',
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
                                        message: 'Sign in with your @iisc.ac.in account to view contact info.',
                                      );
                                      if (signedIn && context.mounted) {
                                        Navigator.pop(context);
                                        ref.invalidate(lostReportsProvider);
                                        ref.invalidate(foundReportsProvider);
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
                          label: const Text('Moderator: Remove Report'),
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
    ));
  }

  Future<void> _openEditDialog(BuildContext context, WidgetRef ref) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => EditReportDialog(item: item),
    );
    if (updated == true && context.mounted) {
      Navigator.pop(context);
    }
  }

  LostFoundPaginationNotifier _feed(WidgetRef ref) => item.kind == PostType.lost
      ? ref.read(lostReportsPaginationProvider.notifier)
      : ref.read(foundReportsPaginationProvider.notifier);

  void _refreshLists(WidgetRef ref) {
    ref.invalidate(lostReportsProvider);
    ref.invalidate(foundReportsProvider);
    ref.invalidate(myLostReportsProvider);
    ref.invalidate(myFoundReportsProvider);
    ref.invalidate(lostFoundDetailProvider((id: item.id, kind: item.kind)));
  }

  /// Saves the new status, then updates the card in the feed. Stays open on failure, with the reason.
  Future<void> _changeStatus(BuildContext context, WidgetRef ref, ReportStatus status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(lostFoundRepositoryProvider).updateStatus(item.id, item.kind, status);
      _feed(ref).updateItemStatusLocally(item.id, status);
      _refreshLists(ref);
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

  /// Removes the report, waiting for the server before closing anything.
  Future<void> _remove(BuildContext context, WidgetRef ref, BuildContext promptContext, {String? reason}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(lostFoundRepositoryProvider).deleteReport(item.id, item.kind, reason: reason);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't remove the report: ${errorText(e)}"),
        backgroundColor: Colors.red.shade700,
      ));
      return;
    }
    if (promptContext.mounted) Navigator.pop(promptContext);
    if (context.mounted) Navigator.pop(context);
    _feed(ref).removeItemLocally(item.id);
    _refreshLists(ref);
    messenger.showSnackBar(const SnackBar(
      content: Text('Report removed from the board.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _confirmOwnerDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${item.kind == PostType.lost ? "Lost" : "Found"} Report',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Delete this report? It will no longer appear on the Lost & Found board.',
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Report (Moderation)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'As a moderator, you can remove this report. Please provide a reason for the moderation log:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for removal',
                hintText: 'e.g. Inappropriate content, resolved offline, or duplicate',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => _remove(context, ref, ctx, reason: reasonController.text.trim()),
            child: const Text('Confirm Remove'),
          ),
        ],
      ),
    );
  }
}
