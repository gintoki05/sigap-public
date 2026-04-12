import 'dart:io';

void main() async {
  var file = File(
    r'c:\Users\ajiep\Documents\Developments\Ajie\sigap\lib\screens\assistant_screen.dart',
  );
  var lines = await file.readAsLines();

  int emergencyIconLine = lines.indexWhere(
    (l) => l.contains('Icons.emergency_share_outlined'),
  );
  if (emergencyIconLine == -1) {
    print('emergency icon not found');
    return;
  }

  int startIdx = -1;
  for (int i = emergencyIconLine; i > 0; i--) {
    if (lines[i].trimLeft().startsWith('Row(')) {
      startIdx = i;
      break;
    }
  }

  int endIdx = -1;
  for (int i = emergencyIconLine; i < lines.length; i++) {
    // Look for the end of the Row
    // The Row contains Expanded containing TextButton then closing tags.
    // It is followed by `if (pendingPhoto != null)`
    if (lines[i].contains('child: const Text(\'Ubah\'),')) {
      for (int j = i; j < i + 10; j++) {
        if (lines[j].trim() == '],') {
          // next line should be ),
          if (lines[j + 1].trim() == '),') {
            endIdx = j + 4; // ), ), ], )
            break;
          }
        }
      }
      break;
    }
  }

  if (startIdx == -1 || endIdx == -1) {
    print('Failed. start: $startIdx, end: $endIdx');
    return;
  }

  print('Extract from \$startIdx to \$endIdx');

  var block = lines.sublist(startIdx, endIdx + 1);
  lines.removeRange(startIdx, endIdx + 1);

  int insertIdx = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains('return SingleChildScrollView(') ||
        lines[i].contains('child: Column(')) {
      for (int j = i; j < i + 10; j++) {
        if (lines[j].contains('children: [')) {
          insertIdx = j + 1;
          break;
        }
      }
    }
  }

  if (insertIdx == -1) {
    print('Failed to find insert point');
    return;
  }

  block.add('          const SizedBox(height: 8),');
  lines.insertAll(insertIdx, block);

  await file.writeAsString(lines.join('\n'));
  print('Success');
}
