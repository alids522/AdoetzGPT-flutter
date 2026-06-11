import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> downloadFile(String filename, List<int> bytes) async {
  final uint8List = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final blob = web.Blob([uint8List.toJS].toJS, web.BlobPropertyBag(type: 'application/octet-stream'));
  final url = web.URL.createObjectURL(blob);
  
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
    
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  
  web.URL.revokeObjectURL(url);
}
