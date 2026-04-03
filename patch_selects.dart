import 'dart:io';

void main() {
  final directory = Directory('lib/views');
  final files = directory.listSync().whereType<File>().toList();
  
  for (var file in files) {
    if (!file.path.endsWith('.dart') || file.path.contains('reports_view.dart')) continue;
    
    var content = file.readAsStringSync();
    bool changed = false;

    // Replace select queries streams
    final Map<String, String> replacements = {
      ".from('orders').stream(primaryKey: ['id'])": ".from('orders').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch)",
      ".from('restaurant_tables').stream(primaryKey: ['id'])": ".from('restaurant_tables').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch)",
      ".from('waiters').stream(primaryKey: ['id'])": ".from('waiters').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch)",
      ".from('dishes').stream(primaryKey: ['id'])": ".from('dishes').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch)",
      
      ".from('orders').select()": ".from('orders').select().eq('branch_name', Globals.currentBranch)",
      ".from('restaurant_tables').select()": ".from('restaurant_tables').select().eq('branch_name', Globals.currentBranch)",
      ".from('waiters').select('id, name')": ".from('waiters').select('id, name').eq('branch_name', Globals.currentBranch)",
      ".from('dishes').select()": ".from('dishes').select().eq('branch_name', Globals.currentBranch)",
    };

    replacements.forEach((find, replace) {
      if (content.contains(find)) {
        content = content.replaceAll(find, replace);
        changed = true;
      }
    });

    if (changed) {
      if (!content.contains("import '../globals.dart';")) {
        content = content.replaceFirst("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../globals.dart';");
      }
      file.writeAsStringSync(content);
      print("Patched reads \${file.path}");
    }
  }
}
