import 'package:flutter/material.dart';

/// Shared text field used by every MarketFlow form (auth, address).
///
/// Accessibility contract:
///
/// * validation failures render as Material `errorText` — screen readers
///   announce them automatically when the field is focused;
/// * the password visibility toggle is a labeled 48dp [IconButton];
/// * [autofillHints] are forwarded so password managers and keyboards can
///   fill the field;
/// * once a password has been revealed, a failing validation keeps it
///   visible so the user can correct it while reading the error.
class AppTextFormField extends StatefulWidget {
  const AppTextFormField({
    super.key,
    required this.label,
    required this.prefixIcon,
    this.controller,
    this.keyboardType,
    this.obscure = false,
    this.validator,
    this.autofillHints,
    this.helper,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.maxLines = 1,
  });

  final String label;
  final IconData prefixIcon;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final bool obscure;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;

  /// Supporting text under the field (e.g. demo credentials hint).
  final String? helper;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool autofocus;
  final bool enabled;
  final int? maxLines;

  @override
  State<AppTextFormField> createState() => _AppTextFormFieldState();
}

class _AppTextFormFieldState extends State<AppTextFormField> {
  bool _obscured = false;
  bool _hasBeenVisible = false;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscure;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      obscureText: _obscured,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      validator: (value) {
        final error = widget.validator?.call(value);
        if (error != null && widget.obscure && _hasBeenVisible) {
          // Keep the text visible while the user fixes the error.
          setState(() => _obscured = false);
        }
        return error;
      },
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.prefixIcon),
        helperText: widget.helper,
        helperMaxLines: 2,
        suffixIcon: widget.obscure
            ? Semantics(
                label: _obscured
                    ? 'Show ${widget.label.toLowerCase()}'
                    : 'Hide ${widget.label.toLowerCase()}',
                button: true,
                child: IconButton(
                  tooltip: _obscured ? 'Show' : 'Hide',
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: _obscured ? null : theme.colorScheme.primary,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscured = !_obscured;
                      _hasBeenVisible = true;
                    });
                  },
                ),
              )
            : null,
      ),
    );
  }
}
