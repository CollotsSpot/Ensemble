enum MediaType {
  artist,
  album,
  track,
  playlist,
  radio,
  audiobook,
  chapter,
  podcast,
  podcastEpisode,
}

/// Parse a media item JSON map into the appropriate model type.
MediaItem parseMediaItemJson(Map<String, dynamic> json) {
  final mediaTypeStr = (json['media_type'] as String?)?.toLowerCase();
  switch (mediaTypeStr) {
    case 'artist':
      return Artist.fromJson(json);
    case 'album':
      return Album.fromJson(json);
    case 'track':
      return Track.fromJson(json);
    case 'playlist':
      return Playlist.fromJson(json);
    case 'audiobook':
      return Audiobook.fromJson(json);
    case 'radio':
      return MediaItem.fromJson(json);
    case 'podcast':
    case 'podcast_episode':
    default:
      return MediaItem.fromJson(json);
  }
}

class ProviderMapping {
  final String itemId;
  final String providerDomain;
  final String providerInstance;
  final bool available;
  final Map<String, dynamic>? audioFormat;
  /// Whether this item is in the library for this specific provider instance.
  /// True = this provider "owns" the item (user added it from this account)
  /// False = item exists but wasn't added from this provider
  final bool inLibrary;

  ProviderMapping({
    required this.itemId,
    required this.providerDomain,
    required this.providerInstance,
    required this.available,
    this.audioFormat,
    this.inLibrary = true,
  });

  factory ProviderMapping.fromJson(Map<String, dynamic> json) {
    return ProviderMapping(
      itemId: json['item_id'] as String? ?? '',
      providerDomain: json['provider_domain'] as String? ?? '',
      providerInstance: json['provider_instance'] as String? ?? '',
      available: json['available'] as bool? ?? true,
      audioFormat: json['audio_format'] as Map<String, dynamic>?,
      // Parse in_library field - MA uses 1/0 or true/false
      inLibrary: json['in_library'] == true || json['in_library'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'provider_domain': providerDomain,
      'provider_instance': providerInstance,
      'available': available,
      if (audioFormat != null) 'audio_format': audioFormat,
      'in_library': inLibrary,
    };
  }
}

class MediaItem {
  final String itemId;
  final String provider;
  final String name;
  final MediaType mediaType;
  final String? sortName;
  final String? uri;
  final List<ProviderMapping>? providerMappings;
  final Map<String, dynamic>? metadata;
  final bool? favorite;
  final int? position;
  final Duration? duration;

