import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/error_text.dart';
import '../domain/campus_service.dart';
import '../providers/campus_services_providers.dart';
import 'campus_services_dialog.dart';

/// Admin tab: add, edit, hide or delete the landing page's campus services.
class CampusServicesAdminPanel extends ConsumerWidget {
  final bool isAdmin;

  const CampusServicesAdminPanel({super.key, required this.isAdmin});

  void _refresh(WidgetRef ref) {
    ref.invalidate(allCampusServicesProvider);
    ref.invalidate(campusServicesProvider);
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      _refresh(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (!isAdmin) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Only the admin can change the campus services list.', textAlign: TextAlign.center),
        ),
      );
    }
    final servicesAsync = ref.watch(allCampusServicesProvider);
    final repo = ref.read(campusServicesRepositoryProvider);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Links and phone numbers shown under "Campus services" in the app bar. '
                'Hidden ones stay here but are not shown to students.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () async {
                final created = await showDialog<CampusService>(
                  context: context,
                  builder: (_) => const CampusServiceEditDialog(),
                );
                if (created != null && context.mounted) {
                  await _run(context, ref, () => repo.createService(created));
                }
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add service'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        servicesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(errorText(e)),
          data: (services) => Column(
            children: [
              for (final s in services)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
                  ),
                  child: ListTile(
                    leading: Icon(campusServiceIcon(s.category),
                        color: s.isActive ? theme.colorScheme.primary : theme.hintColor),
                    title: Text(
                      s.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: s.isActive ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    subtitle: Text(
                      [s.category.label, if (s.phone != null) s.phone!, if (s.url != null) s.url!].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: s.isActive ? 'Shown to students' : 'Hidden',
                          child: Switch(
                            value: s.isActive,
                            onChanged: (v) => _run(context, ref, () => repo.updateService(s.copyWith(isActive: v))),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () async {
                            final edited = await showDialog<CampusService>(
                              context: context,
                              builder: (_) => CampusServiceEditDialog(service: s),
                            );
                            if (edited != null && context.mounted) {
                              await _run(context, ref, () => repo.updateService(edited));
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red.shade700),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('Delete “${s.name}”?'),
                                content: const Text('To keep it for later, switch it off instead.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true && context.mounted) {
                              await _run(context, ref, () => repo.deleteService(s.id));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Add or edit one service. Returns the edited service (not yet saved).
class CampusServiceEditDialog extends StatefulWidget {
  final CampusService? service;

  const CampusServiceEditDialog({super.key, this.service});

  @override
  State<CampusServiceEditDialog> createState() => _CampusServiceEditDialogState();
}

class _CampusServiceEditDialogState extends State<CampusServiceEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.service?.name);
  late final _description = TextEditingController(text: widget.service?.description);
  late final _url = TextEditingController(text: widget.service?.url);
  late final _phone = TextEditingController(text: widget.service?.phone);
  late final _order = TextEditingController(text: '${widget.service?.sortOrder ?? 100}');
  late CampusServiceCategory _category = widget.service?.category ?? CampusServiceCategory.health;

  @override
  void dispose() {
    for (final c in [_name, _description, _url, _phone, _order]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      CampusService(
        id: widget.service?.id ?? '',
        name: _name.text.trim(),
        description: _description.text.trim(),
        category: _category,
        url: _url.text.trim(),
        phone: _phone.text.trim(),
        sortOrder: int.tryParse(_order.text.trim()) ?? 100,
        isActive: widget.service?.isActive ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label, {String? hint}) =>
        InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true);

    return AlertDialog(
      title: Text(widget.service == null ? 'Add campus service' : 'Edit campus service'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  decoration: field('Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                DropdownButtonFormField<CampusServiceCategory>(
                  initialValue: _category,
                  decoration: field('Category'),
                  items: [
                    for (final c in CampusServiceCategory.values) DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _description, maxLength: 300, decoration: field('Description')),
                TextFormField(
                  controller: _url,
                  decoration: field('Link', hint: 'https://...'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty && _phone.text.trim().isEmpty) return 'Give a link or a phone number';
                    if (value.isNotEmpty && !RegExp(r'^https?://\S+$').hasMatch(value)) {
                      return 'Start with http:// or https://';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: field('Phone', hint: '080-2293-4444'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isNotEmpty && !RegExp(r'^\+?[0-9 -]{3,20}$').hasMatch(value)) {
                      return 'Digits, spaces and dashes only';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _order,
                  keyboardType: TextInputType.number,
                  decoration: field('Order', hint: 'Lower comes first in its group'),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    return (n == null || n < 0 || n > 1000) ? '0 to 1000' : null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
