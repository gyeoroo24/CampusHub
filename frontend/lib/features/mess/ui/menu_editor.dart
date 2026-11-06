import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/file_picker.dart';
import '../../auth/providers/auth_providers.dart';
import '../mess_models.dart';

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Reads a menu copied from a spreadsheet (or a CSV): one row per weekday with Breakfast / Lunch / Snacks /
/// Dinner columns, or the other way round (one row per meal, a column per weekday). Returns the cells it found.
Map<(int, String), String> parseMenuTable(String text) {
  final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) return {};
  final sep = lines.first.contains('\t') ? '\t' : ',';
  List<String> cells(String line) => _splitRow(line, sep);
  int? weekdayOf(String s) {
    final t = s.trim().toLowerCase();
    if (t.length < 3) return null;
    for (var i = 0; i < 7; i++) {
      if (weekdayLabels[i].toLowerCase().startsWith(t.substring(0, 3))) return i + 1;
    }
    return null;
  }

  String? mealOf(String s) {
    final t = s.trim().toLowerCase();
    if (t.startsWith('break')) return 'breakfast';
    if (t.startsWith('lunch')) return 'lunch';
    if (t.startsWith('snack') || t.contains('tiffin') || t.contains('tea')) return 'snacks';
    if (t.startsWith('dinner') || t.startsWith('supper')) return 'dinner';
    return null;
  }

  final header = cells(lines.first);
  final result = <(int, String), String>{};
  final mealColumns = {for (var i = 0; i < header.length; i++) if (mealOf(header[i]) != null) i: mealOf(header[i])!};
  final dayColumns = {for (var i = 0; i < header.length; i++) if (weekdayOf(header[i]) != null) i: weekdayOf(header[i])!};
  if (mealColumns.length >= dayColumns.length && mealColumns.isNotEmpty) {
    for (final line in lines.skip(1)) {
      final row = cells(line);
      final day = row.isEmpty ? null : weekdayOf(row.first);
      if (day == null) continue;
      for (final e in mealColumns.entries) {
        if (e.key < row.length && row[e.key].trim().isNotEmpty) result[(day, e.value)] = _clean(row[e.key]);
      }
    }
  } else if (dayColumns.isNotEmpty) {
    for (final line in lines.skip(1)) {
      final row = cells(line);
      final meal = row.isEmpty ? null : mealOf(row.first);
      if (meal == null) continue;
      for (final e in dayColumns.entries) {
        if (e.key < row.length && row[e.key].trim().isNotEmpty) result[(e.value, meal)] = _clean(row[e.key]);
      }
    }
  }
  return result;
}

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Splits one line of CSV (with "quoted, cells") or tab-separated text.
List<String> _splitRow(String line, String sep) {
  if (sep == '\t') return line.split('\t').map((c) => c.replaceAll('"', '')).toList();
  final out = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == ',' && !quoted) {
      out.add(cell.toString());
      cell.clear();
    } else {
      cell.write(ch);
    }
  }
  out.add(cell.toString());
  return out;
}

/// Post or edit a mess menu in two steps.
///
///  1. Fill in: the mess (picked or typed; a new name adds the mess), the dates, and the menu. Attaching
///     the PDF or photo uploads it and reads the meals out of it (POST /mess-menus/extract), prefilling
///     every cell; pasting a spreadsheet table or typing works too.
///  2. Review: the whole week in one table, to check what was read before posting.
class MenuEditorDialog extends ConsumerStatefulWidget {
  /// The mess, or null to choose (or add) one by name.
  final Mess? mess;
  final MessMenu? menu;
  final DateTime? suggestedFrom;
  final List<Mess> messes;

  const MenuEditorDialog({super.key, this.mess, this.menu, this.suggestedFrom, this.messes = const []});

  @override
  ConsumerState<MenuEditorDialog> createState() => _MenuEditorDialogState();
}

