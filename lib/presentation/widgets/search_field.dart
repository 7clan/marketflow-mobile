import 'package:flutter/material.dart';

/// The search input used on the search screen.
///
/// * text changes stream to the hosting screen (which forwards them to the
///   debounced search controller) — this field holds no state of its own;
/// * the clear affordance is a 48dp labeled icon button, only visible when
///   there is something to clear.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onSubmitted,
    this.hintText = 'Search products',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hintText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.isNotEmpty;
        return TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: hasText
                ? Semantics(
                    label: 'Clear search',
                    button: true,
                    child: IconButton(
                      tooltip: 'Clear search',
                      icon: Icon(
                        Icons.close_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}
