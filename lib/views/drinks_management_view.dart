import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class DrinksManagementView extends StatefulWidget {
  const DrinksManagementView({super.key});

  @override
  State<DrinksManagementView> createState() => _DrinksManagementViewState();
}

class _DrinksManagementViewState extends State<DrinksManagementView> {
  final _supabase = Supabase.instance.client;

  Future<void> _showDrinkDialog({Map<String, dynamic>? drink}) async {
    final isEditing = drink != null;
    final nameController = TextEditingController(text: isEditing ? drink['name'] : '');
    final descController = TextEditingController(text: isEditing ? drink['description'] : '');
    final priceController = TextEditingController(text: isEditing ? drink['price'].toString() : '');
    final costController = TextEditingController(text: isEditing ? (drink['cost'] ?? 0.0).toString() : '');
    String category = isEditing ? drink['category'] : 'drink';
    String? currentImageUrl = isEditing ? drink['image_url'] : null;
    XFile? selectedImage;
    bool isUploading = false;

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? 'Editar Bebida' : 'Nueva Bebida'),
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
                        decoration: const InputDecoration(labelText: 'Precio de Venta'),
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
                        value: ['jugos', 'cafes', 'refrescos', 'aguas', 'alcohol', 'drink'].contains(category) ? category : 'jugos',
                        decoration: const InputDecoration(labelText: 'Subcategoría'),
                        items: const [
                          DropdownMenuItem(value: 'jugos',     child: Text('Jugos')),
                          DropdownMenuItem(value: 'cafes',     child: Text('Cafés')),
                          DropdownMenuItem(value: 'refrescos', child: Text('Refrescos')),
                          DropdownMenuItem(value: 'aguas',     child: Text('Aguas')),
                          DropdownMenuItem(value: 'alcohol',   child: Text('Alcohol')),
                        ],
                        onChanged: (v) { if (v != null) category = v; },
                        validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
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

                        final data = {
                          'name': nameController.text,
                          'description': descController.text,
                          'price': double.parse(priceController.text),
                          'cost': double.parse(costController.text),
                          'image_url': finalImageUrl,
                          'category': category,
                          'requires_guisado': false,
                          'max_time': 5,
                        };

                        if (isEditing) {
                          await _supabase.from('dishes').update(data).eq('id', drink['id']);
                        } else {
                          await _supabase.from('dishes').insert(data);
                        }
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error al guardar bebida: $e')),
                        );
                      } finally {
                        if (mounted) setDialogState(() => isUploading = false);
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

  Future<void> _deleteDrink(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar bebida?'),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se puede eliminar (quizás esté en una orden): $e')),
          );
        }
      }
    }
  }

  String _categoryLabel(String category) {
    const labels = {
      'jugos': 'Jugos',
      'cafes': 'Cafés',
      'refrescos': 'Refrescos',
      'aguas': 'Aguas',
      'alcohol': 'Alcohol',
      'drink': 'Bebidas',
    };
    return labels[category] ?? category;
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
                'Gestión de Bebidas',
                style: TextStyle(fontSize: isMobile ? 24 : 28, fontWeight: FontWeight.bold),
              ),
              if (isMobile) const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showDrinkDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Nueva Bebida'),
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
            stream: _supabase
                .from('dishes')
                .stream(primaryKey: ['id'])
                .inFilter('category', ['drink', 'jugos', 'cafes', 'refrescos', 'aguas', 'alcohol'])
                .order('category')
                .order('name'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final drinks = snapshot.data!;

              if (drinks.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_drink, size: 64, color: Color(0xFF334155)),
                      SizedBox(height: 16),
                      Text('No hay bebidas registradas', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 8),
                      Text('Usa el botón "Nueva Bebida" para agregar una.', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                itemCount: drinks.length,
                separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155)),
                itemBuilder: (context, index) {
                  final drink = drinks[index];
                  return ListTile(
                    leading: SizedBox(
                      width: 50,
                      height: 50,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          drink['image_url'] ?? 'https://via.placeholder.com/150',
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.local_drink, size: 40, color: Color(0xFFFF6D00)),
                        ),
                      ),
                    ),
                    title: Text(drink['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Venta: \$${drink['price']} | Compra: \$${drink['cost'] ?? 0.0}'),
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6D00).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _categoryLabel(drink['category'] ?? 'drink'),
                            style: const TextStyle(
                              color: Color(0xFFFF6D00),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showDrinkDialog(drink: drink),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteDrink(drink['id']),
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
