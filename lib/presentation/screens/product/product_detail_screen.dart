import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/cart_item.dart';
import '../../../domain/entities/product.dart';
import '../../providers/cart_controller.dart';
import '../../providers/favorites_controller.dart';
import '../../providers/product_detail_provider.dart';
import '../../widgets/error_view.dart';
import '../../widgets/favorite_button.dart';
import '../../widgets/price_text.dart';
import '../../widgets/quantity_stepper.dart';
import '../../widgets/rating_stars.dart';
import '../../widgets/skeleton.dart';

/// Product detail: gallery, pricing, stock, seller, description, quantity
/// and add-to-cart.
///
/// When opened from a feed card the tapped [initialProduct] renders
/// instantly while the authoritative copy loads in the background
/// (optimistic content, then silent correction).
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.productId,
    this.initialProduct,
  });

  final String productId;
  final Product? initialProduct;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  final _pageController = PageController();
  var _quantity = 1;
  var _descriptionExpanded = false;
  var _galleryIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _announce(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _addToCart(Product product) {
    final controller = ref.read(cartControllerProvider.notifier);
    controller.addToCart(product, quantity: _quantity);

    // The controller may have clamped the quantity (stock / order limits)
    // and recorded the reason as a validation message for this product.
    final validation = ref.read(cartControllerProvider).messageFor(product.id);
    if (validation != null) {
      _announce(validation);
      return;
    }

    _announce('${product.title} added to cart');
  }

  @override
  Widget build(BuildContext context) {
    final asyncProduct = ref.watch(productDetailProvider(widget.productId));
    final product = asyncProduct.value ?? widget.initialProduct;

    final error = asyncProduct.hasError ? asyncProduct.error : null;

    // Announce optimistic favorite rollbacks (state already restored).
    ref.listen(favoritesControllerProvider.select((state) => state.error), (
      previous,
      next,
    ) {
      if (next != null) {
        ref.read(favoritesControllerProvider.notifier).clearError();
        _announce(next.message);
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          product?.title ?? 'Product',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (product != null) ...[
            FavoriteButton(product: product),
            const SizedBox(width: 4),
          ],
        ],
      ),
      body: switch ((product, error)) {
        (null, null) => const _DetailSkeleton(),
        (null, _) => ErrorView(
          message: switch (error) {
            AppException exception => exception.message,
            _ => 'Something went wrong. Please try again.',
          },
          title: 'We could not load this product',
          retryLabel: 'Retry',
          onRetry: () =>
              ref.invalidate(productDetailProvider(widget.productId)),
        ),
        (final Product loaded, _) => _DetailContent(
          product: loaded,
          quantity: _quantity,
          galleryIndex: _galleryIndex,
          descriptionExpanded: _descriptionExpanded,
          pageController: _pageController,
          onQuantityChanged: (value) => setState(() => _quantity = value),
          onGalleryIndexChanged: (index) =>
              setState(() => _galleryIndex = index),
          onDescriptionExpandedChanged: (expanded) =>
              setState(() => _descriptionExpanded = expanded),
          onAddToCart: () => _addToCart(loaded),
        ),
      },
      bottomNavigationBar: product == null
          ? null
          : _AddToCartBar(product: product, onAdd: () => _addToCart(product)),
    );
  }
}

