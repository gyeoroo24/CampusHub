import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/config/server_config.dart';
import '../../../core/utils/contact_actions.dart';
import '../../../core/utils/error_text.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/ui/auth_dialog.dart';
import '../../messages/ui/messages_screen.dart' show openChatAbout;
import '../domain/placement_models.dart';

/// A senior who got an offer at a company: from an imported placement sheet (the last two seasons), or added
/// by a Placement Hub moderator (off-campus offers, PPOs, alumni).
class Senior {
  final String id;
  final bool fromSheet;
  final String name;
  final String email;
  final String? phone;
  final String? userId;
  final String? roleTitle;
  final int placementYear;
  final String offerType;
  final String? slot;
  final String? note;
  final bool hidden;

  const Senior({
    required this.id,
    required this.fromSheet,
    required this.name,
    required this.email,
    this.phone,
    this.userId,
    this.roleTitle,
    required this.placementYear,
    required this.offerType,
    this.slot,
    this.note,
    this.hidden = false,
  });

  factory Senior.fromJson(Map<String, dynamic> j) => Senior(
        id: '${j['id']}',
        fromSheet: j['source'] == 'placement_sheet',
        name: '${j['name'] ?? ''}',
        email: '${j['email'] ?? ''}',
        phone: j['phone'] as String?,
        userId: j['user_id'] as String?,
        roleTitle: j['role_title'] as String?,
        placementYear: (j['placement_year'] as num?)?.toInt() ?? 0,
        offerType: '${j['offer_type'] ?? 'on_campus'}',
        slot: j['slot'] as String?,
        note: j['note'] as String?,
        hidden: j['hidden'] == true,
      );

  String get offerLabel => offerLabels[offerType] ?? offerType;
}

const offerLabels = {'on_campus': 'On campus', 'off_campus': 'Off campus', 'ppo': 'PPO', 'internship': 'Internship'};

/// Seniors for a company; empty for guests and in mock mode (there is no mock version).
final companySeniorsProvider = FutureProvider.autoDispose.family<List<Senior>, String>((ref, companyId) async {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.isGuest || ref.watch(serverConfigProvider).useMockData) return const [];
  final res = await ref.watch(apiClientProvider).get(ApiEndpoints.companySeniors(companyId));
  return [for (final j in res.data as List) Senior.fromJson(j as Map<String, dynamic>)];
});

/// "Talk to seniors" on a company's page: people who got an offer here, with chat (when they're on CampusHub),
/// email and phone. Moderators add and edit seniors, and hide placement-sheet students.
class CompanySeniorsSection extends ConsumerStatefulWidget {
  final Company company;

  const CompanySeniorsSection({super.key, required this.company});

  @override
  ConsumerState<CompanySeniorsSection> createState() => _CompanySeniorsSectionState();
}

class _CompanySeniorsSectionState extends ConsumerState<CompanySeniorsSection> {
  static const _collapsedCount = 4;
  bool _showAll = false;

  Future<void> _edit([Senior? senior]) async {
    final saved = await showDialog<bool>(
        context: context, builder: (_) => SeniorFormDialog(companyId: widget.company.id, senior: senior));
    if (saved == true) ref.invalidate(companySeniorsProvider(widget.company.id));
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(companySeniorsProvider(widget.company.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final guest = user == null || user.isGuest;
    final manage = widget.company.viewerCanManage;
    final api = ref.read(apiClientProvider);
    final seniorsAsync = ref.watch(companySeniorsProvider(widget.company.id));

    Widget body;
    if (guest) {
      body = Row(
        children: [
          Expanded(
            child: Text('Sign in to see seniors who got an offer here and message them.',
                style: TextStyle(fontSize: 13, color: theme.hintColor)),
          ),
          TextButton(onPressed: () => AuthDialog.ensureSignedIn(context, ref), child: const Text('Sign in')),
        ],
      );
    } else {
      body = seniorsAsync.when(
        loading: () => const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        error: (e, _) => Text(errorText(e), style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
        data: (seniors) {
          if (seniors.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Nobody from the last two seasons is listed yet.',
                  style: TextStyle(color: theme.hintColor, fontSize: 13)),
            );
          }
          final shown = _showAll ? seniors : seniors.take(_collapsedCount).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in shown)
                _SeniorTile(
                  senior: s,
                  isMe: s.userId != null && s.userId == user.id,
                  menu: !manage
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: 'Manage',
                          onSelected: (v) => switch (v) {
                            'edit' => _edit(s),
                            'delete' => _act(() => api.delete(ApiEndpoints.senior(s.id))),
                            _ => _act(() => api.put(ApiEndpoints.placementRecordContactHidden(s.id),
                                data: {'hidden': !s.hidden})),
                          },
                          itemBuilder: (_) => s.fromSheet
                              ? [PopupMenuItem(value: 'hide', child: Text(s.hidden ? 'Show in the list' : 'Hide from the list'))]
                              : const [
                                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  PopupMenuItem(value: 'delete', child: Text('Remove')),
                                ],
                        ),
                ),
              if (seniors.length > _collapsedCount)
                TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll ? 'Show fewer' : 'Show all ${seniors.length}'),
                ),
            ],
          );
        },
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Talk to seniors',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (manage)
                  TextButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.person_add_alt_rounded, size: 16),
                    label: const Text('Add'),
                  ),
              ],
            ),
            Text('Got an offer here in the last two seasons. Ask them about the process, the role and the team.',
                style: TextStyle(fontSize: 12, color: theme.hintColor)),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}

