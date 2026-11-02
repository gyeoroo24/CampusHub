import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/text_file_picker.dart';
import '../domain/placement_models.dart';
import '../providers/placement_providers.dart';

/// Shared frame for the Placement Hub forms: a title, the fields, and Cancel / Save. [onSave] throws to
/// show its error under the fields; the dialog closes with `true` when it succeeds.
class _FormDialog extends StatefulWidget {
  final String title;
  final String saveLabel;
  final List<Widget> children;
  final Future<void> Function() onSave;
  final double width;

  const _FormDialog({
    required this.title,
    required this.children,
    required this.onSave,
    this.saveLabel = 'Save',
    this.width = 480,
  });

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave();
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
      title: Text(widget.title),
      content: SizedBox(
        width: widget.width,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in widget.children) ...[child, const SizedBox(height: 12)],
                if (_error != null)
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.saveLabel),
        ),
      ],
    );
  }
}

String? _required(String? value) => (value == null || value.trim().isEmpty) ? 'Required' : null;

InputDecoration _field(String label, {String? hint, String? helper}) =>
    InputDecoration(labelText: label, hintText: hint, helperText: helper, border: const OutlineInputBorder());

// ---------------------------------------------------------------- company
class CompanyFormDialog extends ConsumerStatefulWidget {
  final Company? company;

  const CompanyFormDialog({super.key, this.company});

  @override
  ConsumerState<CompanyFormDialog> createState() => _CompanyFormDialogState();
}

class _CompanyFormDialogState extends ConsumerState<CompanyFormDialog> {
  late final _name = TextEditingController(text: widget.company?.name);
  late final _industry = TextEditingController(text: widget.company?.industry);
  late final _website = TextEditingController(text: widget.company?.website);
  late final _description = TextEditingController(text: widget.company?.description);

