import 'package:flutter_test/flutter_test.dart';
import 'package:fairstream_app/services/text_normalizer.dart';

void main() {
  test('cleanHtmlContent removes tags and normalizes spaces', () {
    final input = '<p>Hello&nbsp;World\u200B</p>';
    final out = cleanHtmlContent(input);
    expect(out, 'Hello World');
  });

  test('cleanTrackTitle normalizes en-dash and mojibake', () {
    final input = 'Lorenzo\u2013 Friction';
    final out = cleanTrackTitle(input);
    expect(out, 'Lorenzo - Friction');

    final mojibake = "Lorenzoâ€™s Song";
    final out2 = cleanTrackTitle(mojibake);
    expect(out2.contains("Lorenzo"), true);
  });

  test('stripArtistPrefix removes artist and separators safely', () {
    final artist = "Lorenzo's Music";
    final title = "Lorenzo's Music \u2013 Friction"; // en-dash
    final stripped = stripArtistPrefix(title, artist);
    expect(stripped, 'Friction');

    final weird = "Lorenzo's Music â Friction"; // mojibake artifact
    final stripped2 = stripArtistPrefix(weird, artist);
    expect(stripped2, 'Friction');
  });
}
