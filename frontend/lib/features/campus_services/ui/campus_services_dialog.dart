import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/web_history_support.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/error_text.dart';
import '../domain/campus_service.dart';
import '../providers/campus_services_providers.dart';

/// App-bar button that opens the campus services card (visible to everyone, guests included).
class CampusServicesButton extends StatelessWidget {
  const CampusServicesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Campus services: Health Centre, Wellness Centre, grievances',
      icon: const Icon(Icons.health_and_safety_outlined, size: 21),
      onPressed: () => showDialog(context: context, builder: (_) => const CampusServicesDialog()),
    );
  }
}

/// Opens a link in the browser, or dials a phone number; copies it if neither works.
Future<void> openServiceTarget(BuildContext context, {String? url, String? phone}) async {
  final value = url ?? phone!;
  final uri = url != null ? Uri.parse(url) : Uri(scheme: 'tel', path: phone!.replaceAll(RegExp(r'[^0-9+]'), ''));
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!opened) {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open it here, so it's copied: $value"), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

IconData campusServiceIcon(CampusServiceCategory category) {
  switch (category) {
    case CampusServiceCategory.health:
      return Icons.local_hospital_outlined;
    case CampusServiceCategory.wellbeing:
      return Icons.self_improvement_rounded;
    case CampusServiceCategory.grievance:
      return Icons.gavel_rounded;
    case CampusServiceCategory.safety:
      return Icons.shield_outlined;
    case CampusServiceCategory.other:
      return Icons.info_outline_rounded;
  }
}

class CampusServicesDialog extends ConsumerWidget {
  const CampusServicesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(campusServicesProvider);
    final theme = Theme.of(context);

    return ModalHistoryWrapper(
      child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(Icons.health_and_safety_rounded, color: Colors.teal),
          SizedBox(width: 10),
          Expanded(child: Text('Campus services', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 480,
        child: servicesAsync.when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text(errorText(e)),
          data: (services) {
            if (services.isEmpty) {
              return Text('No services listed yet.', style: TextStyle(color: theme.hintColor));
            }
            final groups = <CampusServiceCategory, List<CampusService>>{};
            for (final s in services) {
              groups.putIfAbsent(s.category, () => []).add(s);
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                    child: Text(
                      entry.key.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                  for (final s in entry.value) _ServiceTile(service: s),
                ],
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ));
  }
}

class _ServiceTile extends StatelessWidget {
  final CampusService service;

  const _ServiceTile({required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmergency = service.url == null && service.phone != null && service.category == CampusServiceCategory.health;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: isEmergency ? Colors.red.withValues(alpha: 0.08) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Icon(campusServiceIcon(service.category),
                color: isEmergency ? Colors.red.shade700 : theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  if ((service.description ?? '').isNotEmpty)
                    Text(service.description!, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                ],
              ),
            ),
            if (service.phone != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: isEmergency ? Colors.red.shade700 : null),
                onPressed: () => openServiceTarget(context, phone: service.phone),
                icon: const Icon(Icons.call_rounded, size: 16),
                label: Text(service.phone!, style: const TextStyle(fontSize: 12)),
              ),
            if (service.url != null)
              IconButton(
                tooltip: 'Open ${service.url}',
                onPressed: () => openServiceTarget(context, url: service.url),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
