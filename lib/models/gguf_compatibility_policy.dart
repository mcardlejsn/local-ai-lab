/// Centralized GGUF filename recognition and compatibility policy.
///
/// This policy describes what Local AI Lab knows before a model is executed.
/// A supported result means the app has an audited prompt/runtime path for the
/// recognized filename; it does not mean the exact artifact is phone-verified.
enum PromptFormat {
  plain,
  gemma,
  chatml,
  falconH1,
  qwen3,
  phi3,
  phi4,
  llama3,
  mistral,
  smollm2,
  smollm3,
}

extension PromptFormatLabel on PromptFormat {
  String get label {
    switch (this) {
      case PromptFormat.plain:
        return 'plain';
      case PromptFormat.gemma:
        return 'gemma';
      case PromptFormat.chatml:
        return 'chatml';
      case PromptFormat.falconH1:
        return 'falcon-h1';
      case PromptFormat.qwen3:
        return 'qwen3';
      case PromptFormat.phi3:
        return 'phi3';
      case PromptFormat.phi4:
        return 'phi4';
      case PromptFormat.llama3:
        return 'llama3';
      case PromptFormat.mistral:
        return 'mistral';
      case PromptFormat.smollm2:
        return 'smollm2';
      case PromptFormat.smollm3:
        return 'smollm3';
    }
  }
}

class GgufCompatibilityAssessment {
  const GgufCompatibilityAssessment({
    required this.family,
    required this.promptFormat,
    required this.isRecognized,
    required this.isSupported,
    required this.discoveryEligible,
    required this.explanation,
  });

  final String family;
  final PromptFormat promptFormat;
  final bool isRecognized;
  final bool isSupported;

  /// Whether this filename may pass the app-side compatibility portion of
  /// discovery screening. Repository access, artifact, size, checksum,
  /// purpose, and license checks remain separate requirements.
  final bool discoveryEligible;
  final String explanation;
}

GgufCompatibilityAssessment assessGgufCompatibility(String fileName) {
  final String name = fileName.toLowerCase();

  if (name.contains('smollm3')) {
    return _supported('SmolLM3', PromptFormat.smollm3);
  }
  if (name.contains('smollm2')) {
    return _supported('SmolLM2', PromptFormat.smollm2);
  }

  // Explicit ChatML indicators take precedence over the underlying family.
  if (name.contains('chatml') || name.contains('hermes')) {
    return _supported('ChatML/Hermes', PromptFormat.chatml);
  }

  final bool isFalconH105B = name.contains('falcon-h1-0.5b') ||
      name.contains('falcon_h1_0.5b') ||
      name.contains('falconh1-0.5b') ||
      name.contains('falconh1_0.5b');
  if (isFalconH105B) {
    return _supported('Falcon-H1 0.5B', PromptFormat.falconH1);
  }
  if (name.contains('falcon-h1') ||
      name.contains('falcon_h1') ||
      name.contains('falconh1')) {
    return _unsupported(
      family: 'Falcon-H1',
      explanation:
          'Only the independently audited Falcon-H1 0.5B variant is supported.',
    );
  }

  final bool isQwen35 = name.contains('qwen3.5') ||
      name.contains('qwen-3.5') ||
      name.contains('qwen_3.5');
  if (isQwen35) {
    final bool isQwen352B = name.contains('qwen3.5-2b') ||
        name.contains('qwen3.5_2b') ||
        name.contains('qwen-3.5-2b') ||
        name.contains('qwen-3.5_2b') ||
        name.contains('qwen_3.5-2b') ||
        name.contains('qwen_3.5_2b');
    if (isQwen352B) {
      return const GgufCompatibilityAssessment(
        family: 'Qwen3.5 2B',
        promptFormat: PromptFormat.chatml,
        isRecognized: true,
        isSupported: false,
        discoveryEligible: false,
        explanation:
            'Qwen3.5 2B is incompatible with Local AI Lab\'s bundled llama.cpp runtime.',
      );
    }
    return const GgufCompatibilityAssessment(
      family: 'Qwen3.5',
      promptFormat: PromptFormat.chatml,
      isRecognized: true,
      isSupported: false,
      discoveryEligible: false,
      explanation:
          'This Qwen3.5 variant has not been independently audited by Local AI Lab.',
    );
  }
  if (name.contains('qwen3') ||
      name.contains('qwen-3') ||
      name.contains('qwen_3')) {
    return _supported('Qwen3', PromptFormat.qwen3);
  }
  if (name.contains('phi-3') ||
      name.contains('phi3') ||
      name.contains('phi_3')) {
    return _supported('Phi-3', PromptFormat.phi3);
  }
  if (name.contains('phi-4') ||
      name.contains('phi4') ||
      name.contains('phi_4')) {
    return _supported('Phi-4', PromptFormat.phi4);
  }
  if (name.contains('gemma')) {
    return _supported('Gemma', PromptFormat.gemma);
  }
  if (name.contains('llama-3') ||
      name.contains('llama3') ||
      name.contains('llama_3')) {
    return _supported('Llama 3', PromptFormat.llama3);
  }
  if (name.contains('mistral') || name.contains('mixtral')) {
    return _supported('Mistral/Mixtral', PromptFormat.mistral);
  }
  if (name.contains('qwen')) {
    return _supported('Qwen/ChatML', PromptFormat.chatml);
  }

  return _unsupported(
    family: 'Unknown',
    explanation:
        'The filename does not match an audited Local AI Lab GGUF family.',
  );
}

GgufCompatibilityAssessment _supported(
  String family,
  PromptFormat promptFormat,
) {
  return GgufCompatibilityAssessment(
    family: family,
    promptFormat: promptFormat,
    isRecognized: true,
    isSupported: true,
    discoveryEligible: true,
    explanation:
        'Local AI Lab has an audited prompt path for this filename family.',
  );
}

GgufCompatibilityAssessment _unsupported({
  required String family,
  required String explanation,
}) {
  return GgufCompatibilityAssessment(
    family: family,
    promptFormat: PromptFormat.plain,
    isRecognized: family != 'Unknown',
    isSupported: false,
    discoveryEligible: false,
    explanation: explanation,
  );
}

/// Preserves the existing installed-model behavior: unrecognized sideloaded
/// files still receive a plain prompt, while discovery can inspect the richer
/// assessment and withhold unsupported candidates.
PromptFormat resolvePromptFormat(String fileName) {
  return assessGgufCompatibility(fileName).promptFormat;
}
