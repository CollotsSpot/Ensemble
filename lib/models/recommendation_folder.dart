import 'media_item.dart';

class RecommendationFolder {
  final String itemId;
  final String provider;
  final String name;
  final String? uri;
  final List<MediaItem> items;

  RecommendationFolder({
    required this.itemId,
    required this.provider,
    required this.name,
    this.uri,
    required this.items,
  });

  factory RecommendationFolder.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>?;
    final parsedItems = itemsJson
        ?.whereType<Map<String, dynamic>>()
        .map(parseMediaItemJson)
        .toList() ?? <MediaItem>[];

    return RecommendationFolder(
      itemId: json['item_id']?.toString() ?? json['id']?.toString() ?? '',
      provider: json['provider'] as String? ?? 'unknown',
      name: json['name'] as String? ?? '',
      uri: json['uri'] as String?,
      items: parsedItems,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'provider': provider,
      'name': name,
      if (uri != null) 'uri': uri,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}
