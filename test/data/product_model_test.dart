import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/data/models/product_model.dart';

Map<String, dynamic> _validJson() => <String, dynamic>{
  'id': 'p01',
  'title': 'Aurora Wireless Noise-Cancelling Earbuds',
  'description': 'A dependable everyday pick.',
  'price': 129.99,
  'compareAtPrice': 149.99,
  'imageUrls': ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
  'rating': 4.6,
  'reviewCount': 321,
  'stock': 42,
  'categoryId': 'c1',
  'sellerName': 'Northgate Audio',
  'isAvailable': true,
};

void main() {
  group('ProductModel.fromJson — valid payloads', () {
    test('parses every field', () {
      final product = ProductModel.fromJson(_validJson());

      expect(product.id, 'p01');
      expect(product.title, 'Aurora Wireless Noise-Cancelling Earbuds');
      expect(product.price, 129.99);
      expect(product.compareAtPrice, 149.99);
      expect(product.imageUrls, hasLength(2));
      expect(product.rating, 4.6);
      expect(product.reviewCount, 321);
      expect(product.stock, 42);
      expect(product.categoryId, 'c1');
      expect(product.sellerName, 'Northgate Audio');
      expect(product.isAvailable, isTrue);
    });

    test('compareAtPrice may be absent or null', () {
      final withoutKey = _validJson()..remove('compareAtPrice');
      expect(ProductModel.fromJson(withoutKey).compareAtPrice, isNull);

      final nullValue = _validJson();
      nullValue['compareAtPrice'] = null;
      expect(ProductModel.fromJson(nullValue).compareAtPrice, isNull);
    });

    test('numeric strings are safely coerced', () {
      final json = _validJson()
        ..['price'] = '99.5'
        ..['rating'] = '4.8'
        ..['reviewCount'] = '12'
        ..['stock'] = 7.0;
      final product = ProductModel.fromJson(json);
      expect(product.price, 99.5);
      expect(product.rating, 4.8);
      expect(product.reviewCount, 12);
      expect(product.stock, 7);
    });

    test('string booleans are coerced', () {
      final json = _validJson()..['isAvailable'] = 'false';
      expect(ProductModel.fromJson(json).isAvailable, isFalse);
    });

    test('toJson → fromJson round-trips the snapshot', () {
      final original = ProductModel.fromJson(_validJson());
      final roundTripped = ProductModel.fromJson(original.toJson());

      expect(roundTripped.toDomain(), original.toDomain());
      expect(roundTripped.imageUrls, original.imageUrls);
      expect(roundTripped.compareAtPrice, original.compareAtPrice);
    });
  });

  group('ProductModel.fromJson — malformed shapes', () {
    test('missing required field throws MalformedResponseException', () {
      final json = _validJson()..remove('title');
      expect(
        () => ProductModel.fromJson(json),
        throwsA(isA<MalformedResponseException>()),
      );
    });

    test('null required field throws MalformedResponseException', () {
      final json = _validJson();
      json['price'] = null;
      expect(
        () => ProductModel.fromJson(json),
        throwsA(isA<MalformedResponseException>()),
      );
    });

    test('non-numeric string price throws MalformedResponseException', () {
      final json = _validJson()..['price'] = 'free';
      expect(
        () => ProductModel.fromJson(json),
        throwsA(isA<MalformedResponseException>()),
      );
    });

    test(
      'map where a string is expected throws MalformedResponseException',
      () {
        final json = _validJson()..['id'] = {'value': 'p01'};
        expect(
          () => ProductModel.fromJson(json),
          throwsA(isA<MalformedResponseException>()),
        );
      },
    );

    test('non-string entries inside imageUrls throw '
        'MalformedResponseException', () {
      final json = _validJson();
      json['imageUrls'] = [
        'https://ok.example/1.jpg',
        {'url': 'x'},
      ];
      expect(
        () => ProductModel.fromJson(json),
        throwsA(isA<MalformedResponseException>()),
      );
    });

    test('unparseable boolean throws MalformedResponseException', () {
      final json = _validJson()..['isAvailable'] = 'maybe';
      expect(
        () => ProductModel.fromJson(json),
        throwsA(isA<MalformedResponseException>()),
      );
    });
  });

  group('ProductModel.toDomain', () {
    test('the domain snapshot is deeply equal and immutable', () {
      final model = ProductModel.fromJson(_validJson());
      final domain = model.toDomain();

      expect(domain.id, model.id);
      expect(domain.imageUrls, isNot(same(model.imageUrls)));
      expect(() => domain.imageUrls.add('x'), throwsUnsupportedError);
      expect(domain.isOutOfStock, isFalse);
    });

    test('isOutOfStock reflects stock and availability', () {
      final outOfStock = ProductModel.fromJson(_validJson()..['stock'] = 0)
          .toDomain();
      expect(outOfStock.isOutOfStock, isTrue);

      final unavailable = ProductModel.fromJson(
        _validJson()..['isAvailable'] = false,
      ).toDomain();
      expect(unavailable.isOutOfStock, isTrue);
    });

    test('discount math derives from compareAtPrice', () {
      final discounted = ProductModel.fromJson(_validJson()).toDomain();
      expect(discounted.hasDiscount, isTrue);
      expect(discounted.discountPercent, 13);

      final fullPrice = ProductModel.fromJson(
        _validJson()..remove('compareAtPrice'),
      ).toDomain();
      expect(fullPrice.hasDiscount, isFalse);
      expect(fullPrice.discountPercent, isNull);
    });

    test('fromDomain → toDomain preserves every field', () {
      final domain = ProductModel.fromJson(_validJson()).toDomain();
      final rebuilt = ProductModel.fromDomain(domain).toDomain();
      expect(rebuilt, domain);
    });
  });
}
