import 'package:flutter/material.dart';
import '../../../core/widgets/category_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/web_history_support.dart';
import '../../../core/utils/error_text.dart';
import '../../auth/ui/auth_dialog.dart';
import '../../buy_sell/providers/buy_sell_providers.dart';
import '../domain/wanted_post.dart';
import '../providers/wanted_providers.dart';
import 'wanted_detail_dialog.dart';

/// "Post a Wanted request": what the buyer needs, its category and an optional budget.
class CreateWantedDialog extends ConsumerStatefulWidget {
  const CreateWantedDialog({super.key});

  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final signedIn = await AuthDialog.ensureSignedIn(
      context,
      ref,
      title: 'Sign In to Post a Wanted Request',
      message: 'Sellers contact you through your IISc email, so posting needs a signed-in account.',
    );
    if (!signedIn || !context.mounted) return;
    final created = await showDialog<WantedPost>(context: context, builder: (_) => const CreateWantedDialog());
    if (created == null || !context.mounted) return;
    // The Wanted feed shares the Buy & Sell search box and category chips: if they would hide the
    // new post, clear them so it shows at the top of the feed.
    final filter = ref.read(buySellFilterProvider);
    final hiddenByCategory =
        filter.category != 'All' && filter.category.toLowerCase() != created.category.name.toLowerCase();
    if (hiddenByCategory || filter.query.isNotEmpty) {
      ref.read(buySellFilterProvider.notifier).state = filter.copyWith(
        category: hiddenByCategory ? 'All' : null,
        query: '',
      );
    }
    final matches = created.possibleMatches.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(matches > 0
            ? 'Posted. $matches listing${matches == 1 ? '' : 's'} already match what you need.'
            : 'Posted. We\'ll notify you when a matching listing appears.'),
      ),
    );
    showDialog(context: context, builder: (_) => WantedDetailDialog(post: created));
  }

  @override
  ConsumerState<CreateWantedDialog> createState() => _CreateWantedDialogState();
}

class _CreateWantedDialogState extends ConsumerState<CreateWantedDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();
  int? _categoryId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final budget = _budgetController.text.trim();
      final created = await ref.read(wantedRepositoryProvider).createWanted(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            categoryId: _categoryId!,
            maxPrice: budget.isEmpty ? null : double.parse(budget),
          );
      ref.invalidate(wantedPostsProvider);
      ref.invalidate(myWantedPostsProvider);
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(buySellCategoriesProvider);
    final theme = Theme.of(context);

    return ModalHistoryWrapper(
      child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.volunteer_activism_outlined),
          SizedBox(width: 10),
          Text('What are you looking for?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Sellers can see this, and you'll get a notification when a listing in this category, "
                  'within your budget, mentions a word from your title.',
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _titleController,
                  maxLength: 120,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Need a Hero cycle for campus',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Say what you need' : null,
                ),
                const SizedBox(height: 4),
                categories.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(errorText(e), style: TextStyle(color: theme.colorScheme.error)),
                  data: (cats) => CategoryPicker(
                    label: 'Category',
                    categories: cats,
                    value: cats.where((c) => c.id == _categoryId).firstOrNull,
                    onChanged: (c) => setState(() => _categoryId = c.id),
                    validator: (_) => _categoryId == null ? 'Pick a category' : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _budgetController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(
                    labelText: 'Budget (optional)',
                    prefixText: '₹ ',
                    helperText: 'Leave empty if you are open to offers',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final value = double.tryParse(v.trim());
                    return (value == null || value < 0) ? 'Enter an amount in rupees' : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Details (optional)',
                    hintText: 'Condition, size, where you can pick it up...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded, size: 16),
          label: const Text('Post'),
        ),
      ],
    ));
  }
}
