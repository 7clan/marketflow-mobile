import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../domain/entities/product.dart';
import 'favorite_button.dart';
import 'price_text.dart';
import 'rating_stars.dart';

/// Product tile for the feed grid and search results.
///
/// Layout contract under large text scales: the image is the flexible
/// element ([Expanded]) and every text row wraps or ellipsizes — the card
/// never overflows its grid cell.
///
/// Performance: [CachedNetworkImage] with a decode width sized for a grid
/// cell (~500 device pixels), so a scrolling feed never decodes the
/// full-resolution imagery into the image cache.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discountPercent = product.discountPercent;

    return Card(
      child: Semantics(
        button: true,
        label: '${product.title}, ${Formatters.currency(product.price)}',
        child: InkWell(
          onTap: () => context.push('/product/${product.id}', extra: product),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: product.imageUrls.first,
                      fit: BoxFit.cover,
                      memCacheWidth: 500,
                      placeholder: _imagePlaceholder,
                      errorWidget: _imageError,
                    ),
                    if (discountPercent != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: IgnorePointer(
                          // Badge, not a control — hidden from the a11y tree.
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '-$discountPercent%',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: FavoriteButton(product: product),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    RatingStars(
                      rating: product.rating,
                      reviewCount: product.reviewCount,
                    ),
                    const SizedBox(height: 6),
                    PriceText(
                      price: product.price,
                      compareAtPrice: product.compareAtPrice,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder(BuildContext context, String url) =>
      ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);

  Widget _imageError(BuildContext context, String url, Object error) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 32,
        color: theme.colorScheme.onSurfaceVariant,
        semanticLabel: 'Image unavailable',
      ),
    );
  }
}
