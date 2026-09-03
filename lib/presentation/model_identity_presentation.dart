import 'package:flutter/material.dart';

import '../services/model_manager_service.dart';

/// One technical model identity as it enters a compact presentation surface.
///
/// [technicalName] is never changed in storage. [key] lets callers resolve a
/// concise label for the same model after collection-level collision handling.
class ModelDisplayIdentity {
  const ModelDisplayIdentity({
    required this.key,
    required this.technicalName,
    required this.engine,
    this.publisherHint,
  });

  final String key;
  final String technicalName;
  final ModelEngine engine;
  final String? publisherHint;
}

String modelRuntimeLabel(ModelEngine engine) => switch (engine) {
  ModelEngine.nano => 'AICore',
  ModelEngine.gguf => 'GGUF',
  ModelEngine.litertlm => 'LiteRT-LM',
  // MediaPipe is no longer an active runtime. This label exists only so an
  // older saved row can still be rendered instead of failing to deserialize.
  ModelEngine.mediapipe => 'MediaPipe',
};

ModelEngine? modelEngineFromStoredName(String? value) {
  final String normalized = value?.trim().toLowerCase() ?? '';
  return switch (normalized) {
    'nano' || 'aicore' => ModelEngine.nano,
    'gguf' => ModelEngine.gguf,
    'litertlm' || 'litert-lm' => ModelEngine.litertlm,
    'mediapipe' => ModelEngine.mediapipe,
    _ => null,
  };
}

String modelRuntimeLabelFromStoredName(String? value) {
  final ModelEngine? engine = modelEngineFromStoredName(value);
  return engine == null ? 'Local runtime' : modelRuntimeLabel(engine);
}

/// Returns a concise label while leaving [technicalName] untouched.
String conciseModelName(String technicalName, ModelEngine engine) {
  final String trimmed = technicalName.trim();
  if (trimmed.isEmpty) return 'Unknown model';

  if (engine == ModelEngine.nano) return 'Gemini Nano';

  String cleaned = trimmed.split(RegExp(r'[\\/]')).last;
  cleaned = cleaned.replaceFirst(RegExp(r'\.gguf$', caseSensitive: false), '');
  cleaned = cleaned.replaceFirst(
    RegExp(r'[._ -]*q4[._ -]*k[._ -]*m$', caseSensitive: false),
    '',
  );
  cleaned = cleaned.replaceFirst(
    RegExp(r'\s*\(\s*LiteRT-LM\s*\)\s*$', caseSensitive: false),
    '',
  );

  // Some Candidate filenames include a repository-owner prefix. Remove only
  // recognized owner/family combinations; unfamiliar prefixes remain visible.
  cleaned = cleaned.replaceFirst(
    RegExp(
      r'^(?:microsoft[_-](?=phi)|google[_-](?=gemma)|meta-llama[_-](?=llama)|qwen[_-](?=qwen)|(?:bartowski|unsloth|huihui-ai)[_-](?=(?:qwen|llama|gemma|phi|falcon)))',
      caseSensitive: false,
    ),
    '',
  );

  final String separated = cleaned
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final RegExpMatch? qwen = RegExp(
    r'^qwen\s*([0-9]+(?:\.[0-9]+)?)[ -]+([0-9]+(?:\.[0-9]+)?)[ ]*b(?:[ -]+(coder))?(?:[ -]+(instruct|chat))?$',
    caseSensitive: false,
  ).firstMatch(separated);
  if (qwen != null) {
    final StringBuffer name = StringBuffer(
      'Qwen${qwen.group(1)} ${qwen.group(2)}B',
    );
    if (qwen.group(3) != null) name.write(' Coder');
    if (qwen.group(4)?.toLowerCase() == 'instruct') name.write(' Instruct');
    if (qwen.group(4)?.toLowerCase() == 'chat') name.write(' Chat');
    return name.toString();
  }

  final RegExpMatch? falcon = RegExp(
    r'^falcon[ -]+h1[ -]+([0-9]+(?:\.[0-9]+)?)[ ]*b(?:[ -]+(instruct|chat))?$',
    caseSensitive: false,
  ).firstMatch(separated);
  if (falcon != null) {
    final String suffix = falcon.group(2)?.toLowerCase() == 'chat'
        ? ' Chat'
        : falcon.group(2) == null
        ? ''
        : ' Instruct';
    return 'Falcon-H1 ${falcon.group(1)}B$suffix';
  }

  final RegExpMatch? llama = RegExp(
    r'^llama[ -]+([0-9]+(?:\.[0-9]+)?)[ -]+([0-9]+(?:\.[0-9]+)?)[ ]*b(?:[ -]+(instruct|chat))?$',
    caseSensitive: false,
  ).firstMatch(separated);
  if (llama != null) {
    final String suffix = llama.group(3)?.toLowerCase() == 'chat'
        ? ' Chat'
        : llama.group(3) == null
        ? ''
        : ' Instruct';
    return 'Llama ${llama.group(1)} ${llama.group(2)}B$suffix';
  }

  // Safe fallback: remove technical separators and canonicalize only tokens
  // whose meaning is unambiguous. Do not guess at an unfamiliar model family.
  return separated
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .split(' ')
      .map(_canonicalFallbackToken)
      .join(' ')
      .trim();
}

