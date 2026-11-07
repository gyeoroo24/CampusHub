import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/text_file_picker.dart';
import '../domain/placement_models.dart';
import 'similar_companies_review.dart';
import '../providers/placement_providers.dart';

/// Shared frame for the Placement Hub forms: a title, the fields, and Cancel / Save. [onSave] throws to
/// show its error under the fields; the dialog closes with what it returns (`true` if nothing) when it succeeds.
/// What an "Add companies" / "Add placement dates" form saved for, from Manage: checked for look-alikes.
class SavedCompany {
  final String id;
  const SavedCompany(this.id);
}

class _FormDialog extends StatefulWidget {
  final String title;
  final String saveLabel;
  final List<Widget> children;
  final Future<Object?> Function() onSave;
  final double width;
  final Widget? header;

  const _FormDialog({
    required this.title,
    required this.children,
    required this.onSave,
    this.saveLabel = 'Save',
    this.width = 480,
    this.header,
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
      final result = await widget.onSave();
      if (mounted) Navigator.pop(context, result ?? true);
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
                if (widget.header != null) ...[widget.header!, const SizedBox(height: 16)],
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
  final Widget? header;

  const CompanyFormDialog({super.key, this.company, this.header});

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
      title: widget.company == null ? 'Add companies' : 'Edit ${widget.company!.name}',
      header: widget.header,
      width: widget.header == null ? 480 : 640,
      onSave: () async {
        final saved = await ref.read(placementRepositoryProvider).saveCompany(
              companyId: widget.company?.id,
              name: _name.text.trim(),
              industry: _industry.text,
              website: _website.text,
              description: _description.text,
            );
        // From Manage: the new company, so the caller can check it for look-alike companies.
        return widget.header != null ? SavedCompany(saved.id) : null;
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
  late final _base = TextEditingController(text: widget.jd?.base);
  late final _skills = TextEditingController(text: widget.jd?.skills);
  late final _description = TextEditingController(text: widget.jd?.description);
  late int? _year = widget.jd == null ? DateTime.now().year : widget.jd!.placementYear;
  late String _jobType = widget.jd?.jobType ?? 'full_time';
  bool _removeFile = false;

  @override
  void dispose() {
    for (final c in [_role, _compensation, _base, _skills, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FormDialog(
      title: widget.jd == null ? 'Add a role' : 'Edit role',
      width: 560,
      onSave: () async {
        await ref.read(placementRepositoryProvider).saveJobDescription(
              jdId: widget.jd?.id,
              companyId: widget.companyId,
              roleTitle: _role.text.trim(),
              compensation: _compensation.text,
              description: _description.text,
              removeFile: _removeFile,
              placementYear: _year,
              jobType: _jobType,
              base: _base.text,
              skills: _skills.text,
            );
        return null;
      },
      children: [
        TextFormField(controller: _role, decoration: _field('Role', hint: 'e.g. Software Engineer'),
            validator: _required, maxLength: 200),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _year,
                decoration: _field('Season'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not set')),
                  for (var y = DateTime.now().year + 1; y >= DateTime.now().year - 6; y--)
                    DropdownMenuItem(value: y, child: Text('${y - 1}-${(y % 100).toString().padLeft(2, '0')}')),
                ],
                onChanged: (v) => setState(() => _year = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _jobType,
                decoration: _field('Type'),
                items: [
                  for (final e in JobDescription.jobTypeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _jobType = v ?? _jobType),
              ),
            ),
          ],
        ),
        TextFormField(
            controller: _compensation,
            decoration: _field('Compensation (CTC)', hint: 'e.g. ₹32 LPA, 24,00,000, 12-15 LPA',
                helper: 'Written as announced; the amount is read from it for the statistics'),
            maxLength: 200),
        TextFormField(controller: _base, decoration: _field('Base / fixed pay (optional)', hint: 'e.g. ₹18 LPA'),
            maxLength: 200),
        TextFormField(controller: _skills, decoration: _field('Skills (optional)', hint: 'e.g. Python, C++, ML'),
            minLines: 1, maxLines: 4),
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
  final Widget? header;

  const PptFormDialog({super.key, this.companyId, this.ppt, this.initialKind = PptKind.ppt, this.header});

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
      title: widget.ppt == null ? (widget.header == null ? 'Add a placement date' : 'Add placement dates')
          : 'Edit ${_kind.label.toLowerCase()}',
      header: widget.header,
      width: widget.header == null ? 480 : 640,
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
        return widget.header != null ? SavedCompany(companyId) : null;
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
        return null;
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
  CsvImportResult? _rolesResult;

  /// After a sheet import: reviewing the companies that look like the same one (null = not yet / not needed).
  bool _reviewing = false;
  int? _merged;

  /// What the sheet holds: selected students (hiring numbers), or roles with their compensation.
  bool _roles = false;
  bool _rolesChosen = false;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_detect);
  }

  /// Switches to "Roles & compensation" by itself when the header looks like it (CTC, position) and has no
  /// student emails, unless the moderator already picked.
  void _detect() {
    if (_rolesChosen) return;
    final head = _sheet.text.split(RegExp(r'\r?\n')).take(10).join(' ').toLowerCase();
    final roles = RegExp(r'ctc|compensation|stipend|jobtitle|job title|position').hasMatch(head) && !head.contains('email');
    if (roles != _roles) setState(() => _roles = roles);
  }

  @override
  void dispose() {
    _sheet.removeListener(_detect);
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
      final repo = ref.read(placementRepositoryProvider);
      if (_roles) {
        final result = await repo.importRoles(_sheet.text, placementYear: _year);
        ref.read(companiesPaginationProvider.notifier).loadInitial();
        ref.invalidate(placementOverviewProvider);
        if (mounted) setState(() => _rolesResult = result);
        return;
      }
      final result = await repo.importSheet(_year, _sheet.text);
      ref.read(companiesPaginationProvider.notifier).loadInitial();
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
    final rolesResult = _rolesResult;
    final done = result != null || rolesResult != null;
    return AlertDialog(
      title: const Text('Import a placement sheet'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: result != null && _reviewing
              ? SimilarCompaniesReview(
                  groups: result.similarCompanies,
                  onDone: (merged) => setState(() {
                    _reviewing = false;
                    _merged = merged;
                  }),
                )
              : result != null
              ? _ImportSummary(result: result, merged: _merged)
              : rolesResult != null
                  ? _CsvSummary(result: rolesResult)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, icon: Icon(Icons.groups_outlined, size: 18), label: Text('Selected students')),
                        ButtonSegment(value: true, icon: Icon(Icons.payments_outlined, size: 18), label: Text('Roles & compensation')),
                      ],
                      selected: {_roles},
                      onSelectionChanged: _busy ? null : (v) => setState(() {
                            _roles = v.first;
                            _rolesChosen = true;
                          }),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _roles
                          ? 'Roles each company offered and what they pay. Columns by name, in any order: Company and '
                              'Position (or Job title) are needed; Batch or Year, Overall CTC, Base, Job type, Description '
                              'and Skills are used when there. Compensation is kept as written and its amount read for the '
                              'statistics. Contact and comment columns are never imported.'
                          : 'Choose a CSV file, or copy the rows from your spreadsheet (header row included) and paste them '
                              'below. Columns: Company, Student email, Role, and optionally Slot, in any order. '
                              'Each student is one record per season: importing an edited sheet again updates it.',
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(_roles ? 'Season (rows without a Batch/Year)' : 'Placement season'),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: _year,
                          items: [
                            for (var y = DateTime.now().year + 1; y >= DateTime.now().year - 6; y--)
                              DropdownMenuItem(value: y, child: Text('${y - 1}-${(y % 100).toString().padLeft(2, '0')}')),
                          ],
                          onChanged: _busy ? null : (y) => setState(() => _year = y ?? _year),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _CsvSource(
                      controller: _sheet,
                      enabled: !_busy,
                      onFile: (name) {
                        final season = seasonFromFileName(name);
                        if (season != null) setState(() => _year = season);
                      },
                      hint: 'Slot\tCompany\tStudent email\tRole\n'
                          'Slot 2\tWalmart\tchandus@iisc.ac.in\tSoftware Engineer',
                      onChanged: () => setState(() => _error = null),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                    ],
                  ],
                ),
        ),
      ),
      actions: _reviewing
          ? null
          : result != null && result.similarCompanies.isNotEmpty && _merged == null
          ? [
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Skip review')),
              FilledButton.icon(
                onPressed: () => setState(() => _reviewing = true),
                icon: const Icon(Icons.merge_rounded, size: 16),
                label: Text('Review ${result.similarCompanies.length} similar compan'
                    '${result.similarCompanies.length == 1 ? 'y' : 'ies'}'),
              ),
            ]
          : done
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

  /// Groups merged in the review after the import (null if there was none yet).
  final int? merged;

  const _ImportSummary({required this.result, this.merged});

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
        if (result.similarCompanies.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(merged == null ? Icons.merge_rounded : Icons.check_circle_outline_rounded,
                    size: 18, color: Colors.amber.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    merged == null
                        ? '${result.similarCompanies.length} group${result.similarCompanies.length == 1 ? '' : 's'} of '
                            'companies look like the same company under different names, e.g. '
                            '${result.similarCompanies.first.companies.map((c) => '"${c.name}"').take(3).join(', ')}. '
                            'Review them to club them together.'
                        : merged == 0
                            ? 'Similar companies were kept as they are.'
                            : 'Merged $merged group${merged == 1 ? '' : 's'} of similar companies.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
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

/// Where an import's rows come from: a chosen CSV file (shown as a file card) or cells pasted in a text box.
class _CsvSource extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final VoidCallback onChanged;

  /// Called with the chosen file's name (to guess the season from it, say).
  final ValueChanged<String>? onFile;

  const _CsvSource(
      {required this.controller, required this.enabled, required this.hint, required this.onChanged, this.onFile});

  @override
  State<_CsvSource> createState() => _CsvSourceState();
}

class _CsvSourceState extends State<_CsvSource> {
  PickedTextFile? _file;
  String? _error;

  Future<void> _pick() async {
    try {
      final file = await pickTextFile();
      if (file == null || !mounted) return;
      if (file.text.trim().isEmpty) throw Exception('${file.name} is empty.');
      widget.controller.text = file.text;
      setState(() {
        _file = file;
        _error = null;
      });
      widget.onChanged();
      widget.onFile?.call(file.name);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  void _clear() {
    widget.controller.clear();
    setState(() => _file = null);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = _file;
    final error = _error == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
          );
    if (file != null) {
      final rows = file.text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).length;
      final kb = (file.text.length / 1024).toStringAsFixed(file.text.length < 10240 ? 1 : 0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.description_rounded, color: theme.colorScheme.primary, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(file.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                      Text('$rows lines · $kb KB · ready to import',
                          style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    ],
                  ),
                ),
                TextButton(onPressed: widget.enabled ? _pick : null, child: const Text('Change')),
                IconButton(
                  tooltip: 'Remove file',
                  onPressed: widget.enabled ? _clear : null,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          error,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canPickTextFiles) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
            onPressed: widget.enabled ? _pick : null,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Choose a CSV file'),
          ),
          error,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('or paste the rows', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: theme.hintColor)),
          ),
        ],
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          minLines: 6,
          maxLines: 12,
          onChanged: (_) => widget.onChanged(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(border: const OutlineInputBorder(), hintText: widget.hint),
        ),
      ],
    );
  }
}

