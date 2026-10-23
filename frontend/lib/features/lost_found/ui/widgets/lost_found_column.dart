import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../auth/ui/auth_dialog.dart';
import '../../domain/lost_found_item.dart';
import '../../providers/lost_found_providers.dart';
import 'lost_found_card.dart';
import 'report_item_dialog.dart';

class LostFoundColumn extends ConsumerWidget {
  final String title;
  final IconData icon;
  final Color headerColor;
  final String buttonText;
  final PostType postType;
  final AsyncValue<List<LostFoundItem>> asyncData;

  const LostFoundColumn({
    super.key,
    required this.title,
    required this.icon,
    required this.headerColor,
    required this.buttonText,
    required this.postType,
    required this.asyncData,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Sleek Responsive Column Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: headerColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: headerColor.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, color: headerColor, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: headerColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    asyncData.maybeWhen(
                      data: (items) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: headerColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${items.length}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: headerColor,
                          ),
                        ),
                      ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: headerColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  final signedIn = await AuthDialog.ensureSignedIn(
                    context,
                    ref,
                    title: postType == PostType.lost
                        ? 'Sign In to Report Lost Item'
                        : 'Sign In to Report Found Item',
                    message: 'Only verified IISc students can post lost and found reports.',
                  );
                  if (!signedIn || !context.mounted) return;

                  final user = ref.read(currentUserProvider);
                  showDialog(
                    context: context,
                    builder: (ctx) => ReportItemDialog(
                      postType: postType,
                      userEmail: user?.email,
                      userId: user?.id,
                      userName: user?.name,
                      onSubmit: (report) async {
                        final created = await ref.read(lostFoundRepositoryProvider).submitReport(report);
                        ref.invalidate(lostReportsProvider);
                        ref.invalidate(foundReportsProvider);
                        return created;
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.add_rounded, size: 15),
                label: Text(
                  buttonText,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Content Feed (Adaptive Grid on Desktop / ListView on Mobile)
        Expanded(
          child: asyncData.when(
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_rounded, size: 36, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'No ${title.toLowerCase()} matching filter.',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  // If column width > 440 (e.g. desktop side-by-side), show 2 square cards per row!
                  if (constraints.maxWidth > 440) {
                    return GridView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.74,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) => LostFoundCard(item: items[index]),
                    );
                  }

                  // Single column (mobile or narrow container)
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: items.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: LostFoundCard(item: items[index]),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }
}
