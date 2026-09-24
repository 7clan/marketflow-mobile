import 'package:flutter/material.dart';

import '../../../domain/entities/product.dart';

/// PLACEHOLDER — real implementation lands in the product-detail module.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({
    super.key,
    required this.productId,
    this.initialProduct,
  });

  final String productId;
  final Product? initialProduct;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Product detail')));
  }
}