  MediaItem({
    required this.itemId,
    required this.provider,
    required this.name,
    required this.mediaType,
    this.sortName,
    this.uri,
    this.providerMappings,
    this.metadata,
    this.favorite,
    this.position,
    this.duration,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    MediaType? mediaType;
    final mediaTypeStr = json['media_type'] as String?;
    if (mediaTypeStr != null) {
      mediaType = MediaType.values.firstWhere(
        (e) => e.name == mediaTypeStr.toLowerCase(),
        orElse: () => MediaType.track,
      );
    }

    return MediaItem(
      itemId: json['item_id']?.toString() ?? json['id']?.toString() ?? '',
      provider: json['provider'] as String? ?? 'unknown',
      name: json['name'] as String? ?? '',
      mediaType: mediaType ?? MediaType.track,
      sortName: json['sort_name'] as String?,
      uri: json['uri'] as String?,
      providerMappings: (json['provider_mappings'] as List<dynamic>?)
          ?.map((e) => ProviderMapping.fromJson(e as Map<String, dynamic>))
          .toList(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      favorite: json['favorite'] as bool?,
      position: json['position'] as int?,
      duration: json['duration'] != null
          ? Duration(seconds: (json['duration'] as num).toInt())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'provider': provider,
      'name': name,
      'media_type': mediaType.name,
      if (sortName != null) 'sort_name': sortName,
      if (uri != null) 'uri': uri,
      if (providerMappings != null)
        'provider_mappings': providerMappings!.map((m) => m.toJson()).toList(),
      if (metadata != null) 'metadata': metadata,
      if (favorite != null) 'favorite': favorite,
      if (position != null) 'position': position,
      if (duration != null) 'duration': duration!.inSeconds,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaItem &&
          runtimeType == other.runtimeType &&
          itemId == other.itemId &&
          provider == other.provider;

  @override
  int get hashCode => Object.hash(itemId, provider);

  /// Check if this item is in the user's library
  bool get inLibrary {
    if (provider == 'library') return true;
    return providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
  }
}

class Artist extends MediaItem {
  Artist({
    required super.itemId,
    required super.provider,
    required super.name,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
  }) : super(mediaType: MediaType.artist);

  factory Artist.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    return Artist(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
    );
  }

  /// Check if this artist is in the user's library
  bool get inLibrary {
    if (provider == 'library') return true;
    return providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
  }

  @override
  Map<String, dynamic> toJson() => super.toJson();
}

class Album extends MediaItem {
  final List<Artist>? artists;
  final String? albumType;
  final int? year;

  Album({
    required super.itemId,
    required super.provider,
    required super.name,
    this.artists,
    this.albumType,
    this.year,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
  }) : super(mediaType: MediaType.album);

  factory Album.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    // Parse year - can be int or null
    int? year;
    final yearValue = json['year'];
    if (yearValue is int) {
      year = yearValue;
    } else if (yearValue is String) {
      year = int.tryParse(yearValue);
    }

    return Album(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      artists: (json['artists'] as List<dynamic>?)
          ?.map((e) => Artist.fromJson(e as Map<String, dynamic>))
          .toList(),
      albumType: json['album_type'] as String?,
      year: year,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
    );
  }

  String get artistsString =>
      artists?.map((a) => a.name).join(', ') ?? 'Unknown Artist';

  /// Get album name with year appended (e.g., "Album Name (2023)")
  String get nameWithYear {
    return year != null ? '$name ($year)' : name;
  }

  /// Check if this album is in the user's library
  bool get inLibrary {
    if (provider == 'library') return true;
    return providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (artists != null) {
      json['artists'] = artists!.map((a) => a.toJson()).toList();
    }
    if (albumType != null) json['album_type'] = albumType;
    if (year != null) json['year'] = year;
    return json;
  }
}

class Track extends MediaItem {
  final List<Artist>? artists;
  final Album? album;

  Track({
    required super.itemId,
    required super.provider,
    required super.name,
    this.artists,
    this.album,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
    super.position,
    super.duration,
  }) : super(mediaType: MediaType.track);

  factory Track.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    return Track(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      artists: (json['artists'] as List<dynamic>?)
          ?.map((e) => Artist.fromJson(e as Map<String, dynamic>))
          .toList(),
      album: json['album'] != null
          ? Album.fromJson(json['album'] as Map<String, dynamic>)
          : null,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
      position: item.position,
      duration: item.duration,
    );
  }

  String get artistsString =>
      artists?.map((a) => a.name).join(', ') ?? 'Unknown Artist';

  /// Check if this track is in the user's library
  bool get inLibrary {
    if (provider == 'library') return true;
    return providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (artists != null) {
      json['artists'] = artists!.map((a) => a.toJson()).toList();
    }
    if (album != null) json['album'] = album!.toJson();
    return json;
  }
}

class Playlist extends MediaItem {
  final String? owner;
  final bool? isEditable;
  final int? trackCount;

  Playlist({
    required super.itemId,
    required super.provider,
    required super.name,
    this.owner,
    this.isEditable,
    this.trackCount,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
  }) : super(mediaType: MediaType.playlist);

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    return Playlist(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      owner: json['owner'] as String?,
      isEditable: json['is_editable'] as bool?,
      trackCount: json['track_count'] as int?,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
    );
  }

  /// Check if this playlist is in the user's library
  bool get inLibrary {
    if (provider == 'library') return true;
    return providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (owner != null) json['owner'] = owner;
    if (isEditable != null) json['is_editable'] = isEditable;
    if (trackCount != null) json['track_count'] = trackCount;
    return json;
  }
}

class Chapter {
  final int chapterNumber;
  final int positionMs;
  final String title;
  final Duration? duration;

  Chapter({
    required this.chapterNumber,
    required this.positionMs,
    required this.title,
    this.duration,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    // MA API returns chapters with format:
    // {position: 1, name: "Opening Credits", start: 0.0, end: 17.6}
    // We need to handle both this format and potential others

    // Get chapter number (MA uses 'position' for chapter number)
    int chapterNum = 0;
    if (json['position'] is int) {
      chapterNum = json['position'] as int;
    } else if (json['chapter_number'] is int) {
      chapterNum = json['chapter_number'] as int;
    } else if (json['chapter_id'] is int) {
      chapterNum = json['chapter_id'] as int;
    }

    // Get position in milliseconds (MA uses 'start' in seconds)
    int posMs = 0;
    if (json['start'] != null) {
      // MA provides start time in seconds (can be double)
      posMs = ((json['start'] as num) * 1000).toInt();
    } else if (json['position_ms'] != null) {
      posMs = json['position_ms'] as int;
    }

    // Get title (MA uses 'name')
    String title = json['name'] as String? ??
                   json['title'] as String? ??
                   'Chapter $chapterNum';

    // Calculate duration from start/end if available
    Duration? dur;
    if (json['start'] != null && json['end'] != null) {
      final startSec = (json['start'] as num).toDouble();
      final endSec = (json['end'] as num).toDouble();
      dur = Duration(milliseconds: ((endSec - startSec) * 1000).toInt());
    } else if (json['duration'] != null) {
      dur = Duration(seconds: (json['duration'] as num).toInt());
    }

    return Chapter(
      chapterNumber: chapterNum,
      positionMs: posMs,
      title: title,
      duration: dur,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chapter_number': chapterNumber,
      'position_ms': positionMs,
      'title': title,
      if (duration != null) 'duration': duration!.inSeconds,
    };
  }
}

class Audiobook extends MediaItem {
  final List<Artist>? authors;
  final List<Artist>? narrators;
  final String? publisher;
  final String? description;
  final int? year;
  final List<Chapter>? chapters;
  final int? resumePositionMs;
  final bool? fullyPlayed;
  /// Browse order from API - used as fallback for series sequencing
  final int? browseOrder;

