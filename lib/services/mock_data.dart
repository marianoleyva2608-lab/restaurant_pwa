import '../models/dish.dart';

class MockData {
  static const List<Dish> dishes = [
    Dish(
      id: '1',
      name: 'Enchiladas Potosinas',
      description: 'Tradicionales de San Luis Potosí, rellenas de queso y chile serrano.',
      price: 145.0,
      imageUrl: 'https://images.unsplash.com/photo-1533777857889-4be7c70b33f7?auto=format&fit=crop&w=800&q=80',
      category: 'Plato Fuerte',
    ),
    Dish(
      id: '2',
      name: 'Guacamole Premium',
      description: 'Aguacate hass con pico de gallo, chicharrón y totopos artesanales.',
      price: 120.0,
      imageUrl: 'https://images.unsplash.com/photo-1604544215162-a740714ed9bc?auto=format&fit=crop&w=800&q=80',
      category: 'Entrada',
    ),
    Dish(
      id: '3',
      name: 'Flan de Cajeta',
      description: 'Suave flan horneado con cajeta quemada y nuez garapiñada.',
      price: 85.0,
      imageUrl: 'https://images.unsplash.com/photo-1528975612631-0df63a290ec5?auto=format&fit=crop&w=800&q=80',
      category: 'Postre',
    ),
    Dish(
      id: '4',
      name: 'Agua de Horchata',
      description: 'Receta de la casa con arroz, canela y un toque de vainilla.',
      price: 45.0,
      imageUrl: 'https://images.unsplash.com/photo-1594911776517-5789966144e0?auto=format&fit=crop&w=800&q=80',
      category: 'Bebida',
    ),
    Dish(
      id: '5',
      name: 'Tacos de Pastor (5 pzs)',
      description: 'Carne de cerdo adobada, piña, cebolla y cilantro.',
      price: 130.0,
      imageUrl: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&q=80',
      category: 'Plato Fuerte',
    ),
  ];
}
