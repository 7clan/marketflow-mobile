import 'package:flutter/material.dart';

/// PLACEHOLDER — real implementation lands in the order-detail module.
class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Order detail')));
  }
}