  Audiobook({
    required super.itemId,
    required super.provider,
    required super.name,
    this.authors,
    this.narrators,
    this.publisher,
    this.description,
    this.year,
    this.chapters,
    this.resumePositionMs,
    this.fullyPlayed,
    this.browseOrder,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
    super.duration,
  }) : super(mediaType: MediaType.audiobook);

  factory Audiobook.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);

    // Parse year - check top level first, then metadata.release_date (ABS format)
    int? year;
    final metadata = json['metadata'] as Map<String, dynamic>?;
    dynamic yearValue = json['year'];
    if (yearValue == null && metadata != null) {
      // ABS stores year in metadata.release_date (can be "2024" or "2024-01-15")
      final releaseDate = metadata['release_date'];
      if (releaseDate is String && releaseDate.isNotEmpty) {
        // Extract year from date string (handles both "2024" and "2024-01-15" formats)
        yearValue = releaseDate.split('-').first;
      } else if (releaseDate is int) {
        yearValue = releaseDate;
      }
    }
    if (yearValue is int) {
      year = yearValue;
    } else if (yearValue is String) {
      year = int.tryParse(yearValue);
    }

    // Helper to parse authors/narrators that can be either strings or Artist objects
    List<Artist>? parseArtistList(dynamic data) {
      if (data == null) return null;
      if (data is! List) return null;

      return data.map((e) {
        if (e is String) {
          // MA returns just the name as a string
          return Artist(
            itemId: '',
            provider: 'library',
            name: e,
          );
        } else if (e is Map<String, dynamic>) {
          // Full Artist object
          return Artist.fromJson(e);
        }
        return Artist(itemId: '', provider: 'library', name: 'Unknown');
      }).toList();
    }

    // Parse chapters - check top level first, then metadata
    List<Chapter>? chapters;
    dynamic chaptersData = json['chapters'];
    if (chaptersData == null && metadata != null) {
      chaptersData = metadata['chapters'];
    }

