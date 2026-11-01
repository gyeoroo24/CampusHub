import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/admin/providers/admin_providers.dart';
import '../../features/auth/ui/auth_dialog.dart';
import '../utils/error_text.dart';

/// Lets a signed-in user flag a listing or lost/found report for moderator review (FR-10).
/// Call [ReportContentDialog.show] rather than constructing this directly — it handles the
/// sign-in gate first.
class ReportContentDialog extends ConsumerStatefulWidget {
  final String targetType; // 'listing' | 'lost_report' | 'found_report'
  final String targetId;
  final String itemLabel; // e.g. "this listing", "this report"

  const ReportContentDialog({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.itemLabel,
  });

  static const _presetReasons = [
    'Prohibited or unsafe item',
    'Scam or misleading post',
    'Contains personal contact info that shouldn\'t be public',
    'Spam or duplicate post',
    'Abusive or inappropriate content',
  ];

  /// Signs the user in if needed, then opens the report dialog.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required String targetType,
    required String targetId,
    required String itemLabel,
  }) async {
    final signedIn = await AuthDialog.ensureSignedIn(
      context,
      ref,
      title: 'Sign In to Report Content',
      message: 'Only signed-in IISc users can report listings and lost & found posts.',
    );
    if (!signedIn || !context.mounted) return;

    await showDialog(
      context: context,
      builder: (_) => ReportContentDialog(targetType: targetType, targetId: targetId, itemLabel: itemLabel),
    );
  }

  @override
  ConsumerState<ReportContentDialog> createState() => _ReportContentDialogState();
}

class _ReportContentDialogState extends ConsumerState<ReportContentDialog> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _controller.text.trim();
    if (reason.isEmpty) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminRepositoryProvider).createReport(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: reason,
          );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
        content: Text('Thanks — a moderator will review this.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(errorText(e)),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report ${widget.itemLabel}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tell a moderator what\'s wrong with it.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in ReportContentDialog._presetReasons)
                    ActionChip(
                      label: Text(preset, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _controller.text = preset),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                maxLines: 4,
                maxLength: 1000,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'What\'s the issue with this post?',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting || _controller.text.trim().isEmpty ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Submit Report'),
        ),
      ],
    );
  }
}
