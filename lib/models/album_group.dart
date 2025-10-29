import 'track.dart';

/// Internal model for grouping tracks by album while parsing M3U files
class AlbumGroup {
  String title;
  String? coverUrl;
  List<Track> tracks = [];

  AlbumGroup(this.title, this.coverUrl);
}