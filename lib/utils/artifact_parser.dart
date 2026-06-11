class ArtifactParser {
  /// Parses a markdown string and extracts files defined by `// file: ...` or `<!-- file: ... -->`
  /// Returns a map of filename to file content.
  static Map<String, String> parseFiles(String markdown) {
    final files = <String, String>{};
    final fence = RegExp(r'```([^\n`]*)\n?([\s\S]*?)```');
    
    for (final match in fence.allMatches(markdown)) {
      final content = match.group(2)?.trim() ?? '';
      if (content.isEmpty) continue;

      // Look for a file header comment like `// file: index.html` or `<!-- file: style.css -->`
      final firstLine = content.split('\n').first.trim();
      String? filename;
      
      final fileMatch = RegExp(r'(?://|<!--|/\*)\s*file:\s*([^\s>]+)').firstMatch(firstLine);
      if (fileMatch != null) {
        filename = fileMatch.group(1);
      } else if (firstLine.startsWith('file: ')) {
        filename = firstLine.substring(6).trim();
      }

      if (filename != null && filename.isNotEmpty) {
        files[filename] = content;
      }
    }
    
    return files;
  }
}
