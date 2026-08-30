import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_discovery_result.dart';
import '../services/gguf_discovery_cache_service.dart';
import '../services/gguf_discovery_service.dart';
import '../services/gguf_discovery_seed_service.dart';
import '../services/gguf_install_registry_service.dart';
import '../services/hugging_face_discovery_service.dart';
import '../services/model_download_service.dart';

typedef ExternalUriLauncher = Future<bool> Function(Uri uri);

/// Displays GGUF discovery results produced by an explicit user action.
///
/// Opening this screen performs no network request. The discovery service is
/// called only from [_discover], which is wired exclusively to the Discover
/// button. The last successful result may be restored from an app-private
/// local cache. Candidate downloads require a second explicit confirmation.
class GgufDiscoveryScreen extends StatefulWidget {
  const GgufDiscoveryScreen({
    super.key,
    this.embedded = false,
    this.discoveryService,
    this.discoveryCache,
    this.downloadService,
    this.installRegistry,
    this.onModelInstalled,
    this.externalUriLauncher,
  });

  /// Omits the standalone scaffold and app bar when the discovery experience
  /// is presented as the Candidates section of the Models screen.
  final bool embedded;

  /// Injectable so widget tests can provide deterministic, offline responses.
  final GgufDiscoveryService? discoveryService;

  /// Injectable so widget tests can avoid app-private filesystem access.
  final GgufDiscoveryCache? discoveryCache;

  /// Injectable so widget tests never touch Android storage or the network.
  final ModelDownloadService? downloadService;

  /// Records source identity only after a Candidate passes download
  /// verification. Injectable so widget tests avoid app-private storage.
  final GgufInstallRegistry? installRegistry;

  /// Called after an exact candidate artifact is installed successfully.
  final Future<void> Function()? onModelInstalled;

  /// Injectable so widget tests never open an external application.
  final ExternalUriLauncher? externalUriLauncher;

  @override
  State<GgufDiscoveryScreen> createState() => _GgufDiscoveryScreenState();
}

class _GgufDiscoveryScreenState extends State<GgufDiscoveryScreen> {
  static const Color _bgColor = Color(0xFF121212);
  static const Color _surfaceColor = Color(0xFF1E1E1E);
  static const Color _accentBlue = Color(0xFF90CAF9);
  static const Color _candidateGreen = Color(0xFF81C784);
  static const Color _reviewAmber = Color(0xFFFFCC80);
  static const Color _rejectedRed = Color(0xFFEF9A9A);

  late final GgufDiscoveryService _discoveryService;
  late final GgufDiscoveryCache _discoveryCache;
  late final ModelDownloadService _downloadService;
  late final GgufInstallRegistry _installRegistry;
  late final ExternalUriLauncher _externalUriLauncher;
  GgufDiscoveryResult? _result;
  DateTime? _lastRefreshedUtc;
  String? _errorMessage;
  bool _isDiscovering = false;
  bool _isVerifyingInstalledModels = false;
  int _discoveryGeneration = 0;
  final Map<String, _CandidateDownloadState> _downloadStates =
      <String, _CandidateDownloadState>{};

  bool get _hasActiveDownload =>
      _downloadStates.values.any((state) => state.isDownloading);

  @override
  void initState() {
    super.initState();
    _discoveryService = widget.discoveryService ?? GgufDiscoveryService();
    _discoveryCache = widget.discoveryCache ?? GgufDiscoveryCacheService();
    _downloadService = widget.downloadService ?? ModelDownloadService();
    _installRegistry = widget.installRegistry ?? GgufInstallRegistryService();
    _externalUriLauncher = widget.externalUriLauncher ?? _launchExternalUri;
    unawaited(_restoreCachedDiscovery());
  }

  Future<bool> _launchExternalUri(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    for (final _CandidateDownloadState state in _downloadStates.values) {
      state.cancelToken?.cancel();
    }
    super.dispose();
  }

