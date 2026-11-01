import 'package:flutter/material.dart';
import '../models/category_ref.dart';

/// Category dropdown for the post / report / Wanted forms.
///
/// - Type to jump: with the field focused, typing "e" highlights the first category starting with
///   "e", then "el" the first starting with "el", like a native <select>. If nothing starts with the
///   text, the first category containing it is highlighted. Enter picks the highlighted one.
/// - The open menu shows about [visibleEntries] categories at a time and scrolls for the rest, so it
///   no longer fills the whole dialog.
/// - [addNewLabel] adds a last entry ([addNew], id -1) for "+ Add New Category...".
class CategoryPicker extends StatefulWidget {
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
    this.label = 'Category *',
    this.addNewLabel,
    this.validator,
  });

  final List<CategoryRef> categories;
  final CategoryRef? value;
  final ValueChanged<CategoryRef> onChanged;
  final String label;
  final String? addNewLabel;
  final FormFieldValidator<CategoryRef>? validator;

  static const addNew = CategoryRef(id: -1, name: '+ Add New Category...');
  static const visibleEntries = 5;
  static const _entryHeight = 48.0;

  /// The entry to highlight for what the user has typed: prefix match first, then substring.
  static int? prefixSearch(List<DropdownMenuEntry<CategoryRef>> entries, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    final starts = entries.indexWhere((e) => e.label.toLowerCase().startsWith(q));
    if (starts != -1) return starts;
    final contains = entries.indexWhere((e) => e.label.toLowerCase().contains(q));
    return contains == -1 ? null : contains;
  }

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      // Like a native <select>: typing replaces the shown name instead of appending to it.
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    } else {
      // Typed something that matched nothing and clicked away: show the chosen category again.
      _controller.text = widget.value?.name ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final c in widget.categories) DropdownMenuEntry<CategoryRef>(value: c, label: c.name),
      if (widget.addNewLabel != null)
        DropdownMenuEntry<CategoryRef>(
          value: CategoryPicker.addNew,
          label: widget.addNewLabel!,
          labelWidget: Text(widget.addNewLabel!, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
    ];
    return FormField<CategoryRef>(
      // Rebuilt when the value changes from outside (e.g. a suggested category is applied).
      key: ValueKey(widget.value?.id),
      initialValue: widget.value,
      validator: widget.validator,
      builder: (state) => DropdownMenu<CategoryRef>(
        controller: _controller,
        focusNode: _focus,
        initialSelection: widget.value,
        expandedInsets: EdgeInsets.zero,
        menuHeight: CategoryPicker.visibleEntries * CategoryPicker._entryHeight + 16,
        label: Text(widget.label),
        requestFocusOnTap: true,
        enableSearch: true,
        enableFilter: false,
        searchCallback: CategoryPicker.prefixSearch,
        errorText: state.errorText,
        dropdownMenuEntries: entries,
        onSelected: (picked) {
          if (picked == null) return;
          state.didChange(picked);
          widget.onChanged(picked);
        },
      ),
    );
  }
}
