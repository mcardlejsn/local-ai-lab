import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/hugging_face_model_metadata.dart';

typedef HuggingFaceJsonFetcher = Future<Object?> Function(Uri uri);

class HuggingFaceDiscoveryException implements Exception {
  const HuggingFaceDiscoveryException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Anonymous, read-only access to documented Hugging Face model metadata.
///
/// Constructing this service performs no network activity. A request occurs
/// only when [searchPublicGgufRepositories] or [getRepositoryMetadata] is
/// explicitly called. Nothing in the running app calls this service yet.
class HuggingFaceDiscoveryService {
  HuggingFaceDiscoveryService({
    HuggingFaceJsonFetcher? fetchJson,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _fetchJsonOverride = fetchJson;

  static const String _host = 'huggingface.co';
  static const String _userAgent =
      'Local-AI-Lab/1.0 (Android; anonymous model discovery)';
  static const int _maximumSearchLimit = 50;

  final HuggingFaceJsonFetcher? _fetchJsonOverride;
  final Duration requestTimeout;

  /// Returns a limited page of recently updated public, ungated GGUF repos.
  /// Detailed access status is checked again by [getRepositoryMetadata].
  Future<List<HuggingFaceRepositorySummary>> searchPublicGgufRepositories({
    int limit = 20,
  }) async {
    if (limit < 1 || limit > _maximumSearchLimit) {
      throw ArgumentError('Search limit must be between 1 and 50.');
    }

    final Uri uri = Uri.https(_host, '/api/models', <String, String>{
      'filter': 'gguf',
      'gated': 'false',
      'sort': 'lastModified',
      'direction': '-1',
      'limit': '$limit',
    });
    final Object? decoded = await _fetchJson(uri);
    if (decoded is! List) {
      throw const HuggingFaceDiscoveryException(
        'Hugging Face returned an invalid model-search response.',
      );
    }

    final List<HuggingFaceRepositorySummary> results =
        <HuggingFaceRepositorySummary>[];
    for (final Object? value in decoded) {
      if (value is! Map) {
        throw const HuggingFaceDiscoveryException(
          'Hugging Face returned an invalid model-search entry.',
        );
      }
      try {
        final HuggingFaceRepositorySummary summary =
            HuggingFaceRepositorySummary.fromJson(
          Map<String, dynamic>.from(value),
        );
        // Do not trust the query filter alone. Silently exclude any restricted
        // result the server includes rather than exposing it to v1 discovery.
        if (summary.isPublicAndUngated) results.add(summary);
      } on FormatException catch (error) {
        throw HuggingFaceDiscoveryException(error.message.toString());
      }
    }
    return List<HuggingFaceRepositorySummary>.unmodifiable(results);
  }

  /// Retrieves exact revision, access, card, and blob metadata for one repo.
  Future<HuggingFaceRepositoryMetadata> getRepositoryMetadata(
    String repositoryId,
  ) async {
    final List<String> parts = _validatedRepositoryParts(repositoryId);
    final Uri uri = Uri(
      scheme: 'https',
      host: _host,
      pathSegments: <String>['api', 'models', ...parts],
      queryParameters: const <String, String>{'blobs': 'true'},
    );
    final Object? decoded = await _fetchJson(uri);
    if (decoded is! Map) {
      throw const HuggingFaceDiscoveryException(
        'Hugging Face returned invalid repository metadata.',
      );
    }

    try {
      return HuggingFaceRepositoryMetadata.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } on FormatException catch (error) {
      throw HuggingFaceDiscoveryException(error.message.toString());
    }
  }

  Future<Object?> _fetchJson(Uri uri) async {
    final HuggingFaceJsonFetcher? override = _fetchJsonOverride;
    if (override != null) return override(uri);

    final HttpClient client = HttpClient()..connectionTimeout = requestTimeout;
    try {
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(requestTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final HttpClientResponse response =
          await request.close().timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HuggingFaceDiscoveryException(
          'Hugging Face metadata request failed with HTTP '
          '${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      final String body =
          await utf8.decoder.bind(response).join().timeout(requestTimeout);
      try {
        return jsonDecode(body);
      } on FormatException {
        throw const HuggingFaceDiscoveryException(
          'Hugging Face returned malformed JSON.',
        );
      }
    } on HuggingFaceDiscoveryException {
      rethrow;
    } on TimeoutException {
      throw const HuggingFaceDiscoveryException(
        'Hugging Face metadata request timed out.',
      );
    } on SocketException catch (error) {
      throw HuggingFaceDiscoveryException(
        'Hugging Face metadata request failed: ${error.message}',
      );
    } on HttpException catch (error) {
      throw HuggingFaceDiscoveryException(
        'Hugging Face metadata request failed: ${error.message}',
      );
    } finally {
      client.close(force: true);
    }
  }

  List<String> _validatedRepositoryParts(String repositoryId) {
    final String trimmed = repositoryId.trim().replaceAll(
          RegExp(r'^/+|/+$'),
          '',
        );
    final List<String> parts = trimmed.split('/');
    if (parts.length != 2 || parts.any((String part) => part.trim().isEmpty)) {
      throw ArgumentError(
        'Repository must use the Hugging Face owner/name form.',
      );
    }
    return parts;
  }
}
