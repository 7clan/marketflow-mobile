import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/data/datasources/cart_local_data_source.dart';
import 'package:marketflow/data/datasources/shared_preferences_cart_local_data_source.dart';
import 'package:marketflow/domain/entities/cart_item.dart';
import 'package:marketflow/domain/entities/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'marketflow.cart';

Product _product(String id, {double price = 19.99}) => Product(
  id: id,
  title: 'Product $id',
  description: 'Snapshot product $id',
  price: price,
  imageUrls: ['https://example.com/$id.jpg'],
  rating: 4.5,
  reviewCount: 10,
  stock: 5,
  categoryId: 'c1',
  sellerName: 'Test Seller',
  isAvailable: true,
);

SharedPreferencesCartLocalDataSource _dataSource(SharedPreferences prefs) =>
    SharedPreferencesCartLocalDataSource(preferences: prefs);

Future<SharedPreferences> _freshPreferences([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

void main() {
  group('SharedPreferencesCartLocalDataSource round-trip', () {
    test('an empty store loads an empty cart', () async {
      final prefs = await _freshPreferences();
      final dataSource = _dataSource(prefs);

      expect(await dataSource.load(), isEmpty);
    });

    test(
      'saved items are restored with quantities and frozen unit prices',
      () async {
        final prefs = await _freshPreferences();
        final dataSource = _dataSource(prefs);

        final items = [
          CartItem(product: _product('p01', price: 129.99), quantity: 2),
          CartItem(product: _product('p02', price: 34.5), quantity: 1),
        ];
        await dataSource.save(items);

        // A brand-new data source over the same storage restores the cart.
        final restored = await _dataSource(prefs).load();

        expect(restored, hasLength(2));
        expect(restored, items);
        expect(restored.first.unitPrice, 129.99);
        expect(restored.first.quantity, 2);
        expect(restored.first.lineTotal, closeTo(259.98, 0.001));
      },
    );

    test('the cart is serialized as JSON under the storage key', () async {
      final prefs = await _freshPreferences();
      final dataSource = _dataSource(prefs);

      await dataSource.save([CartItem(product: _product('p01'), quantity: 3)]);

      final raw = prefs.getString(_storageKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as List<dynamic>;
      expect(decoded, hasLength(1));
      expect(decoded.first['quantity'], 3);
    });

    test('clear removes the persisted cart', () async {
      final prefs = await _freshPreferences();
      final dataSource = _dataSource(prefs);

      await dataSource.save([CartItem(product: _product('p01'), quantity: 1)]);
      await dataSource.clear();

      expect(prefs.getString(_storageKey), isNull);
      expect(await dataSource.load(), isEmpty);
    });

    test('a single corrupt entry is skipped without wiping the cart', () async {
      final good = CartItemModelless.toRawJson(
        CartItem(product: _product('p01'), quantity: 1),
      );
      final corrupt = {'quantity': 2, 'unitPrice': 9.99}; // no product map
      final prefs = await _freshPreferences({
        _storageKey: jsonEncode([good, corrupt]),
      });

      final loaded = await _dataSource(prefs).load();

      expect(loaded, hasLength(1));
      expect(loaded.first.product.id, 'p01');
    });

    test('a non-array payload surfaces CacheException', () async {
      final prefs = await _freshPreferences({
        _storageKey: jsonEncode({'not': 'a list'}),
      });

      await expectLater(
        _dataSource(prefs).load(),
        throwsA(isA<CacheException>()),
      );
    });

    test('non-JSON payload surfaces CacheException', () async {
      final prefs = await _freshPreferences({_storageKey: '{{{ not json'});

      await expectLater(
        _dataSource(prefs).load(),
        throwsA(isA<CacheException>()),
      );
    });
  });

  group('InMemoryCartLocalDataSource', () {
    test('mirrors the same save/load/clear contract', () async {
      final dataSource = InMemoryCartLocalDataSource();
      expect(await dataSource.load(), isEmpty);

      final items = [CartItem(product: _product('p01'), quantity: 4)];
      await dataSource.save(items);
      expect(await dataSource.load(), items);

      await dataSource.clear();
      expect(await dataSource.load(), isEmpty);
    });

    test(
      'returned lists are snapshots — later mutations do not leak in',
      () async {
        final dataSource = InMemoryCartLocalDataSource();
        final items = [CartItem(product: _product('p01'), quantity: 1)];
        await dataSource.save(items);

        final first = await dataSource.load();
        await dataSource.save([
          CartItem(product: _product('p02'), quantity: 2),
        ]);
        expect(first.single.product.id, 'p01');
        expect((await dataSource.load()).single.product.id, 'p02');
      },
    );
  });
}

/// Small helper so the corrupt-entry test can inline the persisted shape.
class CartItemModelless {
  static Map<String, dynamic> toRawJson(CartItem item) => {
    'product': {
      'id': item.product.id,
      'title': item.product.title,
      'description': item.product.description,
      'price': item.product.price,
      'imageUrls': item.product.imageUrls,
      'rating': item.product.rating,
      'reviewCount': item.product.reviewCount,
      'stock': item.product.stock,
      'categoryId': item.product.categoryId,
      'sellerName': item.product.sellerName,
      'isAvailable': item.product.isAvailable,
    },
    'quantity': item.quantity,
    'unitPrice': item.unitPrice,
  };
}
