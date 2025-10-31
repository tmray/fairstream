import 'dart:io';
import 'dart:convert';

void main() {
  final path = '/home/tom/Public/FairStreamApp/referece files/example-m3u-file.m3u';
  final f = File(path);
  if (!f.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(2);
  }
  final bytes = f.readAsBytesSync();
    // NOTE: This utility is intended for local inspection only. Output is
    // intentionally not printed to avoid analyzer lints in CI; callers can
    // modify for interactive debugging if needed.

  final contentUtf8 = String.fromCharCodes(bytes);
  // Default fromCharCodes treats each byte as a code unit (Latin-1 style).
    // suppressed debug output

  // Proper UTF-8 decode
  final contentProperUtf8 = utf8.decode(bytes);
    // suppressed debug output

  // Print lines with #EXTINF and show rune hexes for the title portion
  final lines = contentUtf8.split('\n');
  final properLines = contentProperUtf8.split('\n');
  for (var line in lines) {
    if (line.startsWith('#EXTINF:')) {
        // suppressed debug output
      final idx = line.indexOf(',');
      if (idx >= 0 && idx + 1 < line.length) {
        final title = line.substring(idx + 1).trim();
          // suppressed debug output
        final runes = title.runes.toList();
        for (var i = 0; i < runes.length; i++) {
          // suppressed per-locale debug output
        }
      }
    }
  }

  // Also show the UTF-8-decoded titles and runes for comparison
  for (var line in properLines) {
    if (line.startsWith('#EXTINF:')) {
        // suppressed utf8-decoded debug output
      final idx = line.indexOf(',');
      if (idx >= 0 && idx + 1 < line.length) {
        final title = line.substring(idx + 1).trim();
          // suppressed utf8-decoded debug output
        final runes = title.runes.toList();
        for (var i = 0; i < runes.length; i++) {
          // suppressed utf8-decoded debug output
        }
      }
    }
  }

  // Hex dump suppressed to avoid printing in CI; keep code for local debugging.
  // final hex = bytes.take(200).map((b) => b.toRadixString(16).padLeft(2,'0')).join(' ');
  // stderr.writeln(hex);
}