/// The season a file's name points to: "FT 2025-26" or "2025_26" is the 2026 season, "data 2026" is 2026.
int? seasonFromFileName(String name) {
  final range = RegExp(r'(20\d\d)\s*[-_–]\s*(\d\d)(?!\d)').firstMatch(name);
  if (range != null) return 2000 + int.parse(range.group(2)!);
  final year = RegExp(r'(?<!\d)(20\d\d)(?!\d)').firstMatch(name);
  return year == null ? null : int.parse(year.group(1)!);
}

/// What a CSV import adds: companies, or dates on the placement schedule.
enum CsvImportKind {
  companies('Add companies', 'Name,Industry,Website,About\nIBM,Software and hardware,https://www.ibm.com/careers,'),
  schedule('Add placement dates',
      'Company,Type,Date,Time,Venue,Details\nGoogle,PPT,2026-11-20,17:30,Faculty Hall,Roles and process\n'
      'Google,OA,2026-11-22,18:00,HackerRank,90 minute coding test');

  final String title;
  final String sample;

  const CsvImportKind(this.title, this.sample);
}

/// Import a company list or a placement schedule from a CSV file (or pasted cells).
class CsvImportDialog extends ConsumerStatefulWidget {
  final CsvImportKind kind;
  final Widget? header;

