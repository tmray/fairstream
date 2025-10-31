import 'package:flutter_test/flutter_test.dart';
import 'package:fairstream_app/services/text_normalizer.dart';

void main() {
  test('Track title cleaning removes artist and numeric prefixes', () {
    const artist = "Lorenzo's Music";
    
    // Test case 1: with en-dash
    var title1 = "Lorenzo's Music – 1. With you";
    var cleaned1 = cleanTrackTitle(title1);
    var stripped1 = stripArtistPrefix(cleaned1, artist);
    var final1 = stripped1.replaceFirst(RegExp(r'^(\d+\.\s*|\(\d+\)\s*)'), '');
    expect(final1, 'With you');
    
    // Test case 2: with regular dash
    var title2 = "Lorenzo's Music - 1. With you";
    var cleaned2 = cleanTrackTitle(title2);
    var stripped2 = stripArtistPrefix(cleaned2, artist);
    var final2 = stripped2.replaceFirst(RegExp(r'^(\d+\.\s*|\(\d+\)\s*)'), '');
    expect(final2, 'With you');
    
    // Test case 3: with numeric prefix only
    var title3 = "1. With you";
    var cleaned3 = cleanTrackTitle(title3);
    var stripped3 = stripArtistPrefix(cleaned3, artist);
    var final3 = stripped3.replaceFirst(RegExp(r'^(\d+\.\s*|\(\d+\)\s*)'), '');
    expect(final3, 'With you');
    
    // Test case 4: just song title
    var title4 = "With you";
    var cleaned4 = cleanTrackTitle(title4);
    var stripped4 = stripArtistPrefix(cleaned4, artist);
    var final4 = stripped4.replaceFirst(RegExp(r'^(\d+\.\s*|\(\d+\)\s*)'), '');
    expect(final4, 'With you');
  });
}
