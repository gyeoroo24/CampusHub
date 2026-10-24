import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/date_time_formatter.dart';
import '../../../../core/utils/web_history_support.dart';
import '../../../../core/widgets/photo_carousel.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../auth/ui/auth_dialog.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';
import 'edit_report_dialog.dart';

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
                        item.status.name.toUpperCase(),
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

                    // ── Status & Owner Controls (Original Reporter Only) ───────────────
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
                                const Text(
                                  'Report Owner Controls',
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
                                  label: Text(status.name.toUpperCase()),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (selected) {
                                      if (onStatusChange != null) {
                                        onStatusChange!(status);
                                      } else {
                                        ref.read(lostFoundRepositoryProvider).updateStatus(
                                              item.id,
                                              item.kind,
                                              status,
                                            );
                                        ref.invalidate(lostReportsProvider);
                                        ref.invalidate(foundReportsProvider);
                                      }
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
                      child: item.reporterContact != null
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
                                        Clipboard.setData(ClipboardData(text: item.reporterContact!.email));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Copied email: ${item.reporterContact!.email}'),
                                          ),
                                        );
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
                                          Clipboard.setData(ClipboardData(text: item.reporterContact!.phone!));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Copied phone: ${item.reporterContact!.phone}'),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.phone_outlined, size: 14),
                                        label: const Text('Call'),
                                      ),
                                    ],
                                  ],
                                ),
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

  void _confirmOwnerDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${item.kind == PostType.lost ? "Lost" : "Found"} Report',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to delete this report? It will be permanently removed from the lost and found board.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(context);
              await ref.read(lostFoundRepositoryProvider).deleteReport(item.id, item.kind);
              ref.invalidate(lostReportsProvider);
              ref.invalidate(foundReportsProvider);
              ref.read(lostReportsPaginationProvider.notifier).loadInitial();
              ref.read(foundReportsPaginationProvider.notifier).loadInitial();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Report deleted successfully.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
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
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(context);
              await ref.read(lostFoundRepositoryProvider).deleteReport(
                    item.id,
                    item.kind,
                    reason: reasonController.text.trim(),
                  );
              ref.invalidate(lostReportsProvider);
              ref.invalidate(foundReportsProvider);
            },
            child: const Text('Confirm Remove'),
          ),
        ],
      ),
    );
  }
}