  Future<void> _discover() async {
    if (_isDiscovering || _isVerifyingInstalledModels || _hasActiveDownload) {
      return;
    }
    final int generation = ++_discoveryGeneration;
    setState(() {
      _isDiscovering = true;
      _errorMessage = null;
    });

    try {
      final GgufDiscoveryResult result = await _discoveryService.discover();
      final DateTime discoveredAtUtc = DateTime.now().toUtc();
      await _saveDiscoveryCache(result, discoveredAtUtc);
      await _publishResultWithCandidateStates(
        result,
        generation,
        discoveredAtUtc: discoveredAtUtc,
      );
    } on HuggingFaceDiscoveryException catch (error) {
      _showFailure(error.message);
    } on GgufDiscoverySeedException catch (error) {
      _showFailure(error.message);
    } on ArgumentError catch (error) {
      _showFailure(
        error.message?.toString() ?? 'The discovery request was invalid.',
      );
    }
  }

  Future<void> _restoreCachedDiscovery() async {
    final int generation = _discoveryGeneration;
    GgufDiscoveryCacheEntry? entry;
    try {
      entry = await _discoveryCache.load();
    } on Object {
      return;
    }
    if (entry == null || !mounted || generation != _discoveryGeneration) {
      return;
    }
    final GgufDiscoveryCacheEntry restored = entry;

    await _publishResultWithCandidateStates(
      restored.result,
      generation,
      discoveredAtUtc: restored.discoveredAtUtc,
    );
  }

  Future<void> _saveDiscoveryCache(
    GgufDiscoveryResult result,
    DateTime discoveredAtUtc,
  ) async {
    try {
      await _discoveryCache.save(result, discoveredAtUtc: discoveredAtUtc);
    } on Object {
      // Discovery remains usable when optional local cache storage fails.
    }
  }

