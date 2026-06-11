import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Future<void> downloadFile(String filename, List<int> bytes) async {
  try {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
    } else if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    } else {
      dir = await getDownloadsDirectory();
    }
    
    // Fallback if null
    dir ??= await getApplicationDocumentsDirectory();

    String path = '${dir.path}/$filename';
    int counter = 1;
    // ensure unique filename
    while (await File(path).exists()) {
      final parts = filename.split('.');
      final ext = parts.length > 1 ? '.${parts.last}' : '';
      final name = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : filename;
      path = '${dir.path}/${name}_$counter$ext';
      counter++;
    }

    final file = File(path);
    await file.writeAsBytes(bytes);
  } catch (e) {
    // Handle error or just ignore
    debugPrint('Error saving file: $e');
  }
}
