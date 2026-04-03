enum CourseCategory {
  appetizer,
  mainCourse,
  dessert,
  drink,
}

class Dish {
  final String id;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final CourseCategory category;
  final bool isPurchase;
  final bool isSale;
  final double cost;

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
  });

  factory Dish.fromJson(Map<String, dynamic> json) {
    return Dish(
      id: json['id'].toString(),
      name: json['name'],
      description: json['description'] ?? '',
      price: (json['price'] as num).toDouble(),
      imageUrl: json['image_url'] ?? 'https://via.placeholder.com/150',
      category: _parseCategory(json['category']),
      isPurchase: json['is_purchase'] ?? false,
      isSale: json['is_sale'] ?? true,
      cost: (json['cost'] as num? ?? 0.0).toDouble(),
    );
  }

  static CourseCategory _parseCategory(String? cat) {
    switch (cat) {
      case 'appetizer': return CourseCategory.appetizer;
      case 'mainCourse': return CourseCategory.mainCourse;
      case 'dessert': return CourseCategory.dessert;
      case 'drink': return CourseCategory.drink;
      default: return CourseCategory.mainCourse;
    }
  }
}