/// Skeleton while the product loads with no optimistic copy available.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonAnnouncer(
      child: SkeletonPulse(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const AspectRatio(aspectRatio: 1, child: SkeletonBlock(radius: 16)),
            const SizedBox(height: 16),
            SkeletonBlock(height: 20, radius: 8),
            const SizedBox(height: 10),
            SkeletonBlock(height: 16, radius: 6),
            const SizedBox(height: 10),
            SkeletonBlock(height: 16, radius: 6),
            const SizedBox(height: 24),
            SkeletonBlock(height: 60, radius: 12),
          ],
        ),
      ),
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.product,
    required this.quantity,
    required this.galleryIndex,
    required this.descriptionExpanded,
    required this.pageController,
    required this.onQuantityChanged,
    required this.onGalleryIndexChanged,
    required this.onDescriptionExpandedChanged,
    required this.onAddToCart,
  });

  final Product product;
  final int quantity;
  final int galleryIndex;
  final bool descriptionExpanded;
  final PageController pageController;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<int> onGalleryIndexChanged;
  final ValueChanged<bool> onDescriptionExpandedChanged;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outOfStock = product.isOutOfStock;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Gallery(
          product: product,
          controller: pageController,
          index: galleryIndex,
          onPageChanged: onGalleryIndexChanged,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              RatingStars(
                rating: product.rating,
                reviewCount: product.reviewCount,
              ),
              const SizedBox(height: 12),
              PriceText(
                price: product.price,
                compareAtPrice: product.compareAtPrice,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                    semanticLabel: 'Seller',
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Sold by ${product.sellerName}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StockBadge(product: product),
              const SizedBox(height: 20),
              _DescriptionSection(
                product: product,
                expanded: descriptionExpanded,
                onExpandedChanged: onDescriptionExpandedChanged,
              ),
              const SizedBox(height: 20),
              if (!outOfStock)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Quantity',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    QuantityStepper(
                      value: quantity,
                      min: 1,
                      max: _maxQuantity(product),
                      onChanged: onQuantityChanged,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  static int _maxQuantity(Product product) => product.stock > 0
      ? (product.stock < CartItem.maxQuantity
            ? product.stock
            : CartItem.maxQuantity)
      : CartItem.maxQuantity;
}

/// Image gallery with page indicator.
class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.product,
    required this.controller,
    required this.index,
    required this.onPageChanged,
  });

  final Product product;
  final PageController controller;
  final int index;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final images = product.imageUrls;

    return Column(
      children: [
        Semantics(
          label: 'Image ${index + 1} of ${images.length}',
          child: AspectRatio(
            aspectRatio: 1,
            child: PageView.builder(
              controller: controller,
              itemCount: images.length,
              onPageChanged: onPageChanged,
              itemBuilder: (context, page) => CachedNetworkImage(
                imageUrl: images[page],
                fit: BoxFit.cover,
                memCacheWidth: 800,
                placeholder: (_, _) => ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (_, _, _) => ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                    semanticLabel: 'Image unavailable',
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (images.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < images.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == index ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == index
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Availability chip: in stock / low stock / out of stock.
class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (label, colorScheme) = switch (product.stock) {
      <= 0 => ('Out of stock', theme.colorScheme.errorContainer),
      < 5 => (
        'Only ${product.stock} left in stock',
        theme.colorScheme.tertiaryContainer,
      ),
      _ => ('In stock', theme.colorScheme.secondaryContainer),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        product.isOutOfStock && product.stock > 0
            ? 'Currently unavailable'
            : label,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Expandable description with a More/Less toggle.
class _DescriptionSection extends StatelessWidget {
  const _DescriptionSection({
    required this.product,
    required this.expanded,
    required this.onExpandedChanged,
  });

  final Product product;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Description', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          product.description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: expanded ? null : 4,
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => onExpandedChanged(!expanded),
          child: Text(expanded ? 'Show less' : 'Show more'),
        ),
      ],
    );
  }
}

/// Sticky add-to-cart action above the shell's bottom navigation.
class _AddToCartBar extends StatelessWidget {
  const _AddToCartBar({required this.product, required this.onAdd});

  final Product product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outOfStock = product.isOutOfStock;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: outOfStock ? null : onAdd,
            style: FilledButton.styleFrom(
              backgroundColor: outOfStock
                  ? theme.colorScheme.surfaceContainerHighest
                  : null,
              foregroundColor: outOfStock
                  ? theme.colorScheme.onSurfaceVariant
                  : null,
            ),
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: Text(
              outOfStock
                  ? 'Out of stock'
                  : 'Add to cart — ${Formatters.currency(product.price)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
