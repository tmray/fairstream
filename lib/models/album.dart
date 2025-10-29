import 'track.dart';

class Album {
  final String id;
  final String title;
  final String artist;
  final String? coverUrl;
  final List<Track> tracks;
  final String? description;
  final String? published;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.coverUrl,
    required this.tracks,
    this.description,
    this.published,
  });

  factory Album.fromMap(Map<String, dynamic> m) => Album(
        id: m['id'],
        title: m['title'],
        artist: m['artist'],
        coverUrl: m['coverUrl'],
        tracks: (m['tracks'] as List<dynamic>?)?.map((e) => Track.fromMap(e as Map<String, dynamic>)).toList() ?? [],
        description: m['description'],
        published: m['published'],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'coverUrl': coverUrl,
        'tracks': tracks.map((t) => t.toMap()).toList(),
        'description': description,
        'published': published,
      };
}
