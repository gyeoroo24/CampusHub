import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
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

// ---------------------------------------------------------------- pre-placement talk
class PptFormDialog extends ConsumerStatefulWidget {
  final String companyId;
  final Ppt? ppt;

  const PptFormDialog({super.key, required this.companyId, this.ppt});

  @override
  ConsumerState<PptFormDialog> createState() => _PptFormDialogState();
}

class _PptFormDialogState extends ConsumerState<PptFormDialog> {
  late final _venue = TextEditingController(text: widget.ppt?.venue);
  late final _details = TextEditingController(text: widget.ppt?.details);
  late DateTime? _when = widget.ppt?.scheduledAt;

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
      title: widget.ppt == null ? 'Add pre-placement talk' : 'Edit pre-placement talk',
      onSave: () async {
        if (_when == null && _venue.text.trim().isEmpty && _details.text.trim().isEmpty) {
          throw Exception('Give at least the time, venue or details of the talk.');
        }
        await ref.read(placementRepositoryProvider).savePpt(
              pptId: widget.ppt?.id,
              companyId: widget.companyId,
              venue: _venue.text,
              details: _details.text,
              scheduledAt: _when,
            );
      },
      children: [
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
        TextFormField(controller: _venue, decoration: _field('Venue', hint: 'e.g. Faculty Hall'), maxLength: 200),
        TextFormField(controller: _details, decoration: _field('Details', hint: 'Roles, eligibility, agenda…'),
            minLines: 3, maxLines: 8),
      ],
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
      setState(() => _error = 'Paste the sheet first.');
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
                      'Copy the rows from your spreadsheet (header row included) and paste them below, or paste a '
                      'CSV export. Columns: Company, Student email, Role, and optionally Slot, in any order. '
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
