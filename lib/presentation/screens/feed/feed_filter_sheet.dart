import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/product_filter.dart';
import '../../providers/filter_controller.dart';

/// Bottom sheet exposing the feed's sort and filter controls.
///
/// Writes go straight to [filterControllerProvider] — the feed re-runs page 1
/// automatically. Local controllers only hold the text of the min/max price
/// fields until the user applies them (a field is not a filter until the
/// sheet is committed).
class FeedFilterSheet extends ConsumerStatefulWidget {
  const FeedFilterSheet({super.key});

  @override
  ConsumerState<FeedFilterSheet> createState() => _FeedFilterSheetState();
}

class _FeedFilterSheetState extends ConsumerState<FeedFilterSheet> {
  late final TextEditingController _minPriceController;
  late final TextEditingController _maxPriceController;

  @override
  void initState() {
    super.initState();
    final filters = ref.read(filterControllerProvider);
    _minPriceController = TextEditingController(
      text: filters.minPrice == null ? '' : _formatPrice(filters.minPrice!),
    );
    _maxPriceController = TextEditingController(
      text: filters.maxPrice == null ? '' : _formatPrice(filters.maxPrice!),
    );
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  static String _formatPrice(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  void _apply() {
    final controller = ref.read(filterControllerProvider.notifier);
    controller.setMinPrice(double.tryParse(_minPriceController.text.trim()));
    controller.setMaxPrice(double.tryParse(_maxPriceController.text.trim()));
    Navigator.of(context).pop();
  }

  void _clearAll() {
    ref.read(filterControllerProvider.notifier).clear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filters = ref.watch(filterControllerProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filters & sorting',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (!filters.isEmpty)
                TextButton(
                  onPressed: _clearAll,
                  child: const Text('Clear all'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Sort by', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sort in ProductSort.values)
                ChoiceChip(
                  label: Text(switch (sort) {
                    ProductSort.relevance => 'Relevance',
                    ProductSort.newest => 'Newest',
                    ProductSort.priceAsc => 'Price: low to high',
                    ProductSort.priceDesc => 'Price: high to low',
                    ProductSort.rating => 'Top rated',
                  }),
                  selected: filters.sort == sort,
                  onSelected: (_) =>
                      ref.read(filterControllerProvider.notifier).setSort(sort),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('In stock only'),
            subtitle: const Text('Hide products that are sold out.'),
            value: filters.inStockOnly,
            onChanged: (value) => ref
                .read(filterControllerProvider.notifier)
                .setInStockOnly(value),
          ),
          const SizedBox(height: 8),
          Text('Price range', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _minPriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Min price',
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _maxPriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Max price',
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  textInputAction: TextInputAction.done,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _apply, child: const Text('Apply')),
          ),
        ],
      ),
    );
  }
}
