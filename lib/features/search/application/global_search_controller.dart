import 'package:flutter/foundation.dart';

enum SearchEntityType {
  task,
  project,
  tag,
}

class GlobalSearchResult {
  final String id;
  final SearchEntityType type;
  final String title;
  final String subtitle;

  const GlobalSearchResult({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
  });
}

abstract interface class GlobalSearchSource {
  Future<List<GlobalSearchResult>> search(String query);
}

class GlobalSearchController extends ChangeNotifier {
  final GlobalSearchSource source;

  List<GlobalSearchResult> results = const [];
  bool isLoading = false;
  Object? error;

  int _requestVersion = 0;

  GlobalSearchController({
    required this.source,
  });

  Future<void> search(String query) async {
    final normalized = query.trim();
    final version = ++_requestVersion;
    error = null;

    if (normalized.isEmpty) {
      isLoading = false;
      results = const [];
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      final next = await source.search(normalized);
      if (version != _requestVersion) {
        return;
      }
      results = List.unmodifiable(next);
    } catch (caught) {
      if (version != _requestVersion) {
        return;
      }
      error = caught;
      results = const [];
    } finally {
      if (version == _requestVersion) {
        isLoading = false;
        notifyListeners();
      }
    }
  }
}
