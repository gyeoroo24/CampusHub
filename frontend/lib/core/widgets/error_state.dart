import 'package:flutter/material.dart';

/// "Couldn't load" panel with a Retry button, so a server problem never looks like an empty feed.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool compact;

  const ErrorState({super.key, required this.message, required this.onRetry, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: compact ? 36 : 52, color: theme.colorScheme.error),
            const SizedBox(height: 10),
            Text("Couldn't load this right now", style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: theme.hintColor)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
