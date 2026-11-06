import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/config/server_config.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/file_picker.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';

/// What a shared file is. The keys are what the API stores.
const materialTags = <String, String>{
  'pyq': 'PYQs',
  'quiz': 'Quizzes',
  'assignment': 'Assignments',
  'notes': 'Notes',
  'slides': 'Slides',
  'lab': 'Labs',
  'solutions': 'Solutions',
  'cheat_sheet': 'Cheat sheets',
  'textbook': 'Textbooks',
  'project': 'Projects',
  'other': 'Other',
};

const _maxBytes = 100 * 1024 * 1024;
const _accept = '.pdf,.docx,.pptx,.xlsx,.txt,.csv,.md,.zip,.png,.jpg,.jpeg,.webp,.heic';

/// One file in a course's shared repository.
class CourseMaterial {
  final String id;
  final String title;
  final List<String> tags;
  final String? description;
  final String? fileName;
  final int? sizeBytes;
  final String? contentType;
  final bool held;
  final bool canEdit;
  final String downloadUrl;
  final String uploaderName;
  final DateTime createdAt;

  const CourseMaterial({
    required this.id,
    required this.title,
    this.tags = const [],
    this.description,
    this.fileName,
    this.sizeBytes,
    this.contentType,
    this.held = false,
    this.canEdit = false,
    required this.downloadUrl,
    required this.uploaderName,
    required this.createdAt,
  });

  factory CourseMaterial.fromJson(Map<String, dynamic> j) => CourseMaterial(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        tags: [for (final t in j['tags'] as List? ?? const []) '$t'],
        description: j['description'] as String?,
        fileName: j['file_name'] as String?,
        sizeBytes: (j['size_bytes'] as num?)?.toInt(),
        contentType: j['content_type'] as String?,
        held: j['held'] == true,
        canEdit: j['can_edit'] == true,
        downloadUrl: '${j['download_url'] ?? ''}',
        uploaderName: '${(j['uploaded_by'] as Map?)?['name'] ?? ''}',
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
      );

  /// "PDF", "Slides (PPTX)", "ZIP"... from the file's type.
  String get kindLabel {
    final ext = (fileName ?? '').contains('.') ? fileName!.split('.').last.toUpperCase() : '';
    return ext.isNotEmpty ? ext : switch (contentType ?? '') {
      'application/pdf' => 'PDF',
      'application/zip' => 'ZIP',
      _ => (contentType ?? 'FILE').split('/').last.toUpperCase(),
    };
  }
}

String formatBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';
}