  const CsvImportDialog({super.key, required this.kind, this.header});

  @override
  ConsumerState<CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends ConsumerState<CsvImportDialog> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;
  CsvImportResult? _result;
  bool _reviewing = false;
  int? _merged;

  /// The chosen file's name: "slot 2 interview schedule.csv" tells the server the rows are interviews.
  String? _fileName;

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
          : await repo.importSchedule(_text.text, fileName: _fileName);
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
        : 'Columns: Company (required), Type (PPT, OA, Interview or Other), Date, Time, Venue, Details; placement '
            'office sheets with columns like Test Date, Test Timings, Mode and Remarks work too. Dates like 2026-11-20, '
            '20/11/2026 or Oct 17th 2026, times like 18:00 or 6:00 pm, in India time. New companies are added. '
            'Importing the same file again updates the entries instead of repeating them.';
    return AlertDialog(
      title: Text(widget.kind.title),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: result != null && _reviewing
              ? SimilarCompaniesReview(
                  groups: result.similarCompanies,
                  onDone: (merged) => setState(() {
                    _reviewing = false;
                    _merged = merged;
                  }),
                )
              : result != null
              ? _CsvSummary(result: result, merged: _merged)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.header != null) ...[widget.header!, const SizedBox(height: 16)],
                    Text(help, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                    const SizedBox(height: 12),
                    _CsvSource(
                      controller: _text,
                      enabled: !_busy,
                      hint: widget.kind.sample,
                      onChanged: () => setState(() => _error = null),
                      onFile: (name) => _fileName = name,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                    ],
                  ],
                ),
        ),
      ),
      actions: _reviewing
          ? null
          : result != null && result.similarCompanies.isNotEmpty && _merged == null
          ? [
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Skip review')),
              FilledButton.icon(
                onPressed: () => setState(() => _reviewing = true),
                icon: const Icon(Icons.merge_rounded, size: 16),
                label: Text('Review ${result.similarCompanies.length} similar compan'
                    '${result.similarCompanies.length == 1 ? 'y' : 'ies'}'),
              ),
            ]
          : result != null
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

  /// After reviewing similar companies: how many groups were merged (0 = kept apart); null before.
  final int? merged;

  const _CsvSummary({required this.result, this.merged});

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
        if (result.kinds.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Saved as ${result.kinds.entries.map((e) => '${e.key.label} (${e.value})').join(', ')}.'
              '${result.pastRows > 0 ? ' ${result.pastRows} of these dates have passed: see Past in the Schedule tab.' : ''}',
              style: const TextStyle(fontSize: 13)),
        ],
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
        if (result.similarCompanies.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(merged == null ? Icons.merge_rounded : Icons.check_circle_outline_rounded,
                    size: 18, color: Colors.amber.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    merged == null
                        ? '${result.similarCompanies.length} group${result.similarCompanies.length == 1 ? '' : 's'} of '
                            'companies look like the same company under different names, e.g. '
                            '${result.similarCompanies.first.companies.map((c) => '"${c.name}"').take(3).join(', ')}. '
                            'Review them to club them together.'
                        : merged == 0
                            ? 'Similar companies were kept as they are.'
                            : 'Merged $merged group${merged == 1 ? '' : 's'} of similar companies.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
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

/// "Add companies" / "Add placement dates" from the Manage menu: one at a time in a form, or many from a file.
class AddOrImportDialog extends StatefulWidget {
  final CsvImportKind kind;

  const AddOrImportDialog({super.key, required this.kind});

  @override
  State<AddOrImportDialog> createState() => _AddOrImportDialogState();
}

class _AddOrImportDialogState extends State<AddOrImportDialog> {
  bool _fromFile = false;

  @override
  Widget build(BuildContext context) {
    final toggle = SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: false, icon: Icon(Icons.edit_note_rounded, size: 18), label: Text('Fill in a form')),
        ButtonSegment(value: true, icon: Icon(Icons.upload_file_rounded, size: 18), label: Text('Upload a CSV file')),
      ],
      selected: {_fromFile},
      onSelectionChanged: (s) => setState(() => _fromFile = s.first),
    );
    if (_fromFile) return CsvImportDialog(key: const ValueKey('file'), kind: widget.kind, header: toggle);
    return widget.kind == CsvImportKind.companies
        ? CompanyFormDialog(key: const ValueKey('form'), header: toggle)
        : PptFormDialog(key: const ValueKey('form'), header: toggle);
  }
}
