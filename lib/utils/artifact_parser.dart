class ArtifactParser {
  /// Parses a markdown string and extracts files defined by `// file: ...` or `<!-- file: ... -->`
  /// Returns a map of filename to file content.
  static Map<String, String> parseFiles(String markdown) {
    final files = <String, String>{};
    final fence = RegExp(r'```([^\n`]*)\n?([\s\S]*?)```');
    
    for (final match in fence.allMatches(markdown)) {
      final content = match.group(2)?.trim() ?? '';
      if (content.isEmpty) continue;

      // Look for a file header comment in the first few lines
      final lines = content.split('\n').take(5).toList();
      String? filename;
      
      for (final line in lines) {
        final trimmed = line.trim();
        final fileMatch = RegExp(r'(?://|<!--|/\*)\s*file:\s*([^\s>]+)').firstMatch(trimmed);
        if (fileMatch != null) {
          filename = fileMatch.group(1);
          break;
        } else if (trimmed.startsWith('file: ')) {
          filename = trimmed.substring(6).trim();
          break;
        }
      }

      if (filename == null || filename.isEmpty) {
        // Fallback: Infer from language tag if missing
        final language = match.group(1)?.trim().toLowerCase() ?? '';
        if (language == 'html') {
          filename = 'index.html';
        } else if (language == 'css') {
          filename = 'styles.css';
        } else if (language == 'js' || language == 'javascript') {
          filename = 'script.js';
        } else if (language == 'dart') {
          filename = 'main.dart';
        } else if (language == 'py' || language == 'python') {
          filename = 'main.py';
        }
      }

      if (filename != null && filename.isNotEmpty) {
        files[filename] = content;
      }
    }
    
    return files;
  }
}
