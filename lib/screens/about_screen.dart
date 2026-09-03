import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/gemini_nano_service.dart';
import '../theme/app_theme.dart';

typedef AppPackageDetailsLoader = Future<AppPackageDetails> Function();
typedef RuntimeDiagnosticsLoader = Future<RuntimeDiagnostics> Function();

@immutable
class AppPackageDetails {
  const AppPackageDetails({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get displayVersion =>
      buildNumber.isEmpty ? version : '$version ($buildNumber)';
}

@immutable
class RuntimeDiagnostics {
  const RuntimeDiagnostics({
    required this.platformDescription,
    required this.geminiNanoAvailable,
    this.nanoBaseModelName,
    this.aiCoreVersion,
  });

  final String platformDescription;
  final bool geminiNanoAvailable;
  final String? nanoBaseModelName;
  final String? aiCoreVersion;
}

Future<AppPackageDetails> loadAppPackageDetails() async {
  final PackageInfo packageInfo = await PackageInfo.fromPlatform();
  return AppPackageDetails(
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
  );
}

Future<RuntimeDiagnostics> loadRuntimeDiagnostics() async {
  final bool nanoAvailable = await GeminiNanoService.isAvailable();
  final String? nanoBaseModelName = nanoAvailable
      ? await GeminiNanoService.getBaseModelName()
      : null;
  final String? aiCoreVersion = await GeminiNanoService.getAiCoreVersion();
  return RuntimeDiagnostics(
    platformDescription: Platform.operatingSystemVersion,
    geminiNanoAvailable: nanoAvailable,
    nanoBaseModelName: nanoBaseModelName,
    aiCoreVersion: aiCoreVersion,
  );
}

Future<void> openOpenSourceLicenses(BuildContext context) async {
  AppPackageDetails? details;
  try {
    details = await loadAppPackageDetails();
  } on Object {
    // The license registry remains usable if platform version lookup fails.
  }
  if (!context.mounted) return;
  showLicensePage(
    context: context,
    applicationName: 'Local AI Lab',
    applicationVersion: details?.displayVersion,
  );
}

class AboutLocalAiLabScreen extends StatefulWidget {
  const AboutLocalAiLabScreen({super.key, this.packageDetailsLoader});

  final AppPackageDetailsLoader? packageDetailsLoader;

  @override
  State<AboutLocalAiLabScreen> createState() => _AboutLocalAiLabScreenState();
}

class _AboutLocalAiLabScreenState extends State<AboutLocalAiLabScreen> {
  late final Future<AppPackageDetails> _details;

  @override
  void initState() {
    super.initState();
    _details = (widget.packageDetailsLoader ?? loadAppPackageDetails)();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About Local AI Lab')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                side: BorderSide(color: colors.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.science_outlined,
                      size: 40,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 16),
                    Text('Local AI Lab', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    FutureBuilder<AppPackageDetails>(
                      future: _details,
                      builder: (BuildContext context, snapshot) {
                        final String version =
                            switch (snapshot.connectionState) {
                              ConnectionState.waiting => 'Reading version…',
                              _ when snapshot.hasData =>
                                'Version ${snapshot.data!.displayVersion}',
                              _ => 'Version unavailable',
                            };
                        return Text(
                          version,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Explore and compare on-device AI models through the '
                      'Run and Compare workflows.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _AboutInfoCard(
              icon: Icons.lock_outline_rounded,
              title: 'Privacy',
              body:
                  'Your passages, prompts, generated output, comparison data, '
                  'and saved results are stored locally. Local AI Lab does not '
                  'transmit them or use accounts, analytics, cloud inference, '
                  'or Android backup.',
            ),
            const SizedBox(height: 16),
            const _AboutInfoCard(
              icon: Icons.language_rounded,
              title: 'Network use',
              body:
                  'Network-related actions occur only when you explicitly '
                  'discover a GGUF model, download a GGUF or LiteRT-LM model, '
                  'or open external model and license information. Gemini '
                  'Nano and installed GGUF and LiteRT-LM model inference run '
                  'on-device.',
            ),
            const SizedBox(height: 16),
            const _AboutInfoCard(
              icon: Icons.fact_check_outlined,
              title: 'Discovery Candidates',
              body:
                  'The Candidates section contains two paths. Curated '
                  'LiteRT-LM lists exact artifacts already audited and '
                  'qualified with the app’s pinned runtime. Each is public '
                  'and ungated, instruction or chat suitable, a single file '
                  'no larger than 3 GB, pinned to an immutable revision, and '
                  'recorded with its exact size, SHA-256 hash, license, '
                  'context, runtime profile, and thinking behavior.\n\n'
                  'GGUF Candidates are ordinary supported instruction or chat '
                  'models that meet Local AI Lab’s mechanical download and '
                  'compatibility requirements: public and ungated; one '
                  'complete, unsharded Q4_K_M artifact no larger than 3 GB; a '
                  'supported prompt and runtime family; resolvable license '
                  'information; and an available SHA-256 hash.\n\n'
                  'Discovery uses three bounded Hugging Face searches—'
                  'instruct, chat, and it-GGUF—together with maintained '
                  'fallback repositories. Duplicate repositories and '
                  'equivalent model results are removed.\n\n'
                  'Candidate status does not establish output quality, safety, '
                  'or practical performance on this phone. LiteRT-LM runtime '
                  'qualification confirms compatibility and clean operation, '
                  'not that a model is best. Use Run and Compare to evaluate '
                  'behavior.',
            ),
            const SizedBox(height: 16),
            const _AboutInfoCard(
              icon: Icons.help_outline_rounded,
              title: 'Understanding the requirements',
              body:
                  'GGUF is the model-file format used by Local AI Lab’s bundled '
                  'llama.cpp runtime.\n\n'
                  'LiteRT-LM artifacts are packaged model files used by '
                  'Google’s LiteRT-LM runtime. Local AI Lab accepts only exact '
                  'cataloged files and currently uses the GPU backend.\n\n'
                  'Q4_K_M is a balanced 4-bit quantization. Q4 means most model '
                  'weights use roughly four bits, reducing file size and '
                  'memory use. K identifies llama.cpp’s grouped quantization '
                  'family. M is the medium variant, retaining higher precision '
                  'for selected weights. Requiring one quantization keeps '
                  'phone downloads practical and comparisons more consistent; '
                  'it does not mean Q4_K_M is best for every device.\n\n'
                  'Single and unsharded means the model is one complete GGUF '
                  'file rather than several pieces, keeping installation and '
                  'exact verification reliable.\n\n'
                  'The 3 GB limit keeps Candidate downloads within the app’s '
                  'phone-focused boundary, but does not guarantee good speed '
                  'or memory behavior.\n\n'
                  'A supported prompt family means Local AI Lab recognizes how '
                  'the model expects instructions and conversation messages to '
                  'be formatted.\n\n'
                  'SHA-256 is a digital fingerprint used to confirm that the '
                  'downloaded bytes match the exact artifact advertised by '
                  'Hugging Face.\n\n'
                  'Public and ungated means the repository can be accessed '
                  'without an account, approval request, or access token.',
            ),
            const SizedBox(height: 16),
            const _AboutInfoCard(
              icon: Icons.analytics_outlined,
              title: 'How Compare results are calculated',
              body:
                  'Compare can run each selected model 1, 3, or 5 times. '
                  'Each run is executed independently and its individual '
                  'metrics and output remain available for inspection.\n\n'
                  'When more than one run succeeds, Local AI Lab summarizes '
                  'the completed runs using medians rather than averages. '
                  'Recall, latency, time to first token (TTFT), estimated '
                  'generation rate, and estimated token count use the median '
                  'of the applicable successful runs. Medians reduce the '
                  'influence of an unusually fast or slow individual run.\n\n'
                  'Latency also retains the minimum-to-maximum range when '
                  'multiple runs succeed. Failed runs are excluded from '
                  'median calculations, but the completed-run count still '
                  'shows how many requested runs succeeded.\n\n'
                  'For Two-Sentence Summary, Length Met is reported as the '
                  'number of completed structured runs that produced exactly '
                  'two sentences, such as 4/5. The representative output is '
                  'the successful run with median latency; individual runs '
                  'and outputs remain available for review.',
            ),
            const SizedBox(height: 16),
            const _AboutInfoCard(
              icon: Icons.recommend_outlined,
              title: 'Recommended models',
              body:
                  'Recommended is based on the most recent saved Compare '
                  'with successful results from at least two models. Models are '
                  'compared only against the other models tested in that '
                  'Compare session.\n\n'
                  'Recommended highlights the model or models with the strongest '
                  'measured results for recall, length compliance when available, '
                  'latency, time to first token (TTFT) where measurable, and '
                  'estimated end-to-end rate. '
                  'Ties are preserved. There is no combined overall score or '
                  'comparison across multiple Compare sessions.\n\n'
                  'Recommendations are specific to the device, task, models, and '
                  'Compare session tested. They are not a universal ranking '
                  'or a guarantee of future performance.',
            ),
            const SizedBox(height: 16),
            const _AboutInfoCard(
              icon: Icons.devices_other_rounded,
              title: 'Device-specific results',
              body:
                  'Hardware and software differ across Android devices. A '
                  'Candidate can meet the file and format requirements yet '
                  'fail to load, run slowly, heat the device, or be stopped by '
                  'the system when memory is limited. The 3 GB artifact limit '
                  'is a download boundary, not a runtime-memory guarantee. '
                  'Gemini Nano availability depends on device-specific AICore '
                  'support.\n\n'
                  'Compare and Recommended results are device-specific. The '
                  'same model can behave differently on other hardware or '
                  'software, so results from this device do not establish a '
                  'universal ranking or guarantee future performance. Generated '
                  'output can omit, alter, or invent details and requires direct '
                  'human review.\n\n'
                  'Local AI Lab is currently Android-only. Other devices and '
                  'future platform versions require separate implementation '
                  'and testing.',
            ),
          ],
        ),
      ),
    );
  }
}

