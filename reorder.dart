import 'dart:io';

void main() async {
  var file = File(
    r'c:\Users\ajiep\Documents\Developments\Ajie\sigap\lib\screens\assistant_screen.dart',
  );
  var lines = await file.readAsLines();

  int startIndex = lines.indexWhere(
    (l) =>
        l.trim() == "Row(" &&
        lines[lines.indexOf(l) + 2].contains("child: InkWell("),
  );
  if (startIndex == -1) {
    print("Could not find start index");
    return;
  }

  // Find the exact end index:
  // After `child: InkWell(`, the block ends right before `if (pendingPhoto != null)`
  // Wait, I have multiple `if (pendingPhoto != null)` now.
  // Search for the one that has `model Gemma akan mengolah visual` below it.

  int endIndex = -1;
  int searchFrom = startIndex + 50;
  for (int i = searchFrom; i < lines.length; i++) {
    if (lines[i].contains('if (pendingPhoto != null)') &&
        lines[i + 24].contains('isVisionBetaEnabled')) {
      // Roughly where the description text is
      // Move backwards to the closing `),` of the Row
      for (int j = i - 1; j > searchFrom; j--) {
        if (lines[j].trim() == '),') {
          endIndex = j;
          break;
        }
      }
      break;
    }
  }

  if (endIndex == -1) {
    print("Could not find end index");
    return;
  }

  print("Start Index: \$startIndex, End Index: \$endIndex");

  var block = lines.sublist(startIndex, endIndex + 1);
  lines.removeRange(startIndex, endIndex + 1);

  int insertIndex = lines.indexWhere(
    (l) => l.contains('children: ['),
    lines.indexWhere((l) => l.contains('return SingleChildScrollView(')),
  );
  if (insertIndex == -1) {
    print("Could not find insert index");
    return;
  }

  insertIndex++; // Insert after children: [
  block.add('          const SizedBox(height: 8),');
  lines.insertAll(insertIndex, block);

  await file.writeAsString(lines.join('\n'));
  print("Success");
}