class _SeniorTile extends ConsumerWidget {
  final Senior senior;
  final bool isMe;
  final Widget? menu;

  const _SeniorTile({required this.senior, required this.isMe, this.menu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = senior;
    final phone = s.phone?.trim() ?? '';
    final canChat = s.userId != null && !isMe;
    final subtitle = [
      if (s.roleTitle != null) s.roleTitle!,
      '${s.offerLabel} · ${s.placementYear}',
    ].join(' · ');
    Widget small(IconData icon, String tooltip, VoidCallback onPressed) => SizedBox(
          width: 36,
          height: 32,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Tooltip(message: tooltip, child: Icon(icon, size: 16)),
          ),
        );
    void email() => contactBy(context, email: s.email, subject: 'Your offer at a company, from CampusHub');
    return Opacity(
      opacity: s.hidden ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(s.name.isEmpty ? '?' : s.name.characters.first.toUpperCase(),
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isMe ? '${s.name} (you)' : s.name + (s.hidden ? ' · hidden' : ''),
                      style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: theme.hintColor), overflow: TextOverflow.ellipsis),
                  if (s.note != null)
                    Text(s.note!, style: TextStyle(fontSize: 12, color: theme.hintColor, fontStyle: FontStyle.italic),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (!isMe) ...[
              // Chat first; people without a CampusHub account can only be emailed (or called).
              if (canChat)
                FilledButton.tonalIcon(
                  onPressed: () => openChatAbout(context, ref, {'user_id': s.userId!}),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                  label: const Text('Message'),
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                )
              else
                Tooltip(
                  message: 'Not on CampusHub yet, so email them',
                  child: FilledButton.tonalIcon(
                    onPressed: email,
                    icon: const Icon(Icons.email_outlined, size: 15),
                    label: const Text('Email'),
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ),
              if (canChat) ...[const SizedBox(width: 6), small(Icons.email_outlined, 'Email ${s.email}', email)],
              if (phone.isNotEmpty) ...[
                const SizedBox(width: 6),
                small(Icons.phone_outlined, 'Call $phone', () => contactBy(context, phone: phone)),
              ],
            ],
            if (menu != null) menu!,
          ],
        ),
      ),
    );
  }
}

/// Add or edit a senior (Placement Hub moderators).
class SeniorFormDialog extends ConsumerStatefulWidget {
  final String companyId;
  final Senior? senior;

  const SeniorFormDialog({super.key, required this.companyId, this.senior});

  @override
  ConsumerState<SeniorFormDialog> createState() => _SeniorFormDialogState();
}

class _SeniorFormDialogState extends ConsumerState<SeniorFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.senior?.name);
  late final _email = TextEditingController(text: widget.senior?.email);
  late final _phone = TextEditingController(text: widget.senior?.phone);
  late final _role = TextEditingController(text: widget.senior?.roleTitle);
  late final _note = TextEditingController(text: widget.senior?.note);
  late int _year = widget.senior?.placementYear ?? DateTime.now().year;
  late String _offer = widget.senior?.offerType ?? 'off_campus';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _role, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.replaceAll(RegExp(r'[\s-]'), ''),
      'role_title': _role.text.trim().isEmpty ? null : _role.text.trim(),
      'placement_year': _year,
      'offer_type': _offer,
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      final api = ref.read(apiClientProvider);
      if (widget.senior == null) {
        await api.post(ApiEndpoints.companySeniors(widget.companyId), data: body);
      } else {
        await api.patch(ApiEndpoints.senior(widget.senior!.id), data: body);
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
    final now = DateTime.now().year;
    InputDecoration field(String label, {String? hint}) =>
        InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder());
    return AlertDialog(
      title: Text(widget.senior == null ? 'Add a senior' : 'Edit ${widget.senior!.name}'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: field('Name'),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: field('Email', hint: 'Their IISc or personal email'),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'An email address',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: field('Phone (optional)', hint: '+91 98765 43210'),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (v) {
                    final p = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
                    return p.isEmpty || RegExp(r'^\+?[0-9]{10,15}$').hasMatch(p) ? null : '10 to 15 digits';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _role, decoration: field('Role (optional)', hint: 'e.g. Research Scientist')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _offer,
                        decoration: field('Offer'),
                        items: [
                          for (final e in offerLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setState(() => _offer = v ?? _offer),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _year,
                        decoration: field('Season'),
                        items: [
                          for (var y = now + 1; y >= now - 3; y--) DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                        onChanged: (v) => setState(() => _year = v ?? _year),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _note, maxLength: 500, decoration: field('Note (optional)',
                    hint: 'e.g. Off-campus through a referral; happy to help with the OA')),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(widget.senior == null ? 'Add' : 'Save')),
      ],
    );
  }
}
