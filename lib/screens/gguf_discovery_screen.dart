import 'package:flutter/material.dart';

import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_discovery_result.dart';
import '../services/gguf_discovery_service.dart';
import '../services/hugging_face_discovery_service.dart';

/// Displays temporary GGUF discovery results after an explicit user action.
///
/// Opening this screen performs no network request. The discovery service is
/// called only from [_discover], which is wired exclusively to the Discover
/// button. This screen deliberately does not download candidate artifacts.
class GgufDiscoveryScreen extends StatefulWidget {
  const GgufDiscoveryScreen({
    super.key,
    this.discoveryService,
  });

  /// Injectable so widget tests can provide deterministic, offline responses.
  final GgufDiscoveryService? discoveryService;

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
  GgufDiscoveryResult? _result;
  String? _errorMessage;
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _discoveryService = widget.discoveryService ?? GgufDiscoveryService();
  }

  Future<void> _discover() async {
    setState(() {
      _isDiscovering = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final GgufDiscoveryResult result = await _discoveryService.discover();
      if (!mounted) return;
      setState(() {
        _result = result;
        _isDiscovering = false;
      });
    } on HuggingFaceDiscoveryException catch (error) {
      _showFailure(error.message);
    } on ArgumentError catch (error) {
      _showFailure(
        error.message?.toString() ?? 'The discovery request was invalid.',
      );
    }
  }

  void _showFailure(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isDiscovering = false;
    });
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
              _buildSummary(result),
              const SizedBox(height: 18),
              if (result.assessments.isEmpty && result.sourceFailures.isEmpty)
                _buildEmptyResult(),
              ..._buildAssessmentSection(
                'Candidates',
                result,
                GgufCandidateDisposition.candidate,
              ),
              ..._buildAssessmentSection(
                'Needs review',
                result,
                GgufCandidateDisposition.needsReview,
              ),
              ..._buildAssessmentSection(
                'Rejected',
                result,
                GgufCandidateDisposition.rejected,
              ),
              if (result.sourceFailures.isNotEmpty) ...[
                _buildSectionHeading('Source errors'),
                for (final GgufDiscoverySourceFailure failure
                    in result.sourceFailures) ...[
                  _buildSourceFailure(failure),
                  const SizedBox(height: 10),
                ],
              ],
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
            'Opening this screen is offline. Tapping Discover requests a '
            'bounded list of recent public, ungated GGUF repositories and '
            'their public metadata from Hugging Face.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            'A Candidate passed mechanical screening only. It is not device '
            'verified, and this screen cannot download it yet.',
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
        onPressed: _isDiscovering ? null : _discover,
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

  Widget _buildSummary(GgufDiscoveryResult result) {
    return Text(
      'Candidate ${result.candidateCount}  ·  '
      'Needs review ${result.needsReviewCount}  ·  '
      'Rejected ${result.rejectedCount}  ·  '
      'Source errors ${result.sourceFailures.length}',
      style: const TextStyle(color: Colors.white70, fontSize: 13),
    );
  }

  Widget _buildEmptyResult() {
    return const Text(
      'No public GGUF repositories were returned for this discovery request.',
      style: TextStyle(color: Colors.white54, fontSize: 13),
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
              '${_formatBytes(artifact.sizeBytes)}  ·  ${artifact.license}  ·  '
              '${artifact.modelFamily}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              artifact.sourcePage.toString(),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
          for (final String reason in assessment.reasons) ...[
            const SizedBox(height: 8),
            Text(
              reason,
              style: TextStyle(color: statusColor, fontSize: 12, height: 1.35),
            ),
          ],
          for (final String warning in assessment.warnings) ...[
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
        ],
      ),
    );
  }

  Widget _buildSourceFailure(GgufDiscoverySourceFailure failure) {
    final String context = failure.requestedForRepositoryId == null
        ? failure.repositoryId
        : '${failure.repositoryId} '
            '(needed by ${failure.requestedForRepositoryId})';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            failure.message,
            style: const TextStyle(
              color: _rejectedRed,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
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
}
