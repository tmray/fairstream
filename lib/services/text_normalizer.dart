import 'package:html_unescape/html_unescape.dart';

final _htmlUnescape = HtmlUnescape();

/// Clean HTML-ish content: strip tags, unescape entities, normalize spaces and
/// common unicode artifacts (NBSP, BOM, various dashes, zero-width marks).
String cleanHtmlContent(String? html) {
  if (html == null || html.isEmpty) return '';

  var text = html.replaceAll(RegExp(r'<[^>]*>'), '');
  text = _htmlUnescape.convert(text);

  // Replace all dash variants and mojibake with a plain ASCII hyphen
  text = text
    // Ensure common single-character dash variants are explicitly mapped to
    // the ASCII hyphen. This avoids confusion between U+2013 (en-dash)
    // and U+002D (hyphen-minus) in downstream processing.
    .replaceAll('\u2013', '-')
    .replaceAll('\u2014', '-')
    .replaceAll(RegExp(r'[\u2010-\u2015\u2013\u2014\u2012\u2011\u2015\u2212\uFE58\uFE63\uFF0D]'), '-') // Unicode dashes
    .replaceAll('â', '-')
    .replaceAll('Â', '-')
    .replaceAll('\u00A0', ' ')
    .replaceAll(RegExp(r'[\u200B-\u200F]'), '')
    .replaceAll('\uFEFF', '');

  // Remove replacement characters and control characters that can render
  // as boxes (U+FFFD) or other non-printables.
  text = text.replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F\uFFFD]'), '');
  // Remove stray euro or other lingering mojibake fragments often seen after
  // incorrect decodes (e.g. "€“ or standalone "€")
  text = text.replaceAll('€“', '-').replaceAll('€', '');

  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

/// More aggressive track-title cleaning. Normalizes quotes/dashes and removes
/// common mojibake sequences like â€™, Â etc.
String cleanTrackTitle(String? title) {
  if (title == null || title.isEmpty) return '';
  var text = cleanHtmlContent(title);

  text = text
    .replaceAll(RegExp(r'[\u2010-\u2015\u2013\u2014\u2012\u2011\u2015\u2212\uFE58\uFE63\uFF0D]'), '-') // Unicode dashes
    .replaceAll('â', '-')
    .replaceAll('Â', '-')
    .replaceAll('â€™', "'")
    .replaceAll('â€˜', "'")
    .replaceAll('â€œ', '"')
    .replaceAll('â€', '')
    .replaceAll('€"', '')
    .replaceAll('\u2018', "'")
    .replaceAll('\u2019', "'")
    .replaceAll('\u201C', '"')
    .replaceAll('\u201D', '"')
    ;

  text = text.replaceAll(RegExp(r'[\u00A0\u2000-\u200A\u202F\u205F\u3000]'), ' ');
  text = text.replaceAll(RegExp(r'[\u200B-\u200F\uFEFF]'), '');

  // Remove extra spaces around dashes
  text = text.replaceAll(RegExp(r'\s*-\s*'), '-');
  text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  return text;
}

/// Safely remove an artist prefix from a title without slicing multi-byte
/// characters. Works on Dart strings. Removes a run of leading separators
/// and artifact characters after the artist name.
String stripArtistPrefix(String title, String artist) {
  if (artist.isEmpty) return title;
  if (!title.startsWith(artist)) return title;

  var rem = title.substring(artist.length);
  final sepLeading = RegExp(r'^[\s\-\u2010-\u2015\u2013\u2014\u00A0\uFEFFâÂ\u2018\u2019\u201C\u201D\"\,\:]*');
  rem = rem.replaceFirst(sepLeading, '');
  return rem.trimLeft();
}
