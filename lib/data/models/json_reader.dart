import '../../core/errors/app_exception.dart';

/// Tolerant JSON field readers shared by every model's `fromJson`.
///
/// Contract (per the MarketFlow parsing rules):
/// * a missing **required** field, or a field of the wrong *shape*, throws
///   [MalformedResponseException];
/// * wrong-but-safely-castable numeric types are accepted (JSON has a single
///   number type — `5` for a `double`, `5.0` for an `int`, `"5.5"` for either);
/// * `optional*` readers return `null` when the field is absent or `null`.
abstract final class JsonReader {
  static String requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    throw MalformedResponseException(
      cause:
          'Field "$key" must be a string but was '
          '${value == null ? 'missing' : value.runtimeType}.',
    );
  }

  static String? optionalString(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return null;
    return requireString(json, key);
  }

  static double requireDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw MalformedResponseException(
      cause:
          'Field "$key" must be a number but was '
          '${value == null ? 'missing' : value.runtimeType}.',
    );
  }

  static double? optionalDouble(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return null;
    return requireDouble(json, key);
  }

  static int requireInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw MalformedResponseException(
      cause:
          'Field "$key" must be an integer but was '
          '${value == null ? 'missing' : value.runtimeType}.',
    );
  }

  static int? optionalInt(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return null;
    return requireInt(json, key);
  }

  static bool requireBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    throw MalformedResponseException(
      cause:
          'Field "$key" must be a boolean but was '
          '${value == null ? 'missing' : value.runtimeType}.',
    );
  }

  static bool? optionalBool(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return null;
    return requireBool(json, key);
  }

  static Map<String, dynamic> requireMap(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is Map<String, dynamic>) return value;
    throw MalformedResponseException(
      cause:
          'Field "$key" must be an object but was '
          '${value == null ? 'missing' : value.runtimeType}.',
    );
  }

  static Map<String, dynamic>? optionalMap(
    Map<String, dynamic> json,
    String key,
  ) {
    if (!json.containsKey(key) || json[key] == null) return null;
    return requireMap(json, key);
  }

  static List<dynamic> requireList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is List) return value;
    throw MalformedResponseException(
      cause:
          'Field "$key" must be an array but was '
          '${value == null ? 'missing' : value.runtimeType}.',
    );
  }

  static List<String> requireStringList(Map<String, dynamic> json, String key) {
    final raw = requireList(json, key);
    final result = <String>[];
    for (final item in raw) {
      if (item is String) {
        result.add(item);
      } else if (item is num || item is bool) {
        result.add(item.toString());
      } else {
        throw MalformedResponseException(
          cause:
              'Field "$key" must only contain strings but contained '
              '${item.runtimeType}.',
        );
      }
    }
    return result;
  }

  static DateTime requireDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      try {
        return DateTime.parse(value);
      } on FormatException {
        throw MalformedResponseException(
          cause: 'Field "$key" is not a valid date: "$value".',
        );
      }
    }
    throw MalformedResponseException(
      cause:
          'Field "$key" must be an ISO-8601 string but was '
          '${value == null ? 'missing' : value.runtimeType}.',
    );
  }

  static DateTime? optionalDateTime(Map<String, dynamic> json, String key) {
    if (!json.containsKey(key) || json[key] == null) return null;
    return requireDateTime(json, key);
  }
}
