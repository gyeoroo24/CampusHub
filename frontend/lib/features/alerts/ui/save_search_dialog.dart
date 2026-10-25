import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/error_text.dart';
import '../../auth/ui/auth_dialog.dart';
import '../domain/alerts_models.dart';
import '../providers/alerts_providers.dart';

/// "Save this search": keeps the current feed filters and alerts the user about new matches.
class SaveSearchDialog extends ConsumerStatefulWidget {
  final SavedSearchModule module;
  final String? query;
  final int? categoryId;
  final String? categoryName;
  final double? minPrice;
  final double? maxPrice;

  /// Set when the feed has a category picked that the server doesn't know (e.g. a preset chip
  /// with no listings yet): the search is saved without it, and the dialog says so.
  final String? unsavedCategoryName;

  const SaveSearchDialog({
    super.key,
    required this.module,
    this.query,
    this.categoryId,
    this.categoryName,
    this.minPrice,
    this.maxPrice,
    this.unsavedCategoryName,
  });

  /// Asks the guest to sign in first, then shows the dialog.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required SavedSearchModule module,
    String? query,
    int? categoryId,
    String? categoryName,
    double? minPrice,
    double? maxPrice,
    String? unsavedCategoryName,
  }) async {
    final signedIn = await AuthDialog.ensureSignedIn(
      context,
      ref,
      title: 'Sign In to Save Searches',
      message: 'Signed-in IISc members get an alert when something new matches their saved search.',
    );
    if (!signedIn || !context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => SaveSearchDialog(
        module: module,
        query: query,
        categoryId: categoryId,
        categoryName: categoryName,
        minPrice: minPrice,
        maxPrice: maxPrice,
        unsavedCategoryName: unsavedCategoryName,
      ),
    );
  }

  @override
  ConsumerState<SaveSearchDialog> createState() => _SaveSearchDialogState();
}

class _SaveSearchDialogState extends ConsumerState<SaveSearchDialog> {
  late final TextEditingController _nameController;
  bool _alertsEnabled = true;
  bool _saving = false;
  String? _error;

  String get _summary => describeFilters(
        query: widget.query,
        categoryName: widget.categoryName,
        minPrice: widget.minPrice,
        maxPrice: widget.maxPrice,
      );

  @override
  void initState() {
    super.initState();
    final summary = _summary == 'Everything new'
        ? 'All new ${widget.module.label.toLowerCase()}'
        : _summary.replaceAll('“', '').replaceAll('”', '');
    _nameController = TextEditingController(text: summary.length > 80 ? summary.substring(0, 80) : summary);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the search a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(alertsRepositoryProvider).createSavedSearch(
            module: widget.module,
            name: name,
            query: widget.query,
            categoryId: widget.categoryId,
            minPrice: widget.minPrice,
            maxPrice: widget.maxPrice,
            alertsEnabled: _alertsEnabled,
          );
      ref.invalidate(savedSearchesProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_alertsEnabled
              ? 'Saved “$name”. We\'ll notify you when something new matches.'
              : 'Saved “$name”.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        _saving = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final watches = widget.module == SavedSearchModule.buySell ? 'new listings' : 'new found-item reports';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.notification_add_outlined),
          SizedBox(width: 10),
          Text('Save this search', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Watches $watches matching:', style: TextStyle(fontSize: 12, color: theme.hintColor)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_summary, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (widget.unsavedCategoryName != null) ...[
              const SizedBox(height: 6),
              Text(
                'The “${widget.unsavedCategoryName}” category has no posts on the server yet, '
                'so this search covers every category.',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              maxLength: 80,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _save(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _alertsEnabled,
              onChanged: (v) => setState(() => _alertsEnabled = v),
              title: const Text('Notify me about new matches', style: TextStyle(fontSize: 13)),
              subtitle: Text('You can turn this off later', style: TextStyle(fontSize: 11, color: theme.hintColor)),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.bookmark_add_outlined, size: 16),
          label: const Text('Save'),
        ),
      ],
    );
  }
}
