import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class Globals {
  static String currentBranch = 'Sucursal Maravillas';
  static List<String> branches = ['Sucursal Maravillas', 'Sucursal Pocitos'];

  /// Cocina Especializada por sucursal (map branch→bool). Antes era un solo
  /// booleano global; ahora cada sucursal tiene su propio valor, igual que
  /// [displayModes].
  static Map<String, bool> splitKitchenModes = {};
  static bool splitKitchenModeFor(String branch) =>
      splitKitchenModes[branch] ?? false;
  static String currentUser = 'Admin';

  /// Modo de visualización de cocina por sucursal:
  ///   'printer' (default) → imprime tickets en impresora térmica.
  ///   'screen'            → cocina ve órdenes en pantalla (kitchen_view).
  /// Lo lee el print-worker desde admin_settings y deja de imprimir si está
  /// en 'screen'. La pantalla (kitchen_view o kitchen-display-lite) no
  /// necesita este flag — siempre muestra; el flag solo controla la
  /// impresora.
  static Map<String, String> displayModes = {};

  static String displayModeFor(String branch) =>
      displayModes[branch] ?? 'printer';
  
  static Future<void> loadBranch() async {
    final prefs = await SharedPreferences.getInstance();
    currentBranch = prefs.getString('restaurant_branch') ?? 'Sucursal Maravillas';

    // Try to load branches list and split mode from Supabase admin_settings.
    // Con límite de tiempo: si la conexión se cuelga (sin fallar ni
    // completarse), la app se quedaría en pantalla en blanco para siempre
    // ya que esto se espera ANTES de runApp(). Con el timeout, sigue con
    // los valores default/cacheados en vez de trabarse.
    try {
      final supabase = Supabase.instance.client;
      final settings = await supabase
          .from('admin_settings')
          .select('setting_key, setting_value')
          .timeout(const Duration(seconds: 8));

      for (var setting in settings) {
        if (setting['setting_key'] == 'branches_list') {
          branches = List<String>.from(jsonDecode(setting['setting_value']));
        } else if (setting['setting_key'] == 'split_kitchen_mode') {
          try {
            final raw = setting['setting_value'] as String;
            final map = jsonDecode(raw) as Map<String, dynamic>;
            splitKitchenModes = map.map((k, v) => MapEntry(k, v == true || v == 'true'));
          } catch (e) {
            splitKitchenModes = {};
          }
        } else if (setting['setting_key'] == 'admin_user') {
          final val = setting['setting_value'] as String?;
          if (val != null && val.isNotEmpty) currentUser = val;
        } else if (setting['setting_key'] == 'display_modes') {
          try {
            final raw = setting['setting_value'] as String;
            final map = jsonDecode(raw) as Map<String, dynamic>;
            displayModes = map.map((k, v) => MapEntry(k, v.toString()));
          } catch (e) {
            displayModes = {};
          }
        }
      }
    } catch (e) {
      print('Error loading admin settings: $e');
    }

    // Si la sucursal guardada / default no está en la lista real cargada
    // de Supabase, cambia automáticamente a la primera disponible para
    // que el APK nunca arranque con una sucursal inválida tipo "Sucursal 1".
    if (branches.isNotEmpty && !branches.contains(currentBranch)) {
      currentBranch = branches.first;
      await prefs.setString('restaurant_branch', currentBranch);
    }
  }
  
  static Future<void> setBranch(String branch) async {
    currentBranch = branch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('restaurant_branch', branch);
  }

  static Future<void> setSplitKitchenMode(String branch, bool value) async {
    try {
      final supabase = Supabase.instance.client;
      // Lee el valor más reciente antes de escribir: si otra tablet (otra
      // sucursal) cambió su propio valor después de que esta cargó, no
      // queremos sobrescribirlo con nuestra copia vieja en memoria.
      final current = await supabase
          .from('admin_settings')
          .select('setting_value')
          .eq('setting_key', 'split_kitchen_mode')
          .maybeSingle();
      Map<String, dynamic> latest = {};
      try {
        if (current?['setting_value'] != null) {
          latest = jsonDecode(current!['setting_value'] as String) as Map<String, dynamic>;
        }
      } catch (e) {
        latest = {};
      }
      latest[branch] = value;
      splitKitchenModes = latest.map((k, v) => MapEntry(k, v == true || v == 'true'));
      await supabase.from('admin_settings').upsert({
        'setting_key': 'split_kitchen_mode',
        'setting_value': jsonEncode(splitKitchenModes),
      });
    } catch (e) {
      splitKitchenModes[branch] = value;
      print('Error saving split mode: $e');
    }
  }

  /// Cambia el modo de visualización de una sucursal. Persiste en
  /// admin_settings.display_modes (JSON map de branch→mode). El
  /// print-worker lo lee cada 30s y se ajusta sin reiniciar.
  static Future<void> setDisplayMode(String branch, String mode) async {
    try {
      final supabase = Supabase.instance.client;
      // Mismo problema de concurrencia que setSplitKitchenMode: lee el
      // mapa más reciente antes de escribir en vez de confiar en la
      // copia en memoria de esta tablet.
      final current = await supabase
          .from('admin_settings')
          .select('setting_value')
          .eq('setting_key', 'display_modes')
          .maybeSingle();
      Map<String, dynamic> latest = {};
      try {
        if (current?['setting_value'] != null) {
          latest = jsonDecode(current!['setting_value'] as String) as Map<String, dynamic>;
        }
      } catch (e) {
        latest = {};
      }
      latest[branch] = mode;
      displayModes = latest.map((k, v) => MapEntry(k, v.toString()));
      await supabase.from('admin_settings').upsert({
        'setting_key': 'display_modes',
        'setting_value': jsonEncode(displayModes),
      });
    } catch (e) {
      displayModes[branch] = mode;
      print('Error saving display modes: $e');
    }
  }

  static Future<void> renameBranch(String oldName, String newName) async {
    final supabase = Supabase.instance.client;
    
    // Update data in tables
    await supabase.from('dishes').update({'branch_name': newName}).eq('branch_name', oldName);
    await supabase.from('waiters').update({'branch_name': newName}).eq('branch_name', oldName);
    await supabase.from('restaurant_tables').update({'branch_name': newName}).eq('branch_name', oldName);
    await supabase.from('orders').update({'branch_name': newName}).eq('branch_name', oldName);
    
    // Update local list
    int idx = branches.indexOf(oldName);
    if (idx != -1) {
      branches[idx] = newName;
    }
    
    // Sync to Supabase admin_settings
    await supabase.from('admin_settings').upsert({
      'setting_key': 'branches_list',
      'setting_value': jsonEncode(branches),
    });

    if (currentBranch == oldName) {
      setBranch(newName);
    }
  }

  static String translateCategory(String category) {
    final Map<String, String> translations = {
      // Categorías del menú físico
      'huevos': 'Huevos',
      'molletes': 'Molletes',
      'sopes': 'Sopes',
      'enchiladas': 'Enchiladas',
      'enmoladas': 'Enmoladas',
      'gorditas': 'Gorditas',
      'quesadillas': 'Quesadillas y más',
      'arrachera': 'Arrachera',
      'chile_relleno': 'Chile Relleno',
      'chilaquiles': 'Chilaquiles',
      'huaraches': 'Huaraches',
      'tapas': 'Tapas de guisado',
      'menudo': 'Menudo',
      'lo_dulce': 'Lo dulce',
      'para_llevar': 'Para llevar',
      'extras': 'Órdenes extras',
      'bebidas': 'Bebidas',
      // Genéricas (compatibilidad)
      'appetizer': 'Entradas',
      'mainCourse': 'Platillos',
      'drink': 'Bebidas',
      'jugos': 'Jugos',
      'cafes': 'Cafés',
      'refrescos': 'Refrescos',
      'aguas': 'Aguas',
      'choco': 'Choco',
      'te': 'Té',
      'leche': 'Leche',
      'dessert': 'Postres',
      'alcohol': 'Alcohol',
      'side': 'Complementos',
      'breakfast': 'Desayunos',
      'salad': 'Ensaladas',
      'soup': 'Sopas',
      'tacos': 'Tacos',
      'tostadas': 'Tostadas',
      'tortas': 'Tortas',
      'especialidades': 'Especialidades',
      'guisados': 'Guisados',
      'galletas': 'Galletas',
    };
    return translations[category] ?? category;
  }

  static IconData categoryIcon(String category) {
    const Map<String, IconData> icons = {
      'Todos': Icons.grid_view,
      'huevos': Icons.egg,
      'molletes': Icons.breakfast_dining,
      'sopes': Icons.circle,
      'enchiladas': Icons.local_dining,
      'enmoladas': Icons.local_dining,
      'gorditas': Icons.breakfast_dining,
      'quesadillas': Icons.local_pizza,
      'arrachera': Icons.set_meal,
      'chile_relleno': Icons.outdoor_grill,
      'chilaquiles': Icons.brunch_dining,
      'huaraches': Icons.local_dining,
      'tapas': Icons.tapas,
      'menudo': Icons.soup_kitchen,
      'lo_dulce': Icons.cake,
      'para_llevar': Icons.takeout_dining,
      'extras': Icons.add_circle_outline,
      'bebidas': Icons.local_drink,
      'appetizer': Icons.tapas,
      'mainCourse': Icons.restaurant,
      'drink': Icons.local_bar,
      'jugos': Icons.local_drink,
      'cafes': Icons.coffee,
      'refrescos': Icons.sports_bar,
      'aguas': Icons.water_drop,
      'choco': Icons.icecream,
      'te': Icons.emoji_food_beverage,
      'leche': Icons.local_cafe,
      'dessert': Icons.icecream,
      'alcohol': Icons.local_bar,
      'side': Icons.add_box,
      'breakfast': Icons.free_breakfast,
      'salad': Icons.eco,
      'soup': Icons.soup_kitchen,
      'tacos': Icons.local_dining,
      'tostadas': Icons.local_dining,
      'tortas': Icons.lunch_dining,
      'especialidades': Icons.star,
      'guisados': Icons.set_meal,
      'galletas': Icons.cookie,
    };
    return icons[category] ?? Icons.restaurant_menu;
  }
}

