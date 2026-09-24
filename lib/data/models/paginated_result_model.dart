import '../../core/errors/app_exception.dart';
import '../../domain/entities/paginated_result.dart';
import 'json_reader.dart';

/// Wire representation of one page of a paginated collection.
///
/// [T] is the domain item type; [parseItem] turns each raw JSON entry into a
/// domain model. Unknown fields are ignored; missing envelope fields throw
/// [MalformedResponseException] through [JsonReader].
class PaginatedResultModel<T> {
  const PaginatedResultModel({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalItems,
    required this.hasMore,
  });

  factory PaginatedResultModel.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parseItem,
  ) {
    final rawItems = JsonReader.requireList(json, 'items');
    final items = <T>[];
    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) {
        throw MalformedResponseException(
          cause: 'Field "items" must be an array of objects.',
        );
      }
      items.add(parseItem(raw));
    }
    return PaginatedResultModel<T>(
      items: items,
      page: JsonReader.requireInt(json, 'page'),
      totalPages: JsonReader.requireInt(json, 'totalPages'),
      totalItems: JsonReader.requireInt(json, 'totalItems'),
      hasMore: JsonReader.requireBool(json, 'hasMore'),
    );
  }

  final List<T> items;
  final int page;
  final int totalPages;
  final int totalItems;
  final bool hasMore;

  PaginatedResult<T> toDomain() => PaginatedResult<T>(
    items: List<T>.unmodifiable(items),
    page: page,
    totalPages: totalPages,
    totalItems: totalItems,
    hasMore: hasMore,
  );
}
