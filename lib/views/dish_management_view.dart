import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class DishManagementView extends StatefulWidget {
  const DishManagementView({super.key});

  @override
  State<DishManagementView> createState() => _DishManagementViewState();
}

class _DishManagementViewState extends State<DishManagementView> {
  final _supabase = Supabase.instance.client;

  Future<void> _showDishDialog({Map<String, dynamic>? dish}) async {
    final isEditing = dish != null;
    final nameController = TextEditingController(text: isEditing ? dish['name'] : '');
    final descController = TextEditingController(text: isEditing ? dish['description'] : '');
    final priceController = TextEditingController(text: isEditing ? dish['price'].toString() : '');
    final costController = TextEditingController(text: isEditing ? (dish['cost'] ?? 0.0).toString() : '');
    String category = isEditing ? dish['category'] : 'mainCourse';
    String? currentImageUrl = isEditing ? dish['image_url'] : null;
    XFile? selectedImage;
    bool isUploading = false;
    bool requiresGuisado = isEditing ? (dish['requires_guisado'] ?? false) : false;

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? 'Editar Platillo' : 'Nuevo Platillo'),
              content: Form(
                key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) => v!.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: priceController,
                    decoration: const InputDecoration(labelText: 'Precio de Venta (Clientes)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v!.isEmpty) return 'Requerido';
                      if (double.tryParse(v) == null) return 'Número inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: costController,
                    decoration: const InputDecoration(labelText: 'Precio de Compra (Costo)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v!.isEmpty) return 'Requerido';
                      if (double.tryParse(v) == null) return 'Número inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: isUploading ? null : () async {
                          final ImagePicker picker = ImagePicker();
                          final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                          if (image != null) {
                            setDialogState(() {
                              selectedImage = image;
                            });
                          }
                        },
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Elegir Imagen'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (selectedImage != null)
                        const Expanded(child: Text('Imagen nueva seleccionada', style: TextStyle(color: Colors.green)))
                      else if (currentImageUrl != null && currentImageUrl.isNotEmpty)
                        const Expanded(child: Text('Imagen actual guardada'))
                      else
                        const Expanded(child: Text('No hay imagen', style: TextStyle(color: Colors.grey))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: [
                      'tacos','tostadas','tortas','especialidades',
                      'mainCourse','breakfast','soup','salad','appetizer',
                      'side','drink','alcohol','dessert',
                    ].contains(category) ? category : 'mainCourse',
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: const [
                      DropdownMenuItem(value: 'tacos',          child: Text('Tacos')),
                      DropdownMenuItem(value: 'tostadas',       child: Text('Tostadas')),
                      DropdownMenuItem(value: 'tortas',         child: Text('Tortas')),
                      DropdownMenuItem(value: 'especialidades', child: Text('Especialidades')),
                      DropdownMenuItem(value: 'mainCourse',     child: Text('Platillos')),
                      DropdownMenuItem(value: 'breakfast',      child: Text('Desayunos')),
                      DropdownMenuItem(value: 'soup',           child: Text('Sopas')),
                      DropdownMenuItem(value: 'salad',          child: Text('Ensaladas')),
                      DropdownMenuItem(value: 'appetizer',      child: Text('Entradas')),
                      DropdownMenuItem(value: 'side',           child: Text('Complementos')),
                      DropdownMenuItem(value: 'drink',          child: Text('Bebidas')),
                      DropdownMenuItem(value: 'alcohol',        child: Text('Alcohol')),
                      DropdownMenuItem(value: 'dessert',        child: Text('Postres')),
                    ],
                    onChanged: (v) { if (v != null) category = v; },
                    validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Requiere selección de guisado'),
                    subtitle: const Text('Al ordenar, el mesero elegirá el guisado'),
                    value: requiresGuisado,
                    onChanged: (v) => setDialogState(() => requiresGuisado = v),
                    activeColor: const Color(0xFFFF6D00),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: (dish?['max_time'] ?? 15).toString(),
                    decoration: const InputDecoration(
                      labelText: 'Tiempo Máximo de Preparación (Minutos)',
                      helperText: 'La orden parpadeará si excede este tiempo.',
                      prefixIcon: Icon(Icons.timer),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      if (v.isNotEmpty) {
                        dish?['max_time'] = int.tryParse(v) ?? 15;
                      }
                    },
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Requerido';
                      if (int.tryParse(v) == null) return 'Ingrese un número entero';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isUploading ? null : () async {
                    if (formKey.currentState!.validate()) {
                      setDialogState(() => isUploading = true);
                      
                      try {
                        String? finalImageUrl = currentImageUrl;

                        // 1. Upload new image if selected
                        if (selectedImage != null) {
                          final bytes = await selectedImage!.readAsBytes();
                          final originalName = selectedImage!.name;
                          final extension = originalName.contains('.') ? originalName.split('.').last : 'png';
                          final fileName = 'dish_${DateTime.now().millisecondsSinceEpoch}.$extension';
                          
                          await _supabase.storage.from('dish_images').uploadBinary(
                            fileName,
                            bytes,
                            fileOptions: FileOptions(upsert: true, contentType: selectedImage!.mimeType),
                          );
                          
                          finalImageUrl = _supabase.storage.from('dish_images').getPublicUrl(fileName);
                        }

                        // 2. Save/Update dish in database
                        final data = {
                          'name': nameController.text,
                          'description': descController.text,
                          'price': double.parse(priceController.text),
                          'cost': double.parse(costController.text),
                          'image_url': finalImageUrl,
                          'category': category,
                          'max_time': int.tryParse((dish?['max_time'] ?? 15).toString()) ?? 15,
                          'requires_guisado': requiresGuisado,
                        };

                        if (isEditing) {
                          await _supabase.from('dishes').update(data).eq('id', dish['id']);
                        } else {
                          await _supabase.from('dishes').insert(data);
                        }
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        debugPrint('Error caught: $e');
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('[V2] Error al guardar platillo: $e')));
                      } finally {
                        if (mounted) {
                          setDialogState(() => isUploading = false);
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6D00),
                    foregroundColor: Colors.white,
                  ),
                  child: isUploading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteDish(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar platillo?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('dishes').delete().eq('id', id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se puede eliminar (quizás esté en una orden): \$e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
          child: Flex(
            direction: isMobile ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gestión de Menú',
                style: TextStyle(fontSize: isMobile ? 24 : 28, fontWeight: FontWeight.bold),
              ),
              if (isMobile) const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showDishDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo Platillo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase.from('dishes').stream(primaryKey: ['id']).order('category').order('name'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final dishes = snapshot.data!;

              return ListView.separated(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                itemCount: dishes.length,
                separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155)),
                itemBuilder: (context, index) {
                  final dish = dishes[index];
                  return ListTile(
                    leading: SizedBox(
                      width: 50,
                      height: 50,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          dish['image_url'] ?? 'https://via.placeholder.com/150',
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.fastfood, size: 50),
                        ),
                      ),
                    ),
                    title: Text(dish['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Venta: \$${dish['price']} | Compra: \$${dish['cost'] ?? 0.0}'),
                        Row(
                          children: [
                            Text('Categoría: ${dish['category']}'),
                            if (dish['requires_guisado'] == true) ...[
                              const SizedBox(width: 8),
                              const Text(
                                'Con guisado',
                                style: TextStyle(
                                  color: Color(0xFFFF6D00),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showDishDialog(dish: dish),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteDish(dish['id']),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