  @override
  void dispose() {
    for (final c in [_name, _industry, _website, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FormDialog(
      title: widget.company == null ? 'Add a company' : 'Edit ${widget.company!.name}',
      onSave: () async {
        await ref.read(placementRepositoryProvider).saveCompany(
              companyId: widget.company?.id,
              name: _name.text.trim(),
              industry: _industry.text,
              website: _website.text,
              description: _description.text,
            );
      },
      children: [
        TextFormField(controller: _name, decoration: _field('Company name'), validator: _required, maxLength: 120),
        TextFormField(controller: _industry, decoration: _field('Industry', hint: 'e.g. Software, Finance'), maxLength: 80),
        TextFormField(
          controller: _website,
          decoration: _field('Careers page', hint: 'https://'),
          validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^https?://', caseSensitive: false).hasMatch(v!.trim())
              ? null
              : 'Start with https://',
        ),
        TextFormField(controller: _description, decoration: _field('About the company'), minLines: 3, maxLines: 6),
      ],
    );
  }
}

// ---------------------------------------------------------------- job description
class JobDescriptionFormDialog extends ConsumerStatefulWidget {
  final String companyId;
  final JobDescription? jd;

  const JobDescriptionFormDialog({super.key, required this.companyId, this.jd});

  @override
  ConsumerState<JobDescriptionFormDialog> createState() => _JobDescriptionFormDialogState();
}

class _JobDescriptionFormDialogState extends ConsumerState<JobDescriptionFormDialog> {
  late final _role = TextEditingController(text: widget.jd?.roleTitle);
  late final _compensation = TextEditingController(text: widget.jd?.compensation);
  late final _description = TextEditingController(text: widget.jd?.description);
  bool _removeFile = false;

  @override
  void dispose() {
    for (final c in [_role, _compensation, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FormDialog(
      title: widget.jd == null ? 'Add a job description' : 'Edit job description',
      width: 560,
      onSave: () async {
        await ref.read(placementRepositoryProvider).saveJobDescription(
              jdId: widget.jd?.id,
              companyId: widget.companyId,
              roleTitle: _role.text.trim(),
              compensation: _compensation.text,
              description: _description.text,
              removeFile: _removeFile,
            );
      },
      children: [
        TextFormField(controller: _role, decoration: _field('Role', hint: 'e.g. Software Engineer'),
            validator: _required, maxLength: 200),
        TextFormField(controller: _compensation, decoration: _field('Compensation', hint: 'e.g. ₹32 LPA'), maxLength: 200),
        TextFormField(controller: _description, decoration: _field('Job description', hint: 'Responsibilities, '
            'eligibility, process…'), minLines: 6, maxLines: 14),
        if (widget.jd?.fileUrl != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _removeFile,
            onChanged: (v) => setState(() => _removeFile = v ?? false),
            title: const Text('Remove the attached JD file'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- placement schedule
/// Add or edit a date on the placement schedule: a pre-placement talk, online test, interviews or other.
/// Without [companyId] the moderator picks the company first (from the Placement Hub page).
class PptFormDialog extends ConsumerStatefulWidget {
  final String? companyId;
  final Ppt? ppt;
  final PptKind initialKind;

  const PptFormDialog({super.key, this.companyId, this.ppt, this.initialKind = PptKind.ppt});

  @override
  ConsumerState<PptFormDialog> createState() => _PptFormDialogState();
}

class _PptFormDialogState extends ConsumerState<PptFormDialog> {
  late final _venue = TextEditingController(text: widget.ppt?.venue);
  late final _details = TextEditingController(text: widget.ppt?.details);
  late DateTime? _when = widget.ppt?.scheduledAt;
  late PptKind _kind = widget.ppt?.kind ?? widget.initialKind;
  Company? _company;

  @override
  void dispose() {
    _venue.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _when ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when ?? DateTime(2000, 1, 1, 17)));
    if (time == null) return;
    setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    return _FormDialog(
      title: widget.ppt == null ? 'Add a placement date' : 'Edit ${_kind.label.toLowerCase()}',
      onSave: () async {
        final companyId = widget.companyId ?? _company?.id;
        if (companyId == null) throw Exception('Pick the company.');
        if (_when == null && _venue.text.trim().isEmpty && _details.text.trim().isEmpty) {
          throw Exception('Give at least the time, venue or details.');
        }
        await ref.read(placementRepositoryProvider).savePpt(
              pptId: widget.ppt?.id,
              companyId: companyId,
              kind: _kind,
              venue: _venue.text,
              details: _details.text,
              scheduledAt: _when,
            );
      },
      children: [
        if (widget.companyId == null)
          _CompanyPicker(onPicked: (c) => setState(() => _company = c)),
        SegmentedButton<PptKind>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [for (final k in PptKind.values) ButtonSegment(value: k, label: Text(k.short))],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                _when == null ? 'Date not announced yet' : DateTimeFormatter.fullDateTime(_when!),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (_when != null)
              IconButton(tooltip: 'Clear date', onPressed: () => setState(() => _when = null),
                  icon: const Icon(Icons.close_rounded, size: 18)),
            OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.event_rounded, size: 16),
                label: Text(_when == null ? 'Set date' : 'Change')),
          ],
        ),
        TextFormField(controller: _venue, decoration: _field('Venue or link', hint: 'e.g. Faculty Hall, HackerRank'),
            maxLength: 200),
        TextFormField(controller: _details, decoration: _field('Details', hint: 'Roles, eligibility, duration, agenda…'),
            minLines: 3, maxLines: 8),
      ],
    );
  }
}

/// Type-ahead over every company (the list API is paged, so it searches as you type).
class _CompanyPicker extends ConsumerWidget {
  final ValueChanged<Company?> onPicked;

  const _CompanyPicker({required this.onPicked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Autocomplete<Company>(
      displayStringForOption: (c) => c.name,
      optionsBuilder: (value) async {
        onPicked(null);
        return ref.read(placementRepositoryProvider).fetchCompanies(query: value.text.trim(), limit: 20);
      },
      onSelected: onPicked,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        decoration: _field('Company', hint: 'Start typing a name', helper: 'Add the company first if it isn\'t listed'),
        validator: _required,
      ),
    );
  }
}

// ---------------------------------------------------------------- interview experience
class InterviewFormDialog extends ConsumerStatefulWidget {
  final String companyId;
  final String companyName;
  final InterviewExperience? interview;

  const InterviewFormDialog({super.key, required this.companyId, required this.companyName, this.interview});

  @override
  ConsumerState<InterviewFormDialog> createState() => _InterviewFormDialogState();
}

class _InterviewFormDialogState extends ConsumerState<InterviewFormDialog> {
  late final _role = TextEditingController(text: widget.interview?.roleTitle);
  late final _year = TextEditingController(
      text: '${widget.interview?.placementYear ?? (widget.interview == null ? DateTime.now().year : '')}');
  late final _content = TextEditingController(text: widget.interview?.content);
  late bool _anonymous = widget.interview?.isAnonymous ?? false;

  @override
  void dispose() {
    for (final c in [_role, _year, _content]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(placementRepositoryProvider);
    return _FormDialog(
      title: widget.interview == null ? 'Share your ${widget.companyName} interview' : 'Edit interview experience',
      saveLabel: widget.interview == null ? 'Post' : 'Save',
      width: 600,
      onSave: () async {
        final year = int.tryParse(_year.text.trim());
        if (widget.interview == null) {
          await repo.postInterview(widget.companyId, roleTitle: _role.text.trim(), placementYear: year,
              content: _content.text.trim(), anonymous: _anonymous);
        } else {
          await repo.updateInterview(widget.interview!.id, roleTitle: _role.text.trim(), placementYear: year,
              content: _content.text.trim(), anonymous: _anonymous);
        }
      },
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(controller: _role, decoration: _field('Role', hint: 'e.g. SDE'),
                  validator: _required),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _year,
                keyboardType: TextInputType.number,
                decoration: _field('Season', hint: 'e.g. 2026'),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return null;
                  final year = int.tryParse(v!.trim());
                  return year == null || year < 2000 || year > 2100 ? 'A year, e.g. 2026' : null;
                },
              ),
            ),
          ],
        ),
        TextFormField(
          controller: _content,
          decoration: _field('Your experience',
              hint: 'Rounds, questions, what they looked for, tips for juniors…',
              helper: "Don't share questions you agreed to keep confidential."),
          minLines: 8,
          maxLines: 18,
          validator: _required,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _anonymous,
          onChanged: (v) => setState(() => _anonymous = v),
          title: const Text('Post anonymously'),
          subtitle: const Text('Your name is hidden from everyone else.'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- bulk import (FR-17)
class ImportSheetDialog extends ConsumerStatefulWidget {
  const ImportSheetDialog({super.key});

  @override
  ConsumerState<ImportSheetDialog> createState() => _ImportSheetDialogState();
}

class _ImportSheetDialogState extends ConsumerState<ImportSheetDialog> {
  final _sheet = TextEditingController();
  int _year = DateTime.now().year;
  bool _busy = false;
  String? _error;
  ImportResult? _result;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_sheet.text.trim().isEmpty) {
      setState(() => _error = 'Choose a CSV file or paste the sheet first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(placementRepositoryProvider).importSheet(_year, _sheet.text);
      ref.invalidate(companiesProvider);
      ref.invalidate(placementOverviewProvider);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return AlertDialog(
      title: const Text('Import a placement sheet'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: result != null
              ? _ImportSummary(result: result)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Choose a CSV file, or copy the rows from your spreadsheet (header row included) and paste them '
                      'below. Columns: Company, Student email, Role, and optionally Slot, in any order. '
                      'Each student is one record per season: importing an edited sheet again updates it.',
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Placement season'),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: _year,
                          items: [
                            for (var y = DateTime.now().year + 1; y >= DateTime.now().year - 6; y--)
                              DropdownMenuItem(value: y, child: Text('$y')),
                          ],
                          onChanged: _busy ? null : (y) => setState(() => _year = y ?? _year),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _CsvFileButton(enabled: !_busy, onPicked: (text) => setState(() => _sheet.text = text)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _sheet,
                      enabled: !_busy,
                      minLines: 10,
                      maxLines: 16,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Slot\tCompany\tStudent email\tRole\n'
                            'Slot 2\tWalmart\tchandus@iisc.ac.in\tSoftware Engineer',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                    ],
                  ],
                ),
        ),
      ),
      actions: result != null
          ? [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done'))]
          : [
              TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: _busy ? null : _import,
                icon: _busy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_rounded, size: 16),
                label: const Text('Import'),
              ),
            ],
    );
  }
}

class _ImportSummary extends StatelessWidget {
  final ImportResult result;

