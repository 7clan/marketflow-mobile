import 'package:flutter/material.dart';

/// Quantity stepper shared by the product detail and cart line rows.
///
/// * 48dp +/- buttons with explicit Semantics labels;
/// * clamped bounds: minus disables at [min], plus disables at [max] —
///   [onChanged] therefore never receives an out-of-bounds value.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.onChanged,
    this.enabled = true,
    this.compact = false,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;
  final bool enabled;

  /// `true` for dense contexts (cart rows) — smaller value typography.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDecrement = enabled && value > min;
    final canIncrement = enabled && value < max;

    return Semantics(
      label: 'Quantity: $value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(
            context: context,
            icon: Icons.remove_rounded,
            semanticsLabel: 'Decrease quantity to ${value - 1}',
            tooltip: 'Decrease quantity',
            onPressed: canDecrement ? () => onChanged?.call(value - 1) : null,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$value',
              style:
                  (compact
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _stepButton(
            context: context,
            icon: Icons.add_rounded,
            semanticsLabel: 'Increase quantity to ${value + 1}',
            tooltip: 'Increase quantity',
            onPressed: canIncrement ? () => onChanged?.call(value + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required BuildContext context,
    required IconData icon,
    required String semanticsLabel,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: onPressed != null,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        visualDensity: compact ? VisualDensity.compact : null,
      ),
    );
  }
}
