import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_discovery_result.dart';
import '../services/database_service.dart';
import '../services/gguf_discovery_cache_service.dart';
import '../services/gguf_discovery_service.dart';
import '../services/gguf_discovery_seed_service.dart';
import '../services/hugging_face_discovery_service.dart';
import '../services/model_download_service.dart';

typedef CandidateQualificationLookup = Future<CandidateQualificationStatus>
    Function(String qualificationArtifactId);
typedef ExternalUriLauncher = Future<bool> Function(Uri uri);

/// Displays GGUF discovery results produced by an explicit user action.
///
/// Opening this screen performs no network request. The discovery service is
/// called only from [_discover], which is wired exclusively to the Discover
/// button. The last successful result may be restored from an app-private
/// local cache. Candidate downloads require a second explicit confirmation
/// and remain mechanically screened rather than device verified.
class GgufDiscoveryScreen extends StatefulWidget {
  const GgufDiscoveryScreen({
    super.key,
    this.discoveryService,
    this.discoveryCache,
    this.downloadService,
    this.onModelInstalled,
    this.onBenchmarkCandidate,
    this.qualificationLookup,
    this.externalUriLauncher,
  });

  /// Injectable so widget tests can provide deterministic, offline responses.
  final GgufDiscoveryService? discoveryService;

  /// Injectable so widget tests can avoid app-private filesystem access.
  final GgufDiscoveryCache? discoveryCache;

  /// Injectable so widget tests never touch Android storage or the network.
  final ModelDownloadService? downloadService;

  /// Called after an exact candidate artifact is installed successfully.
  final Future<void> Function()? onModelInstalled;

  /// Opens a qualification benchmark for the exact installed Candidate file.
  final Future<void> Function(GgufCandidateArtifact artifact)?
      onBenchmarkCandidate;

  /// Injectable so widget tests can avoid the platform database.
  final CandidateQualificationLookup? qualificationLookup;

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
  late final CandidateQualificationLookup _qualificationLookup;
  late final ExternalUriLauncher _externalUriLauncher;
  GgufDiscoveryResult? _result;
  DateTime? _lastRefreshedUtc;
  String? _errorMessage;
  bool _isDiscovering = false;
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
    _qualificationLookup = widget.qualificationLookup ??
        DatabaseService.instance.getCandidateQualificationStatus;
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
    if (_isDiscovering || _hasActiveDownload) return;
    final int generation = ++_discoveryGeneration;
    setState(() {
      _isDiscovering = true;
      _errorMessage = null;
    });

    try {
      final GgufDiscoveryResult result = await _discoveryService.discover();
      final DateTime discoveredAtUtc = DateTime.now().toUtc();
      await _saveDiscoveryCache(result, discoveredAtUtc);
      if (!mounted) return;
      setState(() {
        _result = result;
        _lastRefreshedUtc = discoveredAtUtc;
        _isDiscovering = false;
        _downloadStates.clear();
      });
      await _refreshCandidateStates(result, generation);
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
    final GgufDiscoveryResult visibleResult =
        _discoveryService.excludeVerifiedArtifacts(restored.result);

    setState(() {
      _result = visibleResult;
      _lastRefreshedUtc = restored.discoveredAtUtc;
      _downloadStates.clear();
    });
    await _refreshCandidateStates(visibleResult, generation);
  }

  Future<void> _saveDiscoveryCache(
    GgufDiscoveryResult result,
    DateTime discoveredAtUtc,
  ) async {
    try {
      await _discoveryCache.save(
        result,
        discoveredAtUtc: discoveredAtUtc,
      );
    } on Object {
      // Discovery remains usable when optional local cache storage fails.
    }
  }

