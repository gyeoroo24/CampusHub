import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/web_history_support.dart';

/// Compact dialog for selecting a custom price range (Min Price - Max Price) in Buy & Sell.
class CompactPriceRangePickerDialog extends StatefulWidget {
  final double? initialMin;
  final double? initialMax;

  const CompactPriceRangePickerDialog({
    super.key,
    this.initialMin,
    this.initialMax,
  });

  @override
  State<CompactPriceRangePickerDialog> createState() => _CompactPriceRangePickerDialogState();
}

class _CompactPriceRangePickerDialogState extends State<CompactPriceRangePickerDialog> {
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(
      text: widget.initialMin != null ? widget.initialMin!.toStringAsFixed(0) : '',
    );
    _maxController = TextEditingController(
      text: widget.initialMax != null ? widget.initialMax!.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _applyPreset(double? min, double? max) {
    setState(() {
      _minController.text = min != null ? min.toStringAsFixed(0) : '';
      _maxController.text = max != null ? max.toStringAsFixed(0) : '';
      _errorMessage = null;
    });
  }

  void _handleApply() {
    final minText = _minController.text.trim();
    final maxText = _maxController.text.trim();

    final min = minText.isNotEmpty ? double.tryParse(minText) : null;
    final max = maxText.isNotEmpty ? double.tryParse(maxText) : null;

    if (min != null && min < 0) {
      setState(() => _errorMessage = 'Min price cannot be negative');
      return;
    }
    if (max != null && max < 0) {
      setState(() => _errorMessage = 'Max price cannot be negative');
      return;
    }
    if (min != null && max != null && min > max) {
      setState(() => _errorMessage = 'Min price cannot exceed Max price');
      return;
    }

    Navigator.of(context).pop((min: min, max: max));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ModalHistoryWrapper(
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.currency_rupee_rounded, size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Custom Price Range',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quick Preset Chips
            const Text(
              'Quick Budget Presets',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildPresetChip('Under ₹500', null, 500),
                _buildPresetChip('Under ₹1,500', null, 1500),
                _buildPresetChip('Under ₹3,000', null, 3000),
                _buildPresetChip('₹3k - ₹10k', 3000, 10000),
                _buildPresetChip('Above ₹10k', 10000, null),
              ],
            ),
            const SizedBox(height: 18),

            // Input Fields Row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Min Price',
                      prefixText: '₹ ',
                      hintText: '0',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) {
                      if (_errorMessage != null) setState(() => _errorMessage = null);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                const Text('to', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Max Price',
                      prefixText: '₹ ',
                      hintText: 'Any',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) {
                      if (_errorMessage != null) setState(() => _errorMessage = null);
                    },
                  ),
                ),
              ],
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 14, color: Colors.red),
                  const SizedBox(width: 6),
                  Text(_errorMessage!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                ],
              ),
            ],
            const SizedBox(height: 20),

            // Dialog Actions
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop('CLEAR'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Reset'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _handleApply,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildPresetChip(String label, double? min, double? max) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      onPressed: () => _applyPreset(min, max),
    );
  }
}
