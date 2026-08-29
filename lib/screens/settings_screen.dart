import 'package:flutter/material.dart';

Future<void> openSettings(BuildContext context) async {
  await Navigator.of(
    context,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Appearance',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.brightness_auto_outlined),
                  title: Text('Theme'),
                  subtitle: Text('System'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.palette_outlined),
                  title: Text('Color theme'),
                  subtitle: Text('AI Blue'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: colorScheme.secondaryContainer,
            child: const ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('Current appearance'),
              subtitle: Text(
                'Theme controls and persistence will be added in a focused '
                'Settings change.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
