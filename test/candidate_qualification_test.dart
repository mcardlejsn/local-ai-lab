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

  test('known licenses expose readable names and canonical terms', () {
    final Map<String, (String, String)> expected = <String, (String, String)>{
      'Apache-2.0': (
        'Apache-2.0',
        'https://www.apache.org/licenses/LICENSE-2.0',
      ),
      'MIT': (
        'MIT',
        'https://opensource.org/license/mit',
      ),
      'qwen-research': (
        'Qwen Research License',
        'https://huggingface.co/Qwen/Qwen2.5-3B/blob/main/LICENSE',
      ),
      'llama3.2': (
        'Llama 3.2 Community License',
        'https://developer.meta.com/ai/llama3_2/license/',
      ),
      'gemma': (
        'Gemma Terms of Use',
        'https://ai.google.dev/gemma/terms',
      ),
      'falcon-llm-license': (
        'Falcon-LLM License',
        'https://falconllm.tii.ae/falcon-terms-and-conditions.html',
      ),
    };

    for (final MapEntry<String, (String, String)> entry in expected.entries) {
      final GgufCandidateArtifact artifact = _artifact(
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        license: entry.key,
        hasCustomLicense: entry.key != 'Apache-2.0' && entry.key != 'MIT',
      );
      expect(artifact.licenseDisplayName, entry.value.$1);
      expect(artifact.licenseTermsUri.toString(), entry.value.$2);
      expect(artifact.licenseLinkLabel, 'View license terms');
    }
  });

  test('unmapped usable license links to its recorded source repository', () {
    final GgufCandidateArtifact artifact = _artifact(
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      license: 'future-publisher-license',
      hasCustomLicense: true,
    );

    expect(artifact.licenseDisplayName, 'future-publisher-license');
    expect(
      artifact.licenseTermsUri.toString(),
      'https://huggingface.co/Publisher/Model-GGUF',
    );
    expect(artifact.licenseLinkLabel, 'View license source');
  });
}

GgufCandidateArtifact _artifact({
  required String sha256,
  String license = 'MIT',
  bool hasCustomLicense = false,
}) {
  return GgufCandidateArtifact(
    repositoryId: 'Publisher/Model-GGUF',
    commitSha: '0123456789ABCDEF0123456789ABCDEF01234567',
    fileName: 'model-q4_k_m.gguf',
    sizeBytes: 123,
    sha256: sha256,
    downloadUri: Uri.parse('https://example.com/model.gguf'),
    sourcePage: Uri.parse('https://example.com/model'),
    license: license,
    licenseSourceRepository: 'Publisher/Model-GGUF',
    hasCustomLicense: hasCustomLicense,
    modelFamily: 'Qwen/ChatML',
    promptFormat: PromptFormat.chatml,
  );
}
