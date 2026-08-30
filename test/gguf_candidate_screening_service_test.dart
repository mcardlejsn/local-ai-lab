import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/gguf_candidate_assessment.dart';
import 'package:local_ai_summarizer/models/hugging_face_model_metadata.dart';
import 'package:local_ai_summarizer/services/gguf_candidate_screening_service.dart';

void main() {
  const GgufCandidateScreeningService service = GgufCandidateScreeningService();

  group('GGUF candidate screening', () {
    test(
      'approves one complete supported permissive artifact as Candidate',
      () {
        final assessment = service.assess(
          _metadata(
            id: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
            license: 'apache-2.0',
            files: <HuggingFaceRepositoryFile>[
              _q4File('weights/qwen2.5-1.5b-instruct-q4_k_m.gguf'),
            ],
          ),
        );

        expect(assessment.disposition, GgufCandidateDisposition.candidate);
        expect(assessment.canDownload, isTrue);
        expect(assessment.reasons, isEmpty);
        expect(assessment.warnings, isEmpty);
        expect(assessment.artifact!.license, 'Apache-2.0');
        expect(assessment.artifact!.modelFamily, 'Qwen/ChatML');
        expect(
          assessment.artifact!.fileName,
          'qwen2.5-1.5b-instruct-q4_k_m.gguf',
        );
        expect(
          assessment.artifact!.downloadUri.toString(),
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/'
          'resolve/0123456789abcdef0123456789abcdef01234567/'
          'weights/qwen2.5-1.5b-instruct-q4_k_m.gguf',
        );
      },
    );

    test('allows an identified custom license with review details', () {
      final assessment = service.assess(
        _metadata(
          id: 'tiiuae/Falcon-H1-0.5B-Instruct-GGUF',
          license: 'falcon-llm-license',
          files: <HuggingFaceRepositoryFile>[
            _q4File('Falcon-H1-0.5B-Instruct-Q4_K_M.gguf'),
          ],
        ),
      );

      expect(assessment.disposition, GgufCandidateDisposition.candidate);
      expect(assessment.canDownload, isTrue);
      expect(assessment.artifact!.license, 'Falcon-LLM License');
      expect(assessment.artifact!.hasCustomLicense, isTrue);
      expect(assessment.artifact!.licenseDisplayName, 'Falcon-LLM License');
      expect(
        assessment.artifact!.licenseTermsUri,
        Uri.parse('https://huggingface.co/tiiuae/Falcon-H1-0.5B-Instruct-GGUF'),
      );
      expect(assessment.artifact!.licenseLinkLabel, 'View license information');
      expect(assessment.warnings, isEmpty);
    });

    test('requires unresolved linked license metadata for review', () {
      final metadata = _metadata(
        id: 'Publisher/Qwen2.5-1.5B-Instruct-GGUF',
        files: <HuggingFaceRepositoryFile>[
          _q4File('qwen2.5-1.5b-instruct-q4_k_m.gguf'),
        ],
        quantizedBaseModels: <String>['Qwen/Qwen2.5-1.5B-Instruct'],
      );

      final withoutUpstream = service.assess(metadata);
      expect(withoutUpstream.disposition, GgufCandidateDisposition.needsReview);
      expect(withoutUpstream.canDownload, isFalse);
      expect(withoutUpstream.reasons.single, contains('upstream'));

      final withUpstream = service.assess(
        metadata,
        upstreamMetadata: <String, HuggingFaceRepositoryMetadata>{
          'Qwen/Qwen2.5-1.5B-Instruct': _metadata(
            id: 'Qwen/Qwen2.5-1.5B-Instruct',
            license: 'apache-2.0',
          ),
        },
      );
      expect(withUpstream.disposition, GgufCandidateDisposition.candidate);
      expect(
        withUpstream.artifact!.licenseSourceRepository,
        'Qwen/Qwen2.5-1.5B-Instruct',
      );
    });

    test('rejects restricted repositories', () {
      final assessment = service.assess(
        _metadata(
          id: 'Publisher/Qwen2.5-1.5B-Instruct-GGUF',
          gatedStatus: 'manual',
          license: 'apache-2.0',
          files: <HuggingFaceRepositoryFile>[
            _q4File('qwen2.5-1.5b-instruct-q4_k_m.gguf'),
          ],
        ),
      );

      expect(assessment.disposition, GgufCandidateDisposition.rejected);
      expect(assessment.canDownload, isFalse);
      expect(assessment.reasons, contains(contains('private or gated')));
    });

    test('rejects an explicitly Base model', () {
      final assessment = service.assess(
        _metadata(
          id: 'Qwen/Qwen2.5-1.5B-Base-GGUF',
          license: 'apache-2.0',
          files: <HuggingFaceRepositoryFile>[
            _q4File('qwen2.5-1.5b-base-q4_k_m.gguf'),
          ],
        ),
      );

      expect(assessment.disposition, GgufCandidateDisposition.rejected);
      expect(assessment.reasons, contains(contains('Base model')));
    });

    final Map<String, String> excludedCandidateVariants = <String, String>{
      'williamliao/gemma-4-26B-A4B-it-speculator.eagle3-F16-GGUF':
          'gemma-4-26B-A4B-it-speculator.eagle3-Q4_K_M.gguf',
      'unsloth/functiongemma-270m-it-GGUF': 'functiongemma-270m-it-Q4_K_M.gguf',
      'Anbeeld/gemma-4-31B-it-DFlash-GGUF': 'gemma4-31b-it-dflash-Q4_K_M.gguf',
      'Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF':
          'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
      'bartowski/gemma-2-2b-it-abliterated-GGUF':
          'gemma-2-2b-it-abliterated-Q4_K_M.gguf',
      'bartowski/huihui-ai_gemma-3-1b-it-abliterated-GGUF':
          'huihui-ai_gemma-3-1b-it-abliterated-Q4_K_M.gguf',
      'DavidAU/Gemma-3-it-4B-Uncensored-DBL-X-GGUF':
          'Gemma-3-it-4B-Uncensored-D_AU-Q4_k_m.gguf',
    };
    for (final entry in excludedCandidateVariants.entries) {
      test('rejects excluded Candidate variant ${entry.key}', () {
        final assessment = service.assess(
          _metadata(
            id: entry.key,
            license: 'apache-2.0',
            files: <HuggingFaceRepositoryFile>[_q4File(entry.value)],
          ),
        );

        expect(assessment.disposition, GgufCandidateDisposition.rejected);
        expect(assessment.canDownload, isFalse);
        expect(
          assessment.reasons,
          contains(contains('excluded specialized or modified model')),
        );
      });
    }

    test('does not treat a publisher name as a special-purpose model', () {
      final assessment = service.assess(
        _metadata(
          id: 'Coder-Publisher/Qwen2.5-1.5B-Instruct-GGUF',
          license: 'apache-2.0',
          files: <HuggingFaceRepositoryFile>[
            _q4File('qwen2.5-1.5b-instruct-q4_k_m.gguf'),
          ],
        ),
      );

      expect(assessment.disposition, GgufCandidateDisposition.candidate);
      expect(assessment.canDownload, isTrue);
    });

    test('holds an unsupported Gemma generation for review', () {
      final assessment = service.assess(
        _metadata(
          id: 'Publisher/gemma-4-1B-it-GGUF',
          license: 'apache-2.0',
          files: <HuggingFaceRepositoryFile>[
            _q4File('gemma-4-1b-it-Q4_K_M.gguf'),
          ],
        ),
      );

      expect(assessment.disposition, GgufCandidateDisposition.needsReview);
      expect(assessment.canDownload, isFalse);
      expect(assessment.reasons, contains(contains('Gemma 2 and Gemma 3')));
    });

    test('rejects split-only Q4_K_M artifacts', () {
      final assessment = service.assess(
        _metadata(
          id: 'Qwen/Qwen2.5-3B-Instruct-GGUF',
          license: 'apache-2.0',
          files: <HuggingFaceRepositoryFile>[
            _q4File('qwen2.5-q4_k_m-00001-of-00002.gguf'),
            _q4File('qwen2.5-q4_k_m-00002-of-00002.gguf'),
          ],
        ),
      );

      expect(assessment.disposition, GgufCandidateDisposition.rejected);
      expect(assessment.reasons, contains(contains('split')));
    });

    test('holds ambiguous complete artifacts for review', () {
      final assessment = service.assess(
        _metadata(
          id: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
          license: 'apache-2.0',
          files: <HuggingFaceRepositoryFile>[
            _q4File('qwen2.5-instruct-q4_k_m.gguf'),
            _q4File('qwen2.5-instruct-q4_k_m-v2.gguf'),
          ],
        ),
      );

      expect(assessment.disposition, GgufCandidateDisposition.needsReview);
      expect(assessment.canDownload, isFalse);
      expect(assessment.reasons, contains(contains('More than one')));
    });

    test('holds an unknown prompt family for review', () {
      final assessment = service.assess(
        _metadata(
          id: 'Publisher/Unknown-1B-Instruct-GGUF',
          license: 'mit',
          files: <HuggingFaceRepositoryFile>[
            _q4File('unknown-1b-instruct-q4_k_m.gguf'),
          ],
        ),
      );

      expect(assessment.disposition, GgufCandidateDisposition.needsReview);
      expect(assessment.reasons, contains(contains('audited')));
    });

    test('rejects only a confirmed runtime incompatibility', () {
      final rejected = service.assess(
        _metadata(
          id: 'Qwen/Qwen3.5-2B-Instruct-GGUF',
          license: 'apache-2.0',
          files: <HuggingFaceRepositoryFile>[
            _q4File('Qwen3.5-2B-Instruct-Q4_K_M.gguf'),
          ],
        ),
      );
      final review = service.assess(
        _metadata(
          id: 'Qwen/Qwen3.5-4B-Instruct-GGUF',
          license: 'apache-2.0',
          files: <HuggingFaceRepositoryFile>[
            _q4File('Qwen3.5-4B-Instruct-Q4_K_M.gguf'),
          ],
        ),
      );

      expect(rejected.disposition, GgufCandidateDisposition.rejected);
      expect(rejected.reasons, contains(contains('incompatible')));
      expect(review.disposition, GgufCandidateDisposition.needsReview);
      expect(
        review.reasons,
        contains(contains('not been independently audited')),
      );
    });

    test('rejects an artifact over the size ceiling', () {
      final assessment = service.assess(
        _metadata(
          id: 'Qwen/Qwen2.5-7B-Instruct-GGUF',
          license: 'apache-2.0',
          files: <HuggingFaceRepositoryFile>[
            _q4File('qwen2.5-7b-instruct-q4_k_m.gguf', sizeBytes: 3000000001),
          ],
        ),
      );

      expect(assessment.disposition, GgufCandidateDisposition.rejected);
      expect(assessment.reasons, contains(contains('3 GB')));
    });

    test('holds incomplete exact artifact metadata for review', () {
      final assessment = service.assess(
        _metadata(
          id: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
          license: 'apache-2.0',
          files: const <HuggingFaceRepositoryFile>[
            HuggingFaceRepositoryFile(
              path: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
            ),
          ],
        ),
      );

      expect(assessment.disposition, GgufCandidateDisposition.needsReview);
      expect(assessment.canDownload, isFalse);
      expect(assessment.reasons, contains(contains('size')));
      expect(assessment.reasons, contains(contains('SHA-256')));
    });
  });
}

HuggingFaceRepositoryMetadata _metadata({
  required String id,
  bool isPrivate = false,
  String gatedStatus = 'false',
  String? license,
  String? licenseName,
  List<HuggingFaceRepositoryFile> files = const <HuggingFaceRepositoryFile>[],
  List<String> tags = const <String>['gguf'],
  List<String> quantizedBaseModels = const <String>[],
}) {
  return HuggingFaceRepositoryMetadata(
    id: id,
    commitSha: '0123456789abcdef0123456789abcdef01234567',
    isPrivate: isPrivate,
    gatedStatus: gatedStatus,
    tags: tags,
    files: files,
    quantizedBaseModels: quantizedBaseModels,
    license: license,
    licenseName: licenseName,
  );
}

HuggingFaceRepositoryFile _q4File(
  String path, {
  int sizeBytes = 1000000000,
  String sha256 =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) {
  return HuggingFaceRepositoryFile(
    path: path,
    sizeBytes: sizeBytes,
    sha256: sha256,
  );
}
