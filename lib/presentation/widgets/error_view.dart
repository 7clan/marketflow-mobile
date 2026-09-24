import 'package:flutter/material.dart';

/// Full-area error state: icon, title, mapped [message] and a retry button.
///
/// The message always comes from an [AppException] (already user-safe copy);
/// widgets never render raw `toString()` of exceptions.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.title = 'Something went wrong',
    this.retryLabel = 'Try again',
    this.compact = false,
  });

  /// User-safe message (e.g. `AppException.message`).
  final String message;

  /// Retry callback; hides the button when `null`.
  final VoidCallback? onRetry;

  /// Heading above [message].
  final String title;

  /// Label of the retry button.
  final String retryLabel;

  /// `true` for in-list footers (less breathing room).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.wifi_off_rounded,
          size: compact ? 32 : 48,
          color: theme.colorScheme.error,
          semanticLabel: 'Error',
        ),
        SizedBox(height: compact ? 8 : 16),
        Text(
          title,
          style:
              (compact
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.titleMedium)
                  ?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        if (onRetry != null) ...[
          SizedBox(height: compact ? 8 : 16),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(retryLabel),
          ),
        ],
      ],
    );

    if (compact) return content;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: content,
      ),
    );
  }
}