IconData _iconFor(CourseMaterial m) => switch (m.kindLabel) {
      'PDF' => Icons.picture_as_pdf_outlined,
      'PPTX' => Icons.slideshow_outlined,
      'DOCX' || 'TXT' || 'MD' => Icons.description_outlined,
      'XLSX' || 'CSV' => Icons.table_chart_outlined,
      'ZIP' => Icons.folder_zip_outlined,
      'PNG' || 'JPG' || 'JPEG' || 'WEBP' || 'HEIC' => Icons.image_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

typedef MaterialQuery = ({String courseId, String? tag, String q});

final courseMaterialsProvider =
    FutureProvider.autoDispose.family<List<CourseMaterial>, MaterialQuery>((ref, query) async {
  ref.watch(currentUserProvider); // held files and "can edit" depend on who is viewing
  if (ref.watch(serverConfigProvider).useMockData) return const [];
  final r = await ref.watch(apiClientProvider).get(ApiEndpoints.courseMaterials(query.courseId), queryParameters: {
    'limit': 50,
    if (query.tag != null) 'tag': query.tag,
    if (query.q.trim().isNotEmpty) 'q': query.q.trim(),
  });
  return [for (final j in (r.data as Map)['items'] as List) CourseMaterial.fromJson(j as Map<String, dynamic>)];
});

/// The course's shared repository: filter by tag, search, share a file, download.
class CourseMaterialsTab extends ConsumerStatefulWidget {
  final String courseId;
  final String courseCode;

  const CourseMaterialsTab({super.key, required this.courseId, required this.courseCode});

  @override
  ConsumerState<CourseMaterialsTab> createState() => _CourseMaterialsTabState();
}

class _CourseMaterialsTabState extends ConsumerState<CourseMaterialsTab> {
  String? _tag;
  String _q = '';

  MaterialQuery get _query => (courseId: widget.courseId, tag: _tag, q: _q);

  Future<void> _share() async {
    final ok = await AuthDialog.ensureSignedIn(context, ref, title: 'Sign in to share materials',
        message: 'Sign in with your IISc email to share notes, PYQs and more with this course.');
    if (ok != true || !mounted) return;
    final shared = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MaterialUploadDialog(courseId: widget.courseId, courseCode: widget.courseCode),
    );
    if (shared == true) ref.invalidate(courseMaterialsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final materials = ref.watch(courseMaterialsProvider(_query));
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded, size: 18),
                              hintText: 'Search materials',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => setState(() => _q = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                          label: const Text('Share a file'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // One tag at a time; "All" (or the selected tag again) clears it.
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              showCheckmark: false,
                              label: const Text('All'),
                              selected: _tag == null,
                              onSelected: (_) => setState(() => _tag = null),
                            ),
                          ),
                          for (final e in materialTags.entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                showCheckmark: false,
                                label: Text(e.value),
                                selected: _tag == e.key,
                                onSelected: (_) => setState(() => _tag = _tag == e.key ? null : e.key),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Shared by students for ${widget.courseCode}. Up to 100 MB a file; every file is checked, '
                        'and programs or apps are refused.', style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  ],
                ),
              ),
            ),
            materials.when(
              skipLoadingOnReload: true,
              loading: () => const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))),
              error: (e, _) => SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.all(24), child: Text(errorText(e)))),
              data: (items) => items.isEmpty
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.folder_open_rounded, size: 48, color: theme.hintColor),
                            const SizedBox(height: 8),
                            Text(_tag == null && _q.isEmpty
                                ? 'Nothing shared yet. Be the first: PYQs, notes, slides…'
                                : 'Nothing matches.', style: TextStyle(color: theme.hintColor)),
                          ],
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 320,
                          mainAxisExtent: 196,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _MaterialCard(material: items[i], courseId: widget.courseId),
                          childCount: items.length,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialCard extends ConsumerWidget {
  final CourseMaterial material;
  final String courseId;

  const _MaterialCard({required this.material, required this.courseId});

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove “${material.title}”?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).delete(ApiEndpoints.material(material.id));
      ref.invalidate(courseMaterialsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final m = material;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: m.held ? Colors.orange : theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(m.downloadUrl), mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_iconFor(m), color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${m.kindLabel} · ${formatBytes(m.sizeBytes)}',
                        style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  ),
                  if (m.held)
                    Tooltip(
                      message: 'Waiting for a moderator: only you and the course moderators see it',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('In review',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                      ),
                    ),
                  if (m.canEdit)
                    PopupMenuButton<String>(
                      tooltip: 'Material options',
                      icon: const Icon(Icons.more_vert_rounded, size: 18),
                      onSelected: (v) async {
                        if (v == 'remove') return _remove(context, ref);
                        final saved = await showDialog<bool>(
                            context: context, builder: (_) => MaterialEditDialog(material: m));
                        if (saved == true) ref.invalidate(courseMaterialsProvider);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              if (m.description != null)
                Text(m.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final t in m.tags.take(3))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(materialTags[t] ?? t, style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 13, color: theme.hintColor),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text('${m.uploaderName} · ${DateTimeFormatter.timeAgo(m.createdAt)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: theme.hintColor)),
                  ),
                  Icon(Icons.download_rounded, size: 18, color: theme.colorScheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Share a file with a course: pick it, name it, tag it.
class MaterialUploadDialog extends ConsumerStatefulWidget {
  final String courseId;
  final String courseCode;

  const MaterialUploadDialog({super.key, required this.courseId, required this.courseCode});

  @override
  ConsumerState<MaterialUploadDialog> createState() => _MaterialUploadDialogState();
}

class _MaterialUploadDialogState extends ConsumerState<MaterialUploadDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final Set<String> _tags = {};
  PickedFile? _file;
  bool _busy = false;
  double? _progress;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final file = await pickFile(accept: _accept, maxBytes: _maxBytes);
      if (file == null) return;
      setState(() {
        _file = file;
        _error = null;
        if (_title.text.trim().isEmpty) {
          _title.text = file.name.contains('.') ? file.name.substring(0, file.name.lastIndexOf('.')) : file.name;
        }
      });
    } catch (e) {
      setState(() => _error = errorText(e));
    }
  }

  Future<void> _share() async {
    final file = _file;
    if (file == null) return setState(() => _error = 'Choose a file to share.');
    if (_title.text.trim().isEmpty) return setState(() => _error = 'Give it a title.');
    if (_tags.isEmpty) return setState(() => _error = 'Pick at least one tag, so people can find it.');
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final uploads = ref.read(uploadServiceProvider);
      final ticket = await uploads.getUploadTicket(
        kind: 'course_material',
        contentType: file.mimeType,
        sizeBytes: file.bytes.length,
        checksumSha256: UploadService.computeSha256Base64(file.bytes),
        courseId: widget.courseId,
      );
      await uploads.uploadToS3(ticket, file.bytes,
          onProgress: (sent, total) => setState(() => _progress = total > 0 ? sent / total : null));
      setState(() => _progress = null); // the server is checking the file now
      await ref.read(apiClientProvider).post(ApiEndpoints.courseMaterials(widget.courseId), data: {
        's3_key': ticket.s3Key,
        'title': _title.text.trim(),
        'tags': _tags.toList(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'file_name': file.name,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = _file;
    return AlertDialog(
      title: Text('Share with ${widget.courseCode}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (file == null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Choose a file (PDF, slides, docs, sheets, images, ZIP; up to 100 MB)'),
                )
              else
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${file.name} · ${formatBytes(file.bytes.length)}',
                            overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      TextButton(onPressed: _busy ? null : _pick, child: const Text('Change')),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                enabled: !_busy,
                maxLength: 200,
                decoration: const InputDecoration(
                    labelText: 'Title', hintText: 'e.g. Endsem 2025 with solutions', border: OutlineInputBorder()),
              ),
              Text('What is it?', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in materialTags.entries)
                    FilterChip(
                      label: Text(e.value),
                      selected: _tags.contains(e.key),
                      onSelected: _busy || (!_tags.contains(e.key) && _tags.length >= 5)
                          ? null
                          : (on) => setState(() => on ? _tags.add(e.key) : _tags.remove(e.key)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                enabled: !_busy,
                maxLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)', hintText: 'Which year, which professor, what it covers…',
                    border: OutlineInputBorder()),
              ),
              if (_busy) ...[
                const SizedBox(height: 4),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 4),
                Text(_progress == null ? 'Checking the file…' : 'Uploading…',
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _share, child: const Text('Share')),
      ],
    );
  }
}

/// Edit a shared file's title, tags or description (its uploader or a course moderator).
class MaterialEditDialog extends ConsumerStatefulWidget {
  final CourseMaterial material;

  const MaterialEditDialog({super.key, required this.material});

  @override
  ConsumerState<MaterialEditDialog> createState() => _MaterialEditDialogState();
}

class _MaterialEditDialogState extends ConsumerState<MaterialEditDialog> {
  late final _title = TextEditingController(text: widget.material.title);
  late final _description = TextEditingController(text: widget.material.description);
  late final Set<String> _tags = {...widget.material.tags};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).patch(ApiEndpoints.material(widget.material.id), data: {
        'title': _title.text.trim(),
        'tags': _tags.toList(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      });
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
      title: const Text('Edit material'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _title, maxLength: 200,
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in materialTags.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: _tags.contains(e.key),
                    onSelected: (on) => setState(() => on ? _tags.add(e.key) : _tags.remove(e.key)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _description, maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