class _MenuEditorDialogState extends ConsumerState<MenuEditorDialog> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 7, vsync: this);
  late final Map<(int, String), TextEditingController> _cells = {
    for (var d = 1; d <= 7; d++)
      for (final m in meals) (d, m): TextEditingController(text: widget.menu?.items[(d, m)]),
  };
  late final _notes = TextEditingController(text: widget.menu?.notes);
  late final _name = TextEditingController(text: widget.mess?.name);
  late DateTimeRange _range = widget.menu != null
      ? DateTimeRange(start: widget.menu!.validFrom, end: widget.menu!.validTo)
      : _defaultRange();
  PickedFile? _file;
  String? _fileKey;            // the attached file, already uploaded
  bool _removeFile = false;
  bool _busy = false;
  bool _reading = false;
  bool _reviewing = false;
  String? _readSummary;
  List<String> _warnings = const [];
  String? _error;

  DateTimeRange _defaultRange() {
    // Today (or the day after the last menu) to the end of that month.
    final now = DateTime.now();
    final start = widget.suggestedFrom ?? DateTime(now.year, now.month, now.day);
    return DateTimeRange(start: start, end: DateTime(start.year, start.month + 1, 0));
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _cells.values) {
      c.dispose();
    }
    _notes.dispose();
    _name.dispose();
    super.dispose();
  }

  int get _filled => _cells.values.where((c) => c.text.trim().isNotEmpty).length;

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      helpText: 'Dates this menu covers',
    );
    if (picked != null) setState(() => _range = picked);
  }

  /// Attach a file: upload it, then read the meals out of it to prefill the form.
  Future<void> _pickFile() async {
    PickedFile? file;
    try {
      file = await pickFile(accept: 'application/pdf,image/*');
    } catch (e) {
      setState(() => _error = errorText(e));
      return;
    }
    if (file == null) return;
    setState(() {
      _file = file;
      _fileKey = null;
      _removeFile = false;
      _reading = true;
      _readSummary = null;
      _warnings = const [];
      _error = null;
    });
    try {
      final key = await ref.read(uploadServiceProvider).uploadPhoto(bytes: file.bytes, kind: 'mess_menu',
          contentType: file.mimeType);
      _fileKey = key;
      final r = await ref.read(apiClientProvider).post(ApiEndpoints.messMenuExtract, data: {'file_s3_key': key});
      final data = r.data as Map<String, dynamic>;
      final items = data['items'] as List? ?? const [];
      if (!mounted) return;
      setState(() {
        if (items.isNotEmpty) {
          for (final c in _cells.values) {
            c.clear();
          }
          for (final i in items) {
            _cells[((i['weekday'] as num).toInt(), '${i['meal']}')]?.text = '${i['items']}';
          }
        }
        final notes = data['notes'] as String?;
        if (notes != null && _notes.text.trim().isEmpty) _notes.text = notes;
        final name = data['mess_name'] as String?;
        if (name != null && widget.mess == null && _name.text.trim().isEmpty) _name.text = name;
        // The month in the title, unless it's already over (then it's an old menu being reposted).
        final month = data['month'] == null ? null : DateTime.parse('${data['month']}');
        final now = DateTime.now();
        if (month != null && widget.menu == null && !DateTime(month.year, month.month + 1, 0).isBefore(now)) {
          _range = DateTimeRange(start: month.isBefore(now) ? DateTime(now.year, now.month, now.day) : month,
              end: DateTime(month.year, month.month + 1, 0));
        }
        _warnings = [for (final w in data['warnings'] as List? ?? const []) '$w'];
        _readSummary = items.isEmpty
            ? null
            : 'Read $_filled of 28 meals from ${file!.name}. Words can be misread: check each day before posting.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _paste() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _PasteDialog());
    if (text == null) return;
    final parsed = parseMenuTable(text);
    if (parsed.isEmpty) {
      setState(() => _error = "Couldn't find the meals in that table. It needs a header row with Breakfast, Lunch, "
          'Snacks and Dinner, and a row per weekday (or the other way round).');
      return;
    }
    setState(() {
      for (final e in parsed.entries) {
        _cells[e.key]!.text = e.value;
      }
      _error = null;
    });
  }

  List<Map<String, dynamic>> get _items => [
        for (final e in _cells.entries)
          if (e.value.text.trim().isNotEmpty) {'weekday': e.key.$1, 'meal': e.key.$2, 'items': e.value.text.trim()},
      ];

  /// Step 1 -> 2: check there's something to post, then show the whole week for review.
  void _review() {
    final hasFile = _fileKey != null || (widget.menu?.fileUrl != null && !_removeFile);
    if (widget.mess == null && _name.text.trim().isEmpty) {
      setState(() => _error = 'Which mess is this? Type its name, e.g. C Mess.');
      return;
    }
    if (_items.isEmpty && !hasFile) {
      setState(() => _error = 'Attach the menu as a PDF or photo, or type in at least one meal.');
      return;
    }
    setState(() {
      _error = null;
      _reviewing = true;
    });
  }

  Future<void> _post() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'valid_from': _isoDate(_range.start),
        'valid_to': _isoDate(_range.end),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'items': _items,
        if (_fileKey != null) 'file_s3_key': _fileKey,
        if (_fileKey == null && _removeFile) 'file_s3_key': null,
      };
      final api = ref.read(apiClientProvider);
      if (widget.menu != null) {
        await api.patch(ApiEndpoints.messMenu(widget.menu!.id), data: body);
      } else if (widget.mess != null) {
        await api.post(ApiEndpoints.messMenus(widget.mess!.id), data: body);
      } else {
        await api.post(ApiEndpoints.messMenusByName, data: {...body, 'mess_name': _name.text.trim()});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _reviewing = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _messName => widget.mess?.name ?? (_name.text.trim().isEmpty ? 'a mess' : _name.text.trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.menu != null
        ? 'Edit ${widget.mess?.name ?? ''} menu'
        : (_reviewing ? 'Check $_messName\'s menu' : (widget.mess == null ? 'Upload a mess menu' : 'Post ${widget.mess!.name}\'s menu'));
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 760,
        height: 580,
        child: _reviewing ? _reviewTable(theme) : _form(theme),
      ),
      actions: _reviewing
          ? [
              TextButton(onPressed: _busy ? null : () => setState(() => _reviewing = false), child: const Text('Back to edit')),
              FilledButton(
                onPressed: _busy ? null : _post,
                child: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.menu == null ? 'Looks right, post it' : 'Looks right, save'),
              ),
            ]
          : [
              TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(onPressed: _busy || _reading ? null : _review, child: const Text('Review')),
            ],
    );
  }

  Widget _form(ThemeData theme) {
    final hasOldFile = widget.menu?.fileUrl != null && !_removeFile && _file == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.mess == null) ...[
          Autocomplete<String>(
            initialValue: _name.value,
            optionsBuilder: (v) => widget.messes
                .map((m) => m.name)
                .where((n) => n.toLowerCase().contains(v.text.trim().toLowerCase())),
            onSelected: (n) => _name.text = n,
            fieldViewBuilder: (context, controller, focus, _) {
              // Keep our controller in step with the field (a file can fill the name in).
              if (controller.text != _name.text && !focus.hasFocus) controller.text = _name.text;
              return TextField(
                controller: controller,
                focusNode: focus,
                onChanged: (v) => _name.text = v,
                decoration: const InputDecoration(
                  labelText: 'Mess',
                  hintText: 'e.g. C Mess. A new name adds the mess',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickDates,
              icon: const Icon(Icons.date_range_rounded, size: 18),
              label: Text('${DateTimeFormatter.shortDate(_range.start)} – ${DateTimeFormatter.shortDate(_range.end)}'),
            ),
            if (_file != null)
              InputChip(
                avatar: Icon(_file!.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined, size: 18),
                label: Text(_file!.name, overflow: TextOverflow.ellipsis),
                onDeleted: _busy || _reading
                    ? null
                    : () => setState(() {
                          _file = null;
                          _fileKey = null;
                          _readSummary = null;
                          _warnings = const [];
                        }),
              )
            else if (hasOldFile)
              InputChip(
                avatar: Icon(widget.menu!.fileType == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                    size: 18),
                label: const Text('Current menu file'),
                onDeleted: _busy ? null : () => setState(() => _removeFile = true),
              )
            else if (canPickFiles)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _pickFile,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Upload the menu (PDF or photo)'),
              ),
            TextButton.icon(
              onPressed: _busy || _reading ? null : _paste,
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: const Text('Paste a table'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_reading)
          const Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Reading the meals from the file… (a few seconds)'),
          ])
        else if (_readSummary != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(_readSummary!, style: const TextStyle(fontSize: 13))),
            ]),
          )
        else
          Text('Upload the menu and its meals are read in for you to check, or paste a table or type them. '
              'They repeat every week of these dates. $_filled of 28 meals filled.',
              style: TextStyle(fontSize: 12, color: theme.hintColor)),
        for (final w in _warnings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(w, style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
          ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final d in weekdayLabels) Tab(text: d.substring(0, 3))],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              for (var d = 1; d <= 7; d++)
                ListView(
                  padding: const EdgeInsets.only(top: 12),
                  children: [
                    for (final m in meals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: _cells[(d, m)],
                          enabled: !_busy && !_reading,
                          minLines: 1,
                          maxLines: 3,
                          maxLength: 1000,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: '${weekdayLabels[d - 1]} ${mealLabels[m]!.toLowerCase()}',
                            border: const OutlineInputBorder(),
                            counterText: '',
                          ),
                        ),
                      ),
                    if (d == 7)
                      TextField(
                        controller: _notes,
                        enabled: !_busy,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'e.g. Daily: tea, milk, bread and jam at breakfast',
                          border: OutlineInputBorder(),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
          ),
      ],
    );
  }

  /// Step 2: the whole week at a glance. Empty cells are flagged so nothing is missed.
  Widget _reviewTable(ThemeData theme) {
    final border = BorderSide(color: theme.dividerColor.withValues(alpha: 0.5));
    Widget cell(String text, {bool header = false, bool missing = false}) => Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            missing ? '— missing' : text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: header ? FontWeight.bold : FontWeight.normal,
              color: missing ? Colors.orange.shade800 : null,
            ),
          ),
        );
    final hasFile = _fileKey != null || (widget.menu?.fileUrl != null && !_removeFile);
    return ListView(
      children: [
        Text('$_messName · ${DateTimeFormatter.shortDate(_range.start)} – ${DateTimeFormatter.shortDate(_range.end)}'
            '${hasFile ? ' · with the menu file' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(_filled == 0
            ? 'No meals typed in: followers get “see today\'s menu” alerts that point to the file.'
            : 'Check every cell against the menu. Go back to fix anything misread.',
            style: TextStyle(fontSize: 12, color: theme.hintColor)),
        const SizedBox(height: 10),
        if (_filled > 0)
          Table(
            border: TableBorder(horizontalInside: border, verticalInside: border, top: border, bottom: border,
                left: border, right: border),
            columnWidths: const {0: FixedColumnWidth(84)},
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              TableRow(
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
                children: [cell('', header: true), for (final m in meals) cell(mealLabels[m]!, header: true)],
              ),
              for (var d = 1; d <= 7; d++)
                TableRow(children: [
                  cell(weekdayLabels[d - 1], header: true),
                  for (final m in meals)
                    cell(_cells[(d, m)]!.text.trim(), missing: _cells[(d, m)]!.text.trim().isEmpty),
                ]),
            ],
          ),
        if (_notes.text.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Notes', style: theme.textTheme.titleSmall),
          Text(_notes.text.trim(), style: const TextStyle(fontSize: 12)),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
          ),
      ],
    );
  }
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste the menu table'),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: _text,
          autofocus: true,
          minLines: 8,
          maxLines: 14,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Day\tBreakfast\tLunch\tSnacks\tDinner\n'
                'Monday\tPoha, Coconut chutney\tChapati, Matta rice, Sambar\tMasala vada\tFried rice, Paneer\n'
                'Tuesday\t…',
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('Fill in the menu')),
      ],
    );
  }
}

