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
    this.aiCoreVersion,
  });

  final String platformDescription;
  final bool geminiNanoAvailable;
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
  final String? aiCoreVersion = await GeminiNanoService.getAiCoreVersion();
  return RuntimeDiagnostics(
    platformDescription: Platform.operatingSystemVersion,
    geminiNanoAvailable: nanoAvailable,
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
                      'Compare on-device AI models using the same controlled '
                      'Playground and Benchmark workflows.',
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
                  'Your passages, prompts, generated output, benchmark data, '
                  'and saved results remain on this device. Local AI Lab does '
                  'not use accounts, analytics, or cloud inference.',
            ),
            const SizedBox(height: 16),
            const _AboutInfoCard(
              icon: Icons.language_rounded,
              title: 'Network use',
              body:
                  'Network-related actions occur only when you explicitly '
                  'discover or download a GGUF model, or open external model '
                  'and license information. Gemini Nano and installed GGUF '
                  'model inference run on-device.',
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
            final String? version = diagnostics.aiCoreVersion;

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
                  body: version == null
                      ? aiCoreStatus
                      : '$aiCoreStatus\nAICore $version',
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
                      'models run locally through this runtime.',
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
