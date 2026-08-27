import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/gguf_candidate_assessment.dart';
import 'package:local_ai_summarizer/models/gguf_compatibility_policy.dart';
import 'package:local_ai_summarizer/services/database_service.dart';

void main() {
  test('qualification identity includes the exact artifact digest', () {
    final GgufCandidateArtifact first = _artifact(
      sha256:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
    final GgufCandidateArtifact changed = _artifact(
      sha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );

    expect(
      first.qualificationArtifactId,
      'Publisher/Model-GGUF@'
      '0123456789abcdef0123456789abcdef01234567/'
      'model-q4_k_m.gguf#'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(
      changed.qualificationArtifactId,
      isNot(first.qualificationArtifactId),
    );
  });

  test('missing qualification history remains benchmark required', () {
    expect(
      candidateQualificationStatusFromRuns(null),
      CandidateQualificationStatus.notRun,
    );
  });

  test('every qualification run must finish without a runtime error', () {
    expect(
      candidateQualificationStatusFromRuns(<Map<String, Object?>>[
        <String, Object?>{'error_message': null},
        <String, Object?>{'error_message': null},
      ]),
      CandidateQualificationStatus.completed,
    );
    expect(
      candidateQualificationStatusFromRuns(<Map<String, Object?>>[
        <String, Object?>{'error_message': null},
        <String, Object?>{'error_message': 'Runtime failure'},
      ]),
      CandidateQualificationStatus.failed,
    );
    expect(
      candidateQualificationStatusFromRuns(const <Map<String, Object?>>[]),
      CandidateQualificationStatus.failed,
    );
  });
}

GgufCandidateArtifact _artifact({required String sha256}) {
  return GgufCandidateArtifact(
    repositoryId: 'Publisher/Model-GGUF',
    commitSha: '0123456789ABCDEF0123456789ABCDEF01234567',
    fileName: 'model-q4_k_m.gguf',
    sizeBytes: 123,
    sha256: sha256,
    downloadUri: Uri.parse('https://example.com/model.gguf'),
    sourcePage: Uri.parse('https://example.com/model'),
    license: 'MIT',
    licenseSourceRepository: 'Publisher/Model-GGUF',
    hasCustomLicense: false,
    modelFamily: 'Qwen/ChatML',
    promptFormat: PromptFormat.chatml,
  );
}