class DeviceRuntimeScreen extends StatefulWidget {
  const DeviceRuntimeScreen({super.key, this.diagnosticsLoader});

  final RuntimeDiagnosticsLoader? diagnosticsLoader;

  @override
  State<DeviceRuntimeScreen> createState() => _DeviceRuntimeScreenState();
}

class _DeviceRuntimeScreenState extends State<DeviceRuntimeScreen> {
  late Future<RuntimeDiagnostics> _diagnostics;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _diagnostics = (widget.diagnosticsLoader ?? loadRuntimeDiagnostics)();
  }

  void _retry() {
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device and runtime information')),
      body: SafeArea(
        top: false,
        child: FutureBuilder<RuntimeDiagnostics>(
          future: _diagnostics,
          builder: (BuildContext context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return _DiagnosticsError(onRetry: _retry);
            }

            final RuntimeDiagnostics diagnostics = snapshot.data!;
            final String aiCoreStatus = diagnostics.geminiNanoAvailable
                ? 'Gemini Nano available'
                : 'Gemini Nano unavailable';
            final String baseModel =
                diagnostics.nanoBaseModelName?.trim().isNotEmpty == true
                ? diagnostics.nanoBaseModelName!.trim()
                : 'unavailable';
            final String aiCoreVersion =
                diagnostics.aiCoreVersion?.trim().isNotEmpty == true
                ? diagnostics.aiCoreVersion!.trim()
                : 'unavailable';

            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _AboutInfoCard(
                  icon: Icons.phone_android_rounded,
                  title: 'Device platform',
                  body: diagnostics.platformDescription,
                ),
                const SizedBox(height: 16),
                _AboutInfoCard(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Gemini Nano · AICore',
                  body:
                      '$aiCoreStatus\n'
                      'Base model: $baseModel\n'
                      'AICore service: $aiCoreVersion\n'
                      'ML Kit Prompt API: 1.0.0-beta4',
                  statusColor: diagnostics.geminiNanoAvailable
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                const _AboutInfoCard(
                  icon: Icons.memory_rounded,
                  title: 'GGUF · llama.cpp',
                  body:
                      'Bundled with Local AI Lab. Installed compatible GGUF '
                      'models run locally through llama_flutter_android 0.2.6.',
                ),
                const SizedBox(height: 16),
                const _AboutInfoCard(
                  icon: Icons.memory_rounded,
                  title: 'LiteRT-LM · GPU',
                  body:
                      'Bundled through flutter_gemma_litertlm 1.5.3, which '
                      'contains LiteRT-LM 0.16.0. Approved LiteRT-LM artifacts '
                      'run locally on the GPU backend with the runtime’s fixed '
                      'effective sampling.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DiagnosticsError extends StatelessWidget {
  const _DiagnosticsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Runtime information could not be loaded.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _AboutInfoCard extends StatelessWidget {
  const _AboutInfoCard({
    required this.icon,
    required this.title,
    required this.body,
    this.statusColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: statusColor ?? colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