String _canonicalFallbackToken(String token) {
  final String lower = token.toLowerCase();
  if (RegExp(r'^\d+(?:\.\d+)?b$').hasMatch(lower)) {
    return '${token.substring(0, token.length - 1)}B';
  }
  return switch (lower) {
    'qwen' => 'Qwen',
    'llama' => 'Llama',
    'gemma' => 'Gemma',
    'falcon' => 'Falcon',
    'phi' => 'Phi',
    'instruct' => 'Instruct',
    'chat' => 'Chat',
    'coder' => 'Coder',
    'it' => 'IT',
    _ => token,
  };
}

/// Resolves concise names for a whole visible collection, adding a suffix only
/// where normalization would otherwise hide a real distinction.
Map<String, String> resolveConciseModelNames(
  Iterable<ModelDisplayIdentity> identities,
) {
  final List<ModelDisplayIdentity> items = identities.toList(growable: false);
  final Map<String, String> baseNames = <String, String>{
    for (final ModelDisplayIdentity item in items)
      item.key: conciseModelName(item.technicalName, item.engine),
  };
  final Map<String, List<ModelDisplayIdentity>> collisions =
      <String, List<ModelDisplayIdentity>>{};
  for (final ModelDisplayIdentity item in items) {
    collisions
        .putIfAbsent(baseNames[item.key]!.toLowerCase(), () => [])
        .add(item);
  }

  final Map<String, String> resolved = Map<String, String>.from(baseNames);
  for (final List<ModelDisplayIdentity> group in collisions.values) {
    if (group.length < 2) continue;

    final List<String?> sourceHints = group
        .map(
          (ModelDisplayIdentity item) =>
              item.publisherHint?.trim().isNotEmpty == true
              ? item.publisherHint!.trim()
              : _publisherHintFromTechnicalName(item.technicalName),
        )
        .toList(growable: false);
    final Set<String> normalizedHints = sourceHints
        .whereType<String>()
        .map((String value) => value.toLowerCase())
        .toSet();
    final bool usableHints =
        sourceHints.every((String? value) => value != null) &&
        normalizedHints.length == group.length;

    final Set<ModelEngine> engines = group
        .map((ModelDisplayIdentity item) => item.engine)
        .toSet();
    final bool enginesDistinguish = engines.length == group.length;

    for (int index = 0; index < group.length; index++) {
      final ModelDisplayIdentity item = group[index];
      final String suffix = usableHints
          ? _formatPublisherHint(sourceHints[index]!)
          : enginesDistinguish
          ? modelRuntimeLabel(item.engine)
          : _technicalCollisionSuffix(item.technicalName, item.engine);
      resolved[item.key] = '${baseNames[item.key]} — $suffix';
    }
  }
  return resolved;
}

/// Replaces exact technical model names embedded in a runtime status message.
///
/// Loading a new model deliberately leaves the previous model active until the
/// replacement is ready, so an initializing or failure message can name a
/// different model from the active selection. Resolve against the whole known
/// collection rather than only the active model.
String conciseModelStatus(
  String technicalStatus,
  Iterable<ModelDisplayIdentity> identities,
) {
  final List<ModelDisplayIdentity> items = identities.toList(growable: false)
    ..sort(
      (ModelDisplayIdentity a, ModelDisplayIdentity b) =>
          b.technicalName.length.compareTo(a.technicalName.length),
    );
  final Map<String, String> displayNames = resolveConciseModelNames(items);
  String presented = technicalStatus;
  for (final ModelDisplayIdentity item in items) {
    presented = presented.replaceAll(
      item.technicalName,
      displayNames[item.key]!,
    );
  }
  return presented;
}

String? _publisherHintFromTechnicalName(String technicalName) {
  final String filename = technicalName.split(RegExp(r'[\\/]')).last;
  final RegExpMatch? match = RegExp(
    r'^(microsoft|google|meta-llama|qwen|bartowski|unsloth|huihui-ai)[_-]',
    caseSensitive: false,
  ).firstMatch(filename);
  return match?.group(1);
}

String _formatPublisherHint(String hint) {
  return hint
      .split(RegExp(r'[-_ ]+'))
      .where((String part) => part.isNotEmpty)
      .map(
        (String part) =>
            '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

String _technicalCollisionSuffix(String technicalName, ModelEngine engine) {
  if (engine == ModelEngine.nano) {
    final RegExpMatch? baseModelMatch = RegExp(
      r'base model:\s*([^;)]+)',
      caseSensitive: false,
    ).firstMatch(technicalName);
    final String? baseModelName = baseModelMatch?.group(1)?.trim();
    if (baseModelName == null || baseModelName.isEmpty) {
      return 'base model unreported';
    }
    if (baseModelName.toLowerCase() == 'unavailable') {
      return 'base model unavailable';
    }
    return baseModelName;
  }

  final String filename = technicalName.split(RegExp(r'[\\/]')).last;
  return filename.replaceFirst(RegExp(r'\.gguf$', caseSensitive: false), '');
}

class ModelRuntimeBadge extends StatelessWidget {
  const ModelRuntimeBadge({super.key, required this.engine});

  final ModelEngine engine;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        modelRuntimeLabel(engine),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
