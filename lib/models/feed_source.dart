class FeedSource {
  final String id;
  final String url;
  final String name;
  final String? imageUrl;
  final DateTime addedAt;

  FeedSource({required this.id, required this.url, required this.name, this.imageUrl, required this.addedAt});

  factory FeedSource.fromMap(Map<String, dynamic> m) => FeedSource(
        id: m['id'],
        url: m['url'],
        name: m['name'],
        imageUrl: m['imageUrl'],
        addedAt: DateTime.parse(m['addedAt']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'url': url,
        'name': name,
        'imageUrl': imageUrl,
        'addedAt': addedAt.toIso8601String(),
      };
}