  void _showFailure(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isDiscovering = false;
      _isVerifyingInstalledModels = false;
    });
  }

  Future<void> _publishResultWithCandidateStates(
    GgufDiscoveryResult result,
    int generation, {
    required DateTime discoveredAtUtc,
  }) async {
    final List<GgufCandidateArtifact> artifacts = result.assessments
        .where((assessment) => assessment.canDownload)
        .map((assessment) => assessment.artifact!)
        .toList(growable: false);
    List<GgufCandidateArtifact> savedArtifacts;
    try {
      savedArtifacts = await _installRegistry.load();
    } on Object {
      savedArtifacts = const <GgufCandidateArtifact>[];
    }
    final Map<String, GgufCandidateArtifact> savedByFileName = {
      for (final GgufCandidateArtifact saved in savedArtifacts)
        saved.fileName.toLowerCase(): saved,
    };
    final Map<String, _CandidateDownloadState> preparedStates =
        <String, _CandidateDownloadState>{};
    final List<GgufCandidateArtifact> artifactsToVerify =
        <GgufCandidateArtifact>[];

    for (final GgufCandidateArtifact artifact in artifacts) {
      final InstalledArtifactSizeStatus sizeStatus = await _downloadService
          .installedArtifactSizeStatus(
            fileName: artifact.fileName,
            expectedSizeBytes: artifact.sizeBytes,
          );
      switch (sizeStatus) {
        case InstalledArtifactSizeStatus.absent:
          final int partialBytes = await _downloadService.partialBytes(
            artifact.fileName,
          );
          preparedStates[_artifactKey(artifact)] = _CandidateDownloadState(
            partialBytes: partialBytes,
            receivedBytes: partialBytes,
            totalBytes: artifact.sizeBytes,
          );
          break;
        case InstalledArtifactSizeStatus.matchesExpectedSize:
          final GgufCandidateArtifact? saved =
              savedByFileName[artifact.fileName.toLowerCase()];
          final bool hasMatchingProvenance =
              saved != null && _matchesSavedProvenance(saved, artifact);
          preparedStates[_artifactKey(artifact)] = _CandidateDownloadState(
            isChecking: !hasMatchingProvenance,
            installed: hasMatchingProvenance,
            totalBytes: artifact.sizeBytes,
          );
          artifactsToVerify.add(artifact);
          break;
        case InstalledArtifactSizeStatus.differentSize:
          preparedStates[_artifactKey(artifact)] = _CandidateDownloadState(
            fileConflict: true,
            totalBytes: artifact.sizeBytes,
          );
          break;
        case InstalledArtifactSizeStatus.storageUnavailable:
          preparedStates[_artifactKey(artifact)] = _CandidateDownloadState(
            storageUnavailable: true,
            totalBytes: artifact.sizeBytes,
          );
          break;
      }
    }

    if (!mounted || generation != _discoveryGeneration) return;
    setState(() {
      _result = result;
      _lastRefreshedUtc = discoveredAtUtc;
      _isDiscovering = false;
      _isVerifyingInstalledModels = artifactsToVerify.isNotEmpty;
      _downloadStates
        ..clear()
        ..addAll(preparedStates);
    });
    if (artifactsToVerify.isNotEmpty) {
      unawaited(_verifyCandidateStates(artifactsToVerify, generation));
    }
  }

  bool _matchesSavedProvenance(
    GgufCandidateArtifact saved,
    GgufCandidateArtifact candidate,
  ) {
    return saved.repositoryId.toLowerCase() ==
            candidate.repositoryId.toLowerCase() &&
        saved.fileName.toLowerCase() == candidate.fileName.toLowerCase() &&
        saved.sizeBytes == candidate.sizeBytes &&
        saved.sha256.toLowerCase() == candidate.sha256.toLowerCase();
  }

  Future<void> _verifyCandidateStates(
    List<GgufCandidateArtifact> artifacts,
    int generation,
  ) async {
    for (final GgufCandidateArtifact artifact in artifacts) {
      final _CandidateDownloadState state = await _readArtifactState(artifact);
      if (!mounted || generation != _discoveryGeneration) return;
      setState(() {
        _downloadStates[_artifactKey(artifact)] = state;
      });
    }
    if (!mounted || generation != _discoveryGeneration) return;
    setState(() {
      _isVerifyingInstalledModels = false;
    });
  }

  Future<_CandidateDownloadState> _readArtifactState(
    GgufCandidateArtifact artifact, {
    String? message,
  }) async {
    final InstalledArtifactStatus status = await _downloadService
        .installedArtifactStatus(
          fileName: artifact.fileName,
          expectedSha256: artifact.sha256,
        );
    final int partialBytes = status == InstalledArtifactStatus.absent
        ? await _downloadService.partialBytes(artifact.fileName)
        : 0;
    return _CandidateDownloadState(
      installed: status == InstalledArtifactStatus.matchesExpected,
      fileConflict: status == InstalledArtifactStatus.differentFile,
      storageUnavailable: status == InstalledArtifactStatus.storageUnavailable,
      partialBytes: partialBytes,
      receivedBytes: partialBytes,
      totalBytes: artifact.sizeBytes,
      message: message,
    );
  }

  Future<void> _openLicenseTerms(GgufCandidateArtifact artifact) async {
    bool opened = false;
    try {
      opened = await _externalUriLauncher(artifact.licenseTermsUri);
    } on Object {
      opened = false;
    }
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the license information.')),
    );
  }

  Iterable<String> _visibleWarnings(GgufCandidateAssessment assessment) {
    return assessment.warnings.where(
      (String warning) =>
          !warning.trim().toLowerCase().startsWith('custom license — review'),
    );
  }

  Future<void> _startCandidateDownload(
    GgufCandidateAssessment assessment,
  ) async {
    final GgufCandidateArtifact? artifact = assessment.artifact;
    if (!assessment.canDownload || artifact == null || _hasActiveDownload) {
      return;
    }
    final String key = _artifactKey(artifact);
    final _CandidateDownloadState current =
        _downloadStates[key] ?? const _CandidateDownloadState();
    if (current.partialBytes <= 0) {
      final bool confirmed = await _confirmCandidateDownload(
        assessment,
        artifact,
      );
      if (!confirmed || !mounted || _hasActiveDownload) return;
    }

    final DownloadCancelToken token = DownloadCancelToken();
    DateTime lastTick = DateTime.fromMillisecondsSinceEpoch(0);

    setState(() {
      _downloadStates[key] = current.copyWith(
        isDownloading: true,
        cancelToken: token,
        clearMessage: true,
        receivedBytes: current.partialBytes,
        totalBytes: artifact.sizeBytes,
      );
    });

    final DownloadResult result = await _downloadService.download(
      url: artifact.downloadUri,
      fileName: artifact.fileName,
      expectedSha256: artifact.sha256,
      cancelToken: token,
      onProgress: (DownloadProgress progress) {
        final DateTime now = DateTime.now();
        if (now.difference(lastTick) < const Duration(milliseconds: 250)) {
          return;
        }
        lastTick = now;
        if (!mounted) return;
        final _CandidateDownloadState state = _downloadStates[key] ?? current;
        setState(() {
          _downloadStates[key] = state.copyWith(
            receivedBytes: progress.receivedBytes,
            totalBytes: progress.totalBytes ?? artifact.sizeBytes,
          );
        });
      },
    );

    if (!mounted) return;
    String message = _candidateMessageFor(result);
    _CandidateDownloadState refreshed = await _readArtifactState(
      artifact,
      message: message,
    );
    bool provenanceSaved = true;
    if (result.isSuccess && refreshed.installed) {
      provenanceSaved = await _installRegistry.record(artifact);
      if (!provenanceSaved) {
        message =
            'Installed, but update source information could not be saved.';
        refreshed = refreshed.copyWith(message: message);
      }
    }
    if (!mounted) return;
    setState(() {
      _downloadStates[key] = refreshed;
    });

    if (result.isSuccess && refreshed.installed) {
      await widget.onModelInstalled?.call();
      if (!provenanceSaved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<bool> _confirmCandidateDownload(
    GgufCandidateAssessment assessment,
    GgufCandidateArtifact artifact,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: _surfaceColor,
          title: const Text(
            'Download Candidate?',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This exact artifact passed mechanical screening, but it '
                  'has not been tested on this device. After installation, '
                  'it becomes available in Playground and Benchmark.',
                  style: TextStyle(
                    color: _reviewAmber,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  artifact.fileName,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatBytes(artifact.sizeBytes)}  ·  '
                  '${artifact.licenseDisplayName}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  artifact.sourcePage.toString(),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  key: const Key('candidate-dialog-license-terms'),
                  onPressed: () => _openLicenseTerms(artifact),
                  style: TextButton.styleFrom(
                    foregroundColor: _accentBlue,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(artifact.licenseLinkLabel),
                ),
                for (final String warning in _visibleWarnings(assessment)) ...[
                  const SizedBox(height: 8),
                  Text(
                    warning,
                    style: const TextStyle(
                      color: _reviewAmber,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const Key('confirm-candidate-download-button'),
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentBlue,
                foregroundColor: Colors.black,
              ),
              child: const Text('Download Candidate'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _discardCandidatePartial(GgufCandidateArtifact artifact) async {
    if (_hasActiveDownload) return;
    await _downloadService.discardPartial(artifact.fileName);
    final _CandidateDownloadState refreshed = await _readArtifactState(
      artifact,
    );
    if (!mounted) return;
    setState(() {
      _downloadStates[_artifactKey(artifact)] = refreshed;
    });
  }

  String _candidateMessageFor(DownloadResult result) {
    switch (result.outcome) {
      case DownloadOutcome.completed:
        return 'Installed and available in Playground and Benchmark.';
      case DownloadOutcome.cancelled:
        return 'Stopped. Partial file kept — Resume continues the download.';
      case DownloadOutcome.networkError:
        return 'Download failed: ${result.message ?? 'network error'}. '
            'Partial file kept.';
      case DownloadOutcome.checksumFailed:
        return 'Checksum did not match. The candidate file was discarded.';
      case DownloadOutcome.storageError:
        return 'Storage error: ${result.message ?? 'could not write the file'}.';
      case DownloadOutcome.fileConflict:
        return 'A different file already uses this model filename. '
            'It was not changed.';
    }
  }

  String _artifactKey(GgufCandidateArtifact artifact) {
    return artifact.qualificationArtifactId;
  }

  @override
  Widget build(BuildContext context) {
    final GgufDiscoveryResult? result = _result;

    final Widget content = SafeArea(
      top: !widget.embedded,
      child: ListView(
        key: const PageStorageKey<String>('gguf-discovery-list'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildIntroduction(),
          const SizedBox(height: 14),
          _buildDiscoverButton(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            _buildTopLevelError(_errorMessage!),
          ],
          if (result != null) ...[
            const SizedBox(height: 18),
            _buildSummary(result, _lastRefreshedUtc),
            if (result.sourceFailures.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildIncompleteDiscoveryWarning(result.sourceFailures.length),
            ],
            const SizedBox(height: 18),
            if (_visibleCandidates(result).isEmpty) _buildEmptyResult(),
            ..._buildAssessmentSection(
              'Downloadable Candidates',
              result,
              GgufCandidateDisposition.candidate,
            ),
          ],
        ],
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        elevation: 0,
        title: const Text(
          'Discover GGUF Models',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: content,
    );
  }

  Widget _buildIntroduction() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.manage_search_rounded, color: _accentBlue, size: 20),
              SizedBox(width: 8),
              Text(
                'Public Hugging Face discovery',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Opening Discovery is offline. Tapping Discover checks a '
            'bounded bootstrap list plus popular public instruction-model GGUF repositories '
            'using current public metadata from Hugging Face.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            'A Candidate passed mechanical discovery screening only. '
            'Downloading installs the exact artifact for local testing. '
            'After installation, use Playground or Benchmark to inspect its '
            'behavior and compare its results.',
            style: TextStyle(color: _reviewAmber, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton.icon(
        key: const Key('discover-gguf-button'),
        onPressed:
            _isDiscovering || _isVerifyingInstalledModels || _hasActiveDownload
            ? null
            : _discover,
        icon: _isDiscovering || _isVerifyingInstalledModels
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.travel_explore_rounded, size: 18),
        label: Text(
          _isDiscovering
              ? 'Discovering…'
              : _isVerifyingInstalledModels
              ? 'Verifying installed models…'
              : 'Discover new models',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentBlue,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.white24,
          disabledForegroundColor: Colors.white70,
        ),
      ),
    );
  }

  Widget _buildTopLevelError(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _rejectedRed),
      ),
      child: Text(
        'Discovery could not start: $message',
        style: const TextStyle(color: _rejectedRed, fontSize: 13, height: 1.4),
      ),
    );
  }

  Widget _buildSummary(GgufDiscoveryResult result, DateTime? lastRefreshedUtc) {
    final int count = _visibleCandidates(result).length;
    final int installedCount = result.assessments
        .where(_isInstalledAssessment)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count downloadable '
          '${count == 1 ? 'Candidate' : 'Candidates'} found'
          '${installedCount == 0 ? '' : ' · $installedCount already installed'}',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        if (_isVerifyingInstalledModels) ...[
          const SizedBox(height: 4),
          const Text(
            'Verifying installed model files in the background…',
            key: Key('installed-model-verification-status'),
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
        if (lastRefreshedUtc != null) ...[
          const SizedBox(height: 4),
          Text(
            'Last checked: ${_formatTimestamp(lastRefreshedUtc)} · '
            'saved locally',
            key: const Key('discovery-last-refreshed'),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyResult() {
    return const Text(
      'No downloadable Candidates were found in this discovery run.',
      style: TextStyle(color: Colors.white54, fontSize: 13),
    );
  }

  Widget _buildIncompleteDiscoveryWarning(int failureCount) {
    return Text(
      'Some repositories could not be checked: $failureCount',
      key: const Key('discovery-incomplete-warning'),
      style: const TextStyle(color: _reviewAmber, fontSize: 12),
    );
  }

  List<Widget> _buildAssessmentSection(
    String title,
    GgufDiscoveryResult result,
    GgufCandidateDisposition disposition,
  ) {
    final List<GgufCandidateAssessment> assessments = result.assessments
        .where(
          (assessment) =>
              assessment.disposition == disposition &&
              !_isInstalledAssessment(assessment),
        )
        .toList(growable: false);
    if (assessments.isEmpty) return const <Widget>[];

    return <Widget>[
      _buildSectionHeading(title),
      for (final GgufCandidateAssessment assessment in assessments) ...[
        _buildAssessment(assessment),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<GgufCandidateAssessment> _visibleCandidates(GgufDiscoveryResult result) {
    return result.assessments
        .where(
          (assessment) =>
              assessment.disposition == GgufCandidateDisposition.candidate &&
              !_isInstalledAssessment(assessment),
        )
        .toList(growable: false);
  }

  bool _isInstalledAssessment(GgufCandidateAssessment assessment) {
    final GgufCandidateArtifact? artifact = assessment.artifact;
    if (artifact == null) return false;
    return _downloadStates[_artifactKey(artifact)]?.installed ?? false;
  }

  Widget _buildSectionHeading(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildAssessment(GgufCandidateAssessment assessment) {
    final Color statusColor = _statusColor(assessment.disposition);
    final GgufCandidateArtifact? artifact = assessment.artifact;

    return Container(
      key: ValueKey<String>('discovery-${assessment.repositoryId}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  assessment.repositoryId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusLabel(assessment.disposition),
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (assessment.disposition == GgufCandidateDisposition.candidate)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Candidate — discovery screened',
                style: TextStyle(color: _reviewAmber, fontSize: 12),
              ),
            ),
          if (artifact != null) ...[
            const SizedBox(height: 8),
            Text(
              artifact.fileName,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatBytes(artifact.sizeBytes)}  ·  '
              '${artifact.licenseDisplayName}  ·  ${artifact.modelFamily}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              artifact.sourcePage.toString(),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: Key('candidate-license-${artifact.fileName}'),
              onPressed: () => _openLicenseTerms(artifact),
              style: TextButton.styleFrom(
                foregroundColor: _accentBlue,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(artifact.licenseLinkLabel),
            ),
          ],
          for (final String reason in assessment.reasons) ...[
            const SizedBox(height: 8),
            Text(
              reason,
              style: TextStyle(color: statusColor, fontSize: 12, height: 1.35),
            ),
          ],
          for (final String warning in _visibleWarnings(assessment)) ...[
            const SizedBox(height: 8),
            Text(
              'Warning: $warning',
              style: const TextStyle(
                color: _reviewAmber,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (assessment.canDownload && artifact != null) ...[
            const SizedBox(height: 12),
            _buildCandidateDownloadArea(assessment, artifact),
          ],
        ],
      ),
    );
  }

  Widget _buildCandidateDownloadArea(
    GgufCandidateAssessment assessment,
    GgufCandidateArtifact artifact,
  ) {
    final _CandidateDownloadState state =
        _downloadStates[_artifactKey(artifact)] ??
        const _CandidateDownloadState(isChecking: true);

    if (state.isChecking) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'Checking local model files…',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      );
    }

    if (state.installed) {
      return const SizedBox.shrink();
    }

    if (state.fileConflict) {
      return const Text(
        'A different file already uses this exact model filename. It was not '
        'changed; remove or rename it outside this screen before downloading.',
        style: TextStyle(color: _rejectedRed, fontSize: 12, height: 1.35),
      );
    }

    if (state.storageUnavailable) {
      return const Text(
        'The app cannot inspect its model storage right now.',
        style: TextStyle(color: _rejectedRed, fontSize: 12),
      );
    }

    if (state.isDownloading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: state.fraction,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(_accentBlue),
            minHeight: 4,
          ),
          const SizedBox(height: 6),
          Text(
            state.progressLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            key: ValueKey<String>('candidate-stop-${artifact.fileName}'),
            onPressed: () => state.cancelToken?.cancel(),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('Stop'),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      );
    }

    final bool hasPartial = state.partialBytes > 0;
    final bool anotherDownloadIsActive = _hasActiveDownload;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPartial) ...[
          Text(
            'Partial download: ${_formatBytes(state.partialBytes)} of '
            '${_formatBytes(artifact.sizeBytes)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
        if (state.message != null) ...[
          Text(
            state.message!,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            ElevatedButton.icon(
              key: ValueKey<String>(
                '${hasPartial ? 'candidate-resume' : 'candidate-download'}-'
                '${artifact.fileName}',
              ),
              onPressed: anotherDownloadIsActive
                  ? null
                  : () => _startCandidateDownload(assessment),
              icon: Icon(
                hasPartial ? Icons.play_arrow_rounded : Icons.download_rounded,
                size: 18,
              ),
              label: Text(hasPartial ? 'Resume' : 'Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentBlue,
                foregroundColor: Colors.black,
              ),
            ),
            if (hasPartial) ...[
              const SizedBox(width: 8),
              TextButton(
                key: ValueKey<String>('candidate-discard-${artifact.fileName}'),
                onPressed: anotherDownloadIsActive
                    ? null
                    : () => _discardCandidatePartial(artifact),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                child: const Text('Discard'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Color _statusColor(GgufCandidateDisposition disposition) {
    switch (disposition) {
      case GgufCandidateDisposition.candidate:
        return _candidateGreen;
      case GgufCandidateDisposition.needsReview:
        return _reviewAmber;
      case GgufCandidateDisposition.rejected:
        return _rejectedRed;
    }
  }

  String _statusLabel(GgufCandidateDisposition disposition) {
    switch (disposition) {
      case GgufCandidateDisposition.candidate:
        return 'Candidate';
      case GgufCandidateDisposition.needsReview:
        return 'Needs review';
      case GgufCandidateDisposition.rejected:
        return 'Rejected';
    }
  }

  static String _formatBytes(int bytes) {
    const int gb = 1000 * 1000 * 1000;
    const int mb = 1000 * 1000;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }

  static String _formatTimestamp(DateTime utcTimestamp) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final DateTime local = utcTimestamp.toLocal();
    final int twelveHour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final String minute = local.minute.toString().padLeft(2, '0');
    final String period = local.hour < 12 ? 'AM' : 'PM';
    return '${months[local.month - 1]} ${local.day}, ${local.year} at '
        '$twelveHour:$minute $period';
  }
}

class _CandidateDownloadState {
  const _CandidateDownloadState({
    this.isChecking = false,
    this.installed = false,
    this.fileConflict = false,
    this.storageUnavailable = false,
    this.partialBytes = 0,
    this.isDownloading = false,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.message,
    this.cancelToken,
  });

  final bool isChecking;
  final bool installed;
  final bool fileConflict;
  final bool storageUnavailable;
  final int partialBytes;
  final bool isDownloading;
  final int receivedBytes;
  final int totalBytes;
  final String? message;
  final DownloadCancelToken? cancelToken;

  double? get fraction {
    if (totalBytes <= 0) return null;
    final double value = receivedBytes / totalBytes;
    return value > 1.0 ? 1.0 : value;
  }

  String get progressLabel {
    final String received = _GgufDiscoveryScreenState._formatBytes(
      receivedBytes,
    );
    if (totalBytes <= 0) return received;
    final String total = _GgufDiscoveryScreenState._formatBytes(totalBytes);
    final double percent = (fraction ?? 0) * 100;
    return '$received of $total  ·  ${percent.toStringAsFixed(0)}%';
  }

  _CandidateDownloadState copyWith({
    bool? isChecking,
    bool? installed,
    bool? fileConflict,
    bool? storageUnavailable,
    int? partialBytes,
    bool? isDownloading,
    int? receivedBytes,
    int? totalBytes,
    String? message,
    DownloadCancelToken? cancelToken,
    bool clearMessage = false,
    bool clearCancelToken = false,
  }) {
    return _CandidateDownloadState(
      isChecking: isChecking ?? this.isChecking,
      installed: installed ?? this.installed,
      fileConflict: fileConflict ?? this.fileConflict,
      storageUnavailable: storageUnavailable ?? this.storageUnavailable,
      partialBytes: partialBytes ?? this.partialBytes,
      isDownloading: isDownloading ?? this.isDownloading,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      message: clearMessage ? null : (message ?? this.message),
      cancelToken: clearCancelToken ? null : (cancelToken ?? this.cancelToken),
    );
  }
}
