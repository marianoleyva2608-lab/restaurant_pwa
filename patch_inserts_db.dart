import 'dart:io';

void main() {
  var waitersFile = File('lib/views/waiter_management_view.dart');
  if (waitersFile.existsSync()) {
    var text = waitersFile.readAsStringSync();
    text = text.replaceAll("'pin': pinController.text.trim(),", "'pin': pinController.text.trim(), 'branch_name': Globals.currentBranch,");
    waitersFile.writeAsStringSync(text);
  }

  var dishesFile = File('lib/views/dish_management_view.dart');
  if (dishesFile.existsSync()) {
    var text = dishesFile.readAsStringSync();
    text = text.replaceAll("data['name'] = _nameCtrl.text.trim();", "data['name'] = _nameCtrl.text.trim(); data['branch_name'] = Globals.currentBranch;");
    dishesFile.writeAsStringSync(text);
  }

  var tablesFile = File('lib/views/table_management_view.dart');
  if (tablesFile.existsSync()) {
    var text = tablesFile.readAsStringSync();
    text = text.replaceAll("'table_number': tableNumber,", "'table_number': tableNumber, 'branch_name': Globals.currentBranch,");
    tablesFile.writeAsStringSync(text);
  }

  var clientCheckoutFile = File('lib/views/client_checkout_view.dart');
  if (clientCheckoutFile.existsSync()) {
    var text = clientCheckoutFile.readAsStringSync();
    text = text.replaceAll("'customer_name': _nameCtrl.text.trim(),", "'customer_name': _nameCtrl.text.trim(), 'branch_name': Globals.currentBranch,");
    text = text.replaceAll("'table_id': null,", "'table_id': null, 'branch_name': Globals.currentBranch,");
    clientCheckoutFile.writeAsStringSync(text);
  }

  var comandasFile = File('lib/views/comandas_view.dart');
  if (comandasFile.existsSync()) {
    var text = comandasFile.readAsStringSync();
    text = text.replaceAll("'table_id': widget.tableId!,", "'table_id': widget.tableId!, 'branch_name': Globals.currentBranch,");
    comandasFile.writeAsStringSync(text);
  }
}
