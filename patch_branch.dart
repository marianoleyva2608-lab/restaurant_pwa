import 'dart:io';

void main() {
  final directory = Directory('lib/views');
  final files = directory.listSync().whereType<File>().toList();
  
  for (var file in files) {
    if (!file.path.endsWith('.dart')) continue;
    
    var content = file.readAsStringSync();
    bool changed = false;

    // Add import if missing
    if (!content.contains("import '../globals.dart';") && 
        (content.contains(".from('orders')") || 
         content.contains(".from('restaurant_tables')") || 
         content.contains(".from('waiters')") || 
         content.contains(".from('dishes')"))) {
      content = content.replaceFirst("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../globals.dart';");
      changed = true;
    }

    // Replace select queries streams
    final Map<String, String> replacements = {
      ".from('orders').stream(primaryKey: ['id'])": ".from('orders').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch)",
      ".from('restaurant_tables').stream(primaryKey: ['id'])": ".from('restaurant_tables').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch)",
      ".from('waiters').stream(primaryKey: ['id'])": ".from('waiters').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch)",
      ".from('dishes').stream(primaryKey: ['id'])": ".from('dishes').stream(primaryKey: ['id']).eq('branch_name', Globals.currentBranch)",
      
      ".from('orders').select()": ".from('orders').select().eq('branch_name', Globals.currentBranch)",
      ".from('restaurant_tables').select()": ".from('restaurant_tables').select().eq('branch_name', Globals.currentBranch)",
      ".from('waiters').select(": ".from('waiters').select().eq('branch_name', Globals.currentBranch)",  // might be select('id, name') wait, better precision below:
    };

    replacements.forEach((find, replace) {
      if (content.contains(find)) {
        content = content.replaceAll(find, replace);
        changed = true;
      }
    });

    // Special exact replacements
    if (content.contains(".from('waiters').select('id, name')")) {
      content = content.replaceAll(".from('waiters').select('id, name')", ".from('waiters').select('id, name').eq('branch_name', Globals.currentBranch)");
      changed = true;
    }

    // Inserts
    content = content.replaceAll(".insert({'name': name})", ".insert({'name': name, 'branch_name': Globals.currentBranch})");
    content = content.replaceAll(".insert({'name': dishName, 'price': dishPrice, 'category': dishCategory})", ".insert({'name': dishName, 'price': dishPrice, 'category': dishCategory, 'branch_name': Globals.currentBranch})");
    content = content.replaceAll(".insert({'table_number': tn})", ".insert({'table_number': tn, 'branch_name': Globals.currentBranch})");
    content = content.replaceAll(".insert({", ".insert({ 'branch_name': Globals.currentBranch, "); // Generic blanket but might be risky, let's revert:
    content = content.replaceAll(".insert({ 'branch_name': Globals.currentBranch, ", ".insert({"); 
    
    // Specific orders insert
    content = content.replaceAll("'customer_name': customerName,", "'customer_name': customerName, 'branch_name': Globals.currentBranch,");
    content = content.replaceAll("'table_id': tableId,", "'table_id': tableId, 'branch_name': Globals.currentBranch,");

    if (changed) {
      file.writeAsStringSync(content);
      print("Patched \${file.path}");
    }
  }
  
  // Patch main.dart
  final mainFile = File('lib/main.dart');
  if (mainFile.existsSync()) {
    var mainStr = mainFile.readAsStringSync();
    if (!mainStr.contains("import 'globals.dart';")) {
      mainStr = mainStr.replaceFirst("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'globals.dart';\n");
      mainStr = mainStr.replaceFirst("void main() async {", "void main() async {\n  WidgetsFlutterBinding.ensureInitialized();\n  await Globals.loadBranch();");
      mainFile.writeAsStringSync(mainStr);
      print("Patched main.dart");
    }
  }
}
