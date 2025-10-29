class Track {
  final String id;
  final String title;
  final String url;
  final int durationSeconds;

  Track({required this.id, required this.title, required this.url, required this.durationSeconds});

  factory Track.fromMap(Map<String, dynamic> m) => Track(
        id: m['id'],
        title: m['title'],
        url: m['url'],
        durationSeconds: m['durationSeconds'] ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'url': url,
        'durationSeconds': durationSeconds,
      };
}
