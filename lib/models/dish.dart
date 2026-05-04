class Dish {
  final String id;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final String category;
  final bool isPurchase;
  final bool isSale;
  final double cost;
  final bool requiresGuisado;

  const Dish({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.category,
    this.isPurchase = false,
    this.isSale = true,
    this.cost = 0.0,
    this.requiresGuisado = false,
  });

  Dish copyWith({double? price}) => Dish(
        id: id,
        name: name,
        description: description,
        price: price ?? this.price,
        imageUrl: imageUrl,
        category: category,
        isPurchase: isPurchase,
        isSale: isSale,
        cost: cost,
        requiresGuisado: requiresGuisado,
      );

  factory Dish.fromJson(Map<String, dynamic> json) {
    return Dish(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      price: (json['price'] as num? ?? 0.0).toDouble(),
      imageUrl: json['image_url'] ?? 'https://via.placeholder.com/150',
      category: json['category'] ?? 'Plato Fuerte',
      isPurchase: json['is_purchase'] ?? false,
      isSale: json['is_sale'] ?? true,
      cost: (json['cost'] as num? ?? 0.0).toDouble(),
      requiresGuisado: json['requires_guisado'] ?? false,
    );
  }
}