class CFDIConfig {
  static const String version = "4.0";
  static const String pacUser = "DEMO700101XXX";
  static const String pacPass = "DEMO700101XXX";
  static const bool isProduccion = false;

  static const String emisorRFC = "EKU9003173C9";
  static const String emisorNombre = "ESCUELA KEMPER URGATE";
  static const String emisorRegimen = "603";
  static const String lugarExpedicion = "45079";

  // Certificados (Truncados para legibilidad, el usuario debe colocar los reales)
  static const String cerBase64 = "MIIFsDCCA5igAwIBAgIUMzAwMDEwMDAwMDA1MDAwMDM0MTYwDQYJKoZIhvcNAQELBQAwggErMQ8wDQYDVQQDDAZBQyBVQVQxLjAsBgNVBAoMJVNFUlZJQ0lPIERFIEFETUlOSVNUUkFDSU9OIFRSSUJVVEFSSUExGjAYBgNVBAsMEVNBVC1JRVMgQXV0aG9yaXR5MSgwJgYJKoZIhvcNAQkBFhlvc2Nhci5tYXJ0aW5lekBzYXQuZ29iLm14MR0wGwYDVQQJDBQzcmEgY2VycmFkYSBkZSBjYWxpejEOMAwGA1UEEQwFMDYzNzAxCzAJBgNVBAYTAk1YMRkwFwYDVQQIDBBDSVVEQUQgREUgTUVYSUNPMREwDwYDVQQHDAhDT1lPQUNBTjERMA8GA1UELRMIMi41LjQuNDUxJTAjBgkqhkiG9w0BCQITFnJlc3BvbnNhYmxlOiBBQ0RNQS1TQVQwHhcNMjMwNTE4MTE0MzUxWhcNMjcwNTE4MTE0MzUxWhcNMjcwNTE4MTE0MzUxWjCB1zEnMCUGA1UEAxMeRVNDVUVMQSBLRU1QRVIgVVJHQVRFIFNBIERFIENWMScwJQYDVQQpEx5FU0NVRUxBIEtFTVBFUiBVUkdBVEUgU0EgREUgQ1YxJzAlBgNVBAoTHkVTQ1VFTEEgS0VNUEVSIFVSR0FURSBTQSBERSBDVjElMCMGA1UELRMcRUtVOTAwMzE3M0M5IC8gVkFEQTgwMDkyN0RKMzEeMBwGA1UEBRMVIC8gVkFEQTgwMDkyN0hTUlNSTDA1MRMwEQYDVQQLEwpTdWN1cnNhbCAxMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtmecO6n2GS0zL025gbHGQVxznPDICoXzR2uUngz4DqxVUC/w9cE6FxSiXm2ap8Gcjg7wmcZfm85EBaxCx/0J2u5CqnhzIoGCdhBPuhWQnIh5TLgj/X6uNquwZkKChbNe9aeFirU/JbyN7Egia9oKH9KZUsodiM/pWAH00PCtoKJ9OBcSHMq8Rqa3KKoBcfkg1ZrgueffwRLws9yOcRWLb02sDOPzGIm/jEFicVYt2Hw1qdRE5xmTZ7AGG0UHs+unkGjpCVeJ+BEBn0JPLWVvDKHZAQMj6s5Bku35+d/MyATkpOPsGT/VTnsouxekDfikJD1f7A1ZpJbqDpkJnss3vQIDAQABox0wGzAMBgNVHRMBAf8EAjAAMAsGA1UdDwQEAwIGwDANBgkqhkiG9w0BAQsFAAOCAgEAFaUgj5PqgvJigNMgtrdXZnbPfVBbukAbW4OGnUhNrA7SRAAfv2BSGk16PI0nBOr7qF2mItmBnjgEwk+DTv8Zr7w5qp7vleC6dIsZFNJoa6ZndrE/f7KO1CYruLXr5gwEkIyGfJ9NwyIagvHHMszzyHiSZIA850fWtbqtythpAliJ2jF35M5pNS+YTkRB+T6L/c6m00ymN3q9lT1rB03YywxrLreRSFZOSrbwWfg34EJbHfbFXpCSVYdJRfiVdvHnewN0r5fUlPtR9stQHyuqewzdkyb5jTTw02D2cUfL57vlPStBj7SEi3uOWvLrsiDnnCIxRMYJ2UA2ktDKHk+zWnsDmaeleSzonv2CHW42yXYPCvWi88oE1DJNYLNkIjua7MxAnkNZbScNw01A6zbLsZ3y8G6eEYnxSTRfwjd8EP4kdiHNJftm7Z4iRU7HOVh79/lRWB+gd171s3d/mI9kte3MRy6V8MMEMCAnMboGpaooYwgAmwclI2XZCczNWXfhaWe0ZS5PmytD/GDpXzkX0oEgY9K/uYo5V77NdZbGAjmyi8cE2B2ogvyaN2XfIInrZPgEffJ4AB7kFA2mwesdLOCh0BLD9itmCve3A1FGR4+stO2ANUoiI3w3Tv2yQSg4bjeDlJ08lXaaFCLW2peEXMXjQUk7fmpb5MNuOUTW6BE=";
  static const String keyBase64 = "MIIFDjBABgkqhkiG9w0BBQ0wMzAbBgkqhkiG9w0BBQwwDgQIAgEAAoIBAQACAggAMBQGCCqGSIb3DQMHBAgwggS/AgEAMASCBMh4EHl7aNSCaMDA1VlRoXCZ5UUmqErAbucoZQObOaLUEm+I+QZ7Y8Giupo+F1XWkLvAsdk/uZlJcTfKLJyJbJwsQYbSpLOCLataZ4O5MVnnmMbfG//NKJn9kSMvJQZhSwAwoGLYDm1ESGezrvZabgFJnoQv8Si1nAhVGTk9FkFBesxRzq07dmZYwFCnFSX4xt2fDHs1PMpQbeq83aL/PzLCce3kxbYSB5kQlzGtUYayiYXcu0cVRu228VwBLCD+2wTDDoCmRXtPesgrLKUR4WWWb5N2AqAU1mNDC+UEYsENAerOFXWnmwrcTAu5qyZ7GsBMTpipW4Dbou2yqQ0lpA/aB06n1kz1aL6mNqGPaJ+OqoFuc8Ugdhadd+MmjHfFzoI20SZ3b2geCsUMNCsAd6oXMsZdWm8lzjqCGWHFeol0ik/xHMQvuQkkeCsQ28PBxdnUgf7ZGer+TN+2ZLd2kvTBOk6pIVgy5yC6cZ+o1Tloql9hYGa6rT3xcMbXlW+9e5jM2MWXZliVW3ZhaPjptJFDbIfWxJPjz4QvKyJk0zok4muv13Iiwj2bCyefUTRz6psqI4cGaYm9JpscKO2RCJN8UluYGbbWmYQU+Int6LtZj/lv8p6xnVjWxYI+rBPdtkpfFYRp+MJiXjgPw5B6UGuoruv7+vHjOLHOotRo+RdjZt7NqL9dAJnl1Qb2jfW6+d7NYQSI/bAwxO0sk4taQIT6Gsu/8kfZOPC2xk9rphGqCSS/4q3Os0MMjA1bcJLyoWLp13pqhK6bmiiHw0BBXH4fbEp4xjSbpPx4tHXzbdn8oDsHKZkWh3pPC2J/nVl0k/yF1KDVowVtMDXE47k6TGVcBoqe8PDXCG9+vjRpzIidqNo5qebaUZu6riWMWzldz8x3Z/jLWXuDiM7/Yscn0Z2GIlfoeyz+GwP2eTdOw9EUedHjEQuJY32bq8LICimJ4Ht+zMJKUyhwVQyAER8byzQBwTYmYP5U0wdsyIFitphw+/IH8+v08Ia1iBLPQAeAvRfTTIFLCs8foyUrj5Zv2B/wTYIZy6ioUM+qADeXyo45uBLLqkN90Rf6kiTqDld78NxwsfyR5MxtJLVDFkmf2IMMJHTqSfhbi+7QJaC11OOUJTD0v9wo0X/oO5GvZhe0ZaGHnm9zqTopALuFEAxcaQlc4R81wjC4wrIrqWnbcl2dxiBtD73KW+wcC9ymsLf4I8BEmiN25lx/OUc1IHNyXZJYSFkEfaxCEZWKcnbiyf5sqFSSlEqZLc4lUPJFAoP6s1FHVcyO0odWqdadhRZLZC9RCzQgPlMRtji/OXy5phh7diOBZv5UYp5nb+MZ2NAB/eFXm2JLguxjvEstuvTDmZDUb6Uqv++RdhO5gvKf/AcwU38ifaHQ9uvRuDocYwVxZS2nr9rOwZ8nAh+P2o4e0tEXjxFKQGhxXYkn75H3hhfnFYjik/2qunHBBZfcdG148MaNP6DjX33M238T9Zw/GyGx00JMogr2pdP4JAErv9a5yt4YR41KGf8guSOUbOXVARw6+ybh7+meb7w4BeTlj3aZkv8tVGdfIt3lrwVnlbzhLjeQY6PplKp3/a5Kr5yM0T4wJoKQQ6v3vSNmrhpbuAtKxpMILe8CQoo=";
  static const String keyPass = "12345678a";
}