/// Add a mess or change its name and meal times.
class MessFormDialog extends ConsumerStatefulWidget {
  final Mess? mess;

  const MessFormDialog({super.key, this.mess});

  @override
  ConsumerState<MessFormDialog> createState() => _MessFormDialogState();
}

class _MessFormDialogState extends ConsumerState<MessFormDialog> {
  late final _name = TextEditingController(text: widget.mess?.name);
  late final Map<String, TimeOfDay> _times = {
    for (final m in meals)
      m: () {
        final (h, min) = parseClock(widget.mess?.mealTimes[m] ??
            const {'breakfast': '07:30', 'lunch': '12:30', 'snacks': '16:45', 'dinner': '19:30'}[m]!);
        return TimeOfDay(hour: h, minute: min);
      }(),
  };
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the mess a name, e.g. C Mess.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {'name': _name.text.trim(), 'meal_times': {for (final e in _times.entries) e.key: _hhmm(e.value)}};
    try {
      final api = ref.read(apiClientProvider);
      if (widget.mess == null) {
        await api.post(ApiEndpoints.messes, data: body);
      } else {
        await api.patch(ApiEndpoints.mess(widget.mess!.id), data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.mess == null ? 'Add a mess' : 'Edit ${widget.mess!.name}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.mess == null,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. C Mess', border: OutlineInputBorder()),
            ),
            const Text('When each meal starts. Followers get the menu 30 minutes before.'),
            for (final m in meals)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(mealLabels[m]!),
                trailing: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final t = await showTimePicker(context: context, initialTime: _times[m]!);
                          if (t != null) setState(() => _times[m] = t);
                        },
                  child: Text(_times[m]!.format(context)),
                ),
              ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(widget.mess == null ? 'Add' : 'Save')),
      ],
    );
  }
}