    if (chaptersData is List && chaptersData.isNotEmpty) {
      chapters = chaptersData
          .map((e) => Chapter.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // Parse description - check top level first, then metadata
    String? description = json['description'] as String?;
    if (description == null && metadata != null) {
      description = metadata['description'] as String?;
    }

    return Audiobook(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      authors: parseArtistList(json['authors']),
      narrators: parseArtistList(json['narrators']),
      publisher: json['publisher'] as String?,
      description: description,
      year: year,
      chapters: chapters,
      resumePositionMs: json['resume_position_ms'] as int?,
      fullyPlayed: json['fully_played'] as bool?,
      browseOrder: json['_browse_order'] as int?,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
      duration: item.duration,
    );
  }

  String get authorsString =>
      authors?.map((a) => a.name).join(', ') ?? 'Unknown Author';

  String get narratorsString =>
      narrators?.map((n) => n.name).join(', ') ?? 'Unknown Narrator';

  /// Check if this audiobook is in the user's library
  bool get inLibrary {
    if (provider == 'library') return true;
    return providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
  }

  /// Get progress as a percentage (0.0 to 1.0)
  double get progress {
    if (fullyPlayed == true) return 1.0;
    if (resumePositionMs == null || duration == null) return 0.0;
    final totalMs = duration!.inMilliseconds;
    if (totalMs == 0) return 0.0;
    return (resumePositionMs! / totalMs).clamp(0.0, 1.0);
  }

  /// Get series sequence number from metadata (for sorting within a series)
  /// Tries various metadata fields commonly used by audiobook providers
  double? get seriesSequence {
    // First try the parent's position field (used by MA browse results)
    if (position != null) return position!.toDouble();

    // Try extracting number from sort_name (e.g., "01 - Book Title" or "Book 1")
    if (sortName != null && sortName!.isNotEmpty) {
      // Try to extract leading number
      final match = RegExp(r'^(\d+)').firstMatch(sortName!);
      if (match != null) {
        return double.tryParse(match.group(1)!);
      }
      // Try to extract "Book N" pattern
      final bookMatch = RegExp(r'[Bb]ook\s*(\d+)').firstMatch(sortName!);
      if (bookMatch != null) {
        return double.tryParse(bookMatch.group(1)!);
      }
    }

    // Try extracting from the name itself
    final nameMatch = RegExp(r'^(\d+)').firstMatch(name);
    if (nameMatch != null) {
      return double.tryParse(nameMatch.group(1)!);
    }
    final bookNameMatch = RegExp(r'[Bb]ook\s*(\d+)').firstMatch(name);
    if (bookNameMatch != null) {
      return double.tryParse(bookNameMatch.group(1)!);
    }

    if (metadata == null) return null;

    // Try common metadata fields for series sequence
    final seq = metadata!['sequence'] ??
                metadata!['series_sequence'] ??
                metadata!['series_number'] ??
                metadata!['position'] ??
                metadata!['sort_order'] ??
                metadata!['order'];

    if (seq is num) return seq.toDouble();
    if (seq is String) return double.tryParse(seq);

    // Check if there's a series object with sequence
    final series = metadata!['series'];
    if (series is Map) {
      final seriesSeq = series['sequence'] ?? series['number'] ?? series['order'];
      if (seriesSeq is num) return seriesSeq.toDouble();
      if (seriesSeq is String) return double.tryParse(seriesSeq);
    }
    if (series is List && series.isNotEmpty) {
      final first = series.first;
      if (first is Map) {
        final seriesSeq = first['sequence'] ?? first['number'] ?? first['order'];
        if (seriesSeq is num) return seriesSeq.toDouble();
        if (seriesSeq is String) return double.tryParse(seriesSeq);
      }
    }

    // Last resort: use browse order from API (preserves MA/Audiobookshelf order)
    if (browseOrder != null) return browseOrder!.toDouble();

    return null;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (authors != null) {
      json['authors'] = authors!.map((a) => a.toJson()).toList();
    }
    if (narrators != null) {
      json['narrators'] = narrators!.map((n) => n.toJson()).toList();
    }
    if (publisher != null) json['publisher'] = publisher;
    if (description != null) json['description'] = description;
    if (year != null) json['year'] = year;
    if (chapters != null) {
      json['chapters'] = chapters!.map((c) => c.toJson()).toList();
    }
    if (resumePositionMs != null) json['resume_position_ms'] = resumePositionMs;
    if (fullyPlayed != null) json['fully_played'] = fullyPlayed;
    if (browseOrder != null) json['_browse_order'] = browseOrder;
    return json;
  }
}

/// Represents a browseable folder in Music Assistant (providers, series, authors, etc.)
class BrowseFolder {
  final String path;
  final String name;
  final String? label;
  final String? thumbnailUrl;
  final bool canExpand;
  final List<MediaItem>? items;

  BrowseFolder({
    required this.path,
    required this.name,
    this.label,
    this.thumbnailUrl,
    this.canExpand = true,
    this.items,
  });

  factory BrowseFolder.fromJson(Map<String, dynamic> json) {
    // MA returns either a BrowseFolder or a MediaItem
    // BrowseFolder has 'path' and 'name', MediaItem has 'item_id' and 'media_type'
    return BrowseFolder(
      path: json['path'] as String? ?? json['uri'] as String? ?? '',
      name: json['name'] as String? ?? json['label'] as String? ?? 'Unknown',
      label: json['label'] as String?,
      thumbnailUrl: _extractThumbnail(json),
      canExpand: json['can_expand'] as bool? ?? true,
    );
  }

  static String? _extractThumbnail(Map<String, dynamic> json) {
    // Check for image in metadata
    final metadata = json['metadata'] as Map<String, dynamic>?;
    if (metadata != null) {
      final images = metadata['images'] as List<dynamic>?;
      if (images != null && images.isNotEmpty) {
        final first = images.first as Map<String, dynamic>;
        return first['path'] as String?;
      }
    }
    // Check for direct thumbnail
    return json['thumbnail'] as String? ?? json['image'] as String?;
  }
}

/// Represents an audiobook series
class AudiobookSeries {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final List<Audiobook>? books;
  final int? bookCount;

  AudiobookSeries({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.books,
    this.bookCount,
  });

  factory AudiobookSeries.fromBrowseFolder(BrowseFolder folder) {
    return AudiobookSeries(
      id: folder.path,
      name: folder.name,
      thumbnailUrl: folder.thumbnailUrl,
    );
  }

  factory AudiobookSeries.fromJson(Map<String, dynamic> json) {
    return AudiobookSeries(
      id: json['path'] as String? ?? json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['label'] as String? ?? 'Unknown Series',
      thumbnailUrl: BrowseFolder._extractThumbnail(json),
      bookCount: json['book_count'] as int?,
    );
  }
}
