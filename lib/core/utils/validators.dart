/// Form-field validators returning `null` when valid and an error string
/// otherwise (the Flutter form contract).
///
/// The messages are user-facing copy, safe to render directly under a field.
abstract final class Validators {
  static final _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );
  static final _nameRegex = RegExp(r"^[A-Za-zÀ-ÿ' -]+$");
  static final _zipRegex = RegExp(r'^[A-Za-z0-9][A-Za-z0-9\- ]{2,9}$');
  static final _phoneRegex = RegExp(r'^\+?[0-9][0-9\- ]{6,15}$');
  static final _streetRegex = RegExp(
    r'^[A-Za-z0-9À-ÿ'
    r"'.,/ -]+$",
  );

  /// Validates an email address.
  static String? email(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required.';
    if (!_emailRegex.hasMatch(trimmed)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  /// Validates a password (minimum 8 characters).
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    if (value.length < 8) return 'Use at least 8 characters.';
    return null;
  }

  /// Validates a non-empty required field.
  static String? requiredField(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$label is required.';
    return null;
  }

  /// Validates a person's name (letters, spaces, apostrophes, hyphens).
  static String? name(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Name is required.';
    if (trimmed.length < 2) return 'Name is too short.';
    if (!_nameRegex.hasMatch(trimmed)) {
      return 'Use letters, spaces, apostrophes or hyphens only.';
    }
    return null;
  }

  /// Validates a street address line.
  static String? street(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Street address is required.';
    if (trimmed.length < 4) return 'Enter a complete street address.';
    if (!_streetRegex.hasMatch(trimmed)) {
      return 'Avoid special characters in the address.';
    }
    return null;
  }

  /// Validates a city name.
  static String? city(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'City is required.';
    if (trimmed.length < 2) return 'Enter a valid city.';
    if (!_nameRegex.hasMatch(trimmed)) {
      return 'Use letters, spaces, apostrophes or hyphens only.';
    }
    return null;
  }

  /// Validates a state / region name.
  static String? region(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'State is required.';
    if (trimmed.length < 2) return 'Enter a valid state.';
    if (!_nameRegex.hasMatch(trimmed)) {
      return 'Use letters, spaces, apostrophes or hyphens only.';
    }
    return null;
  }

  /// Validates a ZIP / postal code (3–10 alphanumeric characters).
  static String? zipCode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'ZIP code is required.';
    if (!_zipRegex.hasMatch(trimmed)) return 'Enter a valid ZIP code.';
    return null;
  }

  /// Validates a phone number (7–16 digits, optional country code).
  static String? phone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Phone number is required.';
    if (!_phoneRegex.hasMatch(trimmed)) {
      return 'Enter a valid phone number.';
    }
    return null;
  }
}