  const _ImportSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String label, int value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${result.rowsTotal} rows read for the ${result.placementYear} season.',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          stat('Added', result.rowsCreated, Colors.teal),
          const SizedBox(width: 8),
          stat('Updated', result.rowsUpdated, Colors.blue),
          const SizedBox(width: 8),
          stat('Rejected', result.rowsRejected, result.rowsRejected == 0 ? Colors.grey : Colors.deepOrange),
        ]),
        if (result.companiesCreated.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('New companies: ${result.companiesCreated.join(', ')}', style: const TextStyle(fontSize: 13)),
        ],
        if (result.rejectedRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Fix these rows and import again (good rows were already saved):',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.error)),
          const SizedBox(height: 4),
          for (final r in result.rejectedRows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('Line ${r.line}: ${r.reason}', style: const TextStyle(fontSize: 12)),
            ),
        ],
      ],
    );
  }
}

/// "Choose CSV file": reads the file into the text box, where it can be checked before importing.
class _CsvFileButton extends StatefulWidget {
  final bool enabled;
  final ValueChanged<String> onPicked;

  const _CsvFileButton({required this.enabled, required this.onPicked});

  @override
  State<_CsvFileButton> createState() => _CsvFileButtonState();
}

class _CsvFileButtonState extends State<_CsvFileButton> {
  String? _fileName;
  String? _error;