  void _showFailure(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isDiscovering = false;
    });
  }

  Future<void> _refreshCandidateStates(
    GgufDiscoveryResult result,
    int generation,
  ) async {
    final List<GgufCandidateArtifact> artifacts = result.assessments
        .where((assessment) => assessment.canDownload)
        .map((assessment) => assessment.artifact!)
        .toList(growable: false);
    if (artifacts.isEmpty || !mounted || generation != _discoveryGeneration) {
      return;
    }

    setState(() {
      for (final GgufCandidateArtifact artifact in artifacts) {
        _downloadStates[_artifactKey(artifact)] =
            const _CandidateDownloadState(isChecking: true);
      }
    });

    for (final GgufCandidateArtifact artifact in artifacts) {
      final _CandidateDownloadState state = await _readArtifactState(artifact);
      if (!mounted || generation != _discoveryGeneration) return;
      setState(() {
        _downloadStates[_artifactKey(artifact)] = state;
      });
    }
  }

  Future<_CandidateDownloadState> _readArtifactState(
    GgufCandidateArtifact artifact, {
    String? message,
  }) async {
    final InstalledArtifactStatus status =
        await _downloadService.installedArtifactStatus(
      fileName: artifact.fileName,
      expectedSha256: artifact.sha256,
    );
    final int partialBytes = status == InstalledArtifactStatus.absent
        ? await _downloadService.partialBytes(artifact.fileName)
        : 0;
    CandidateQualificationStatus qualificationStatus =
        CandidateQualificationStatus.notRun;
    if (status == InstalledArtifactStatus.matchesExpected) {
      try {
        qualificationStatus = await _qualificationLookup(
          artifact.qualificationArtifactId,
        );
      } on Object {
        // A local history read must not make installed model controls unusable.
      }
    }
    return _CandidateDownloadState(
      installed: status == InstalledArtifactStatus.matchesExpected,
      fileConflict: status == InstalledArtifactStatus.differentFile,
      storageUnavailable: status == InstalledArtifactStatus.storageUnavailable,
      partialBytes: partialBytes,
      receivedBytes: partialBytes,
      totalBytes: artifact.sizeBytes,
      message: message,
      qualificationStatus: qualificationStatus,
    );
  }

  Future<void> _benchmarkCandidate(GgufCandidateArtifact artifact) async {
    final callback = widget.onBenchmarkCandidate;
    if (callback == null || _hasActiveDownload) return;
    await callback(artifact);
    if (!mounted) return;

    final _CandidateDownloadState refreshed =
        await _readArtifactState(artifact);
    if (!mounted) return;
    setState(() {
      _downloadStates[_artifactKey(artifact)] = refreshed;
    });
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
      const SnackBar(
        content: Text('Could not open the license information.'),
      ),
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
    final String message = _candidateMessageFor(result);
    final _CandidateDownloadState refreshed = await _readArtifactState(
      artifact,
      message: message,
    );
    if (!mounted) return;
    setState(() {
      _downloadStates[key] = refreshed;
    });

    if (result.isSuccess && refreshed.installed) {
      await widget.onModelInstalled?.call();
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
                  'has not been device verified. Benchmark it after install '
                  'before treating it as verified.',
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

  Future<void> _discardCandidatePartial(
    GgufCandidateArtifact artifact,
  ) async {
    if (_hasActiveDownload) return;
    await _downloadService.discardPartial(artifact.fileName);
    final _CandidateDownloadState refreshed =
        await _readArtifactState(artifact);
    if (!mounted) return;
    setState(() {
      _downloadStates[_artifactKey(artifact)] = refreshed;
    });
  }

  String _candidateMessageFor(DownloadResult result) {
    switch (result.outcome) {
      case DownloadOutcome.completed:
        return 'Installed as a Candidate. Run the benchmark before treating '
            'it as verified.';
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                _buildIncompleteDiscoveryWarning(
                  result.sourceFailures.length,
                ),
              ],
              const SizedBox(height: 18),
              if (result.assessments.isEmpty) _buildEmptyResult(),
              ..._buildAssessmentSection(
                'Downloadable Candidates',
                result,
                GgufCandidateDisposition.candidate,
              ),
            ],
          ],
        ),
      ),
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
            'Opening this screen is offline. Tapping Discover checks a '
            'bounded bootstrap list plus recent public GGUF repositories '
            'using current public metadata from Hugging Face.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            'A Candidate passed mechanical screening only. It is not device '
            'verified. You may download it for local testing, but it remains '
            'a Candidate until it passes the benchmark.',
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
        onPressed: _isDiscovering || _hasActiveDownload ? null : _discover,
        icon: _isDiscovering
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.travel_explore_rounded, size: 18),
        label: Text(_isDiscovering ? 'Discovering…' : 'Discover'),
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

  Widget _buildSummary(
    GgufDiscoveryResult result,
    DateTime? lastRefreshedUtc,
  ) {
    final int count = result.candidateCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count downloadable '
          '${count == 1 ? 'Candidate' : 'Candidates'} found',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        if (lastRefreshedUtc != null) ...[
          const SizedBox(height: 4),
          Text(
            'Last refreshed: ${_formatTimestamp(lastRefreshedUtc)} · '
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
        .where((assessment) => assessment.disposition == disposition)
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
                'Candidate — not device verified',
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
      final CandidateQualificationStatus qualificationStatus =
          state.qualificationStatus;
      final String statusText;
      final Color statusColor;
      final IconData statusIcon;
      switch (qualificationStatus) {
        case CandidateQualificationStatus.notRun:
          statusText = 'Installed Candidate — benchmark required';
          statusColor = _candidateGreen;
          statusIcon = Icons.check_circle_rounded;
          break;
        case CandidateQualificationStatus.completed:
          statusText = 'Benchmark completed — review required';
          statusColor = _reviewAmber;
          statusIcon = Icons.fact_check_outlined;
          break;
        case CandidateQualificationStatus.failed:
          statusText = 'Benchmark failed — retry required';
          statusColor = _rejectedRed;
          statusIcon = Icons.error_outline_rounded;
          break;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 16, color: statusColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ),
            ],
          ),
          if (state.message != null) ...[
            const SizedBox(height: 8),
            Text(
              state.message!,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
          if (widget.onBenchmarkCandidate != null) ...[
            const SizedBox(height: 10),
            ElevatedButton.icon(
              key: ValueKey<String>(
                'candidate-benchmark-${artifact.fileName}',
              ),
              onPressed: _hasActiveDownload
                  ? null
                  : () => _benchmarkCandidate(artifact),
              icon: const Icon(Icons.speed_rounded, size: 18),
              label: const Text('Benchmark Candidate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentBlue,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ],
      );
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
                key: ValueKey<String>(
                  'candidate-discard-${artifact.fileName}',
                ),
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
    this.qualificationStatus = CandidateQualificationStatus.notRun,
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
  final CandidateQualificationStatus qualificationStatus;

  double? get fraction {
    if (totalBytes <= 0) return null;
    final double value = receivedBytes / totalBytes;
    return value > 1.0 ? 1.0 : value;
  }

  String get progressLabel {
    final String received =
        _GgufDiscoveryScreenState._formatBytes(receivedBytes);
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
    CandidateQualificationStatus? qualificationStatus,
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
      qualificationStatus: qualificationStatus ?? this.qualificationStatus,
    );
  }
}