  Future<void> _pick() async {
    try {
      final file = await pickTextFile();
      if (file == null || !mounted) return;
      widget.onPicked(file.text);
      setState(() {
        _fileName = file.name;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canPickTextFiles) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: widget.enabled ? _pick : null,
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('Choose CSV file'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _error ?? (_fileName == null ? 'or paste below' : 'Loaded $_fileName. Check it below, then import.'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: _error != null ? theme.colorScheme.error : theme.hintColor),
          ),
        ),
      ],
    );
  }
}

/// What a CSV import adds: companies, or dates on the placement schedule.
enum CsvImportKind {
  companies('Import companies', 'Name,Industry,Website,About\nIBM,Software and hardware,https://www.ibm.com/careers,'),
  schedule('Import placement dates',
      'Company,Type,Date,Time,Venue,Details\nGoogle,PPT,2026-11-20,17:30,Faculty Hall,Roles and process\n'
      'Google,OA,2026-11-22,18:00,HackerRank,90 minute coding test');

  final String title;
  final String sample;

  const CsvImportKind(this.title, this.sample);
}

/// Import a company list or a placement schedule from a CSV file (or pasted cells).
class CsvImportDialog extends ConsumerStatefulWidget {
  final CsvImportKind kind;

  const CsvImportDialog({super.key, required this.kind});

  @override
  ConsumerState<CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends ConsumerState<CsvImportDialog> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;
  CsvImportResult? _result;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Choose a CSV file or paste the rows first.');
      return;
    }
    final repo = ref.read(placementRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = widget.kind == CsvImportKind.companies
          ? await repo.importCompanies(_text.text)
          : await repo.importSchedule(_text.text);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final help = widget.kind == CsvImportKind.companies
        ? 'Columns: Name (required), Industry, Website, About, in any order. A company that already exists '
            '(same name) is updated with the cells you fill in.'
        : 'Columns: Company (required), Type (PPT, OA, Interview or Other), Date, Time, Venue, Details. Dates like '
            '2026-11-20 or 20/11/2026, times like 18:00 or 6:00 pm, in India time. New companies are added. '
            'Importing the same file again updates the entries instead of repeating them.';
    return AlertDialog(
      title: Text(widget.kind.title),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: result != null
              ? _CsvSummary(result: result)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(help, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    const SizedBox(height: 12),
                    _CsvFileButton(enabled: !_busy, onPicked: (text) => setState(() => _text.text = text)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _text,
                      enabled: !_busy,
                      minLines: 8,
                      maxLines: 14,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      decoration: InputDecoration(border: const OutlineInputBorder(), hintText: widget.kind.sample),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                    ],
                  ],
                ),
        ),
      ),
      actions: result != null
          ? [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done'))]
          : [
              TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: _busy ? null : _import,
                icon: _busy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_rounded, size: 16),
                label: const Text('Import'),
              ),
            ],
    );
  }
}

class _CsvSummary extends StatelessWidget {
  final CsvImportResult result;

  const _CsvSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String label, int value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${result.rowsTotal} rows read.', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          stat('Added', result.rowsCreated, Colors.teal),
          const SizedBox(width: 8),
          stat('Updated', result.rowsUpdated, Colors.blue),
          const SizedBox(width: 8),
          stat('Rejected', result.rowsRejected, result.rowsRejected == 0 ? Colors.grey : Colors.deepOrange),
        ]),
        if (result.companiesCreated.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('New companies: ${result.companiesCreated.join(', ')}', style: const TextStyle(fontSize: 13)),
        ],
        if (result.rejectedRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Fix these rows and import again (good rows were already saved):',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.error)),
          const SizedBox(height: 4),
          for (final r in result.rejectedRows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('Line ${r.line}: ${r.reason}', style: const TextStyle(fontSize: 12)),
            ),
        ],
      ],
    );
  }
}
