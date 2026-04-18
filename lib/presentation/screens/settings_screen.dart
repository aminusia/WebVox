import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_reader/core/utils/language_detector.dart';
import 'package:web_reader/domain/entities/settings.dart';
import 'package:web_reader/presentation/providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (settings) => _SettingsForm(settings: settings),
      ),
    );
  }
}

class _SettingsForm extends ConsumerWidget {
  final Settings settings;

  const _SettingsForm({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Text-to-Speech', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),

        // TTS Language
        DropdownButtonFormField<String>(
          initialValue: settings.ttsLanguage,
          decoration: const InputDecoration(
            labelText: 'TTS Language',
            border: OutlineInputBorder(),
          ),
          items:
              LanguageDetector.supportedLanguages
                  .map(
                    (lang) => DropdownMenuItem(value: lang, child: Text(lang)),
                  )
                  .toList(),
          onChanged: (val) {
            if (val != null) {
              // Reset voice when language changes
              notifier.update(
                settings.copyWith(ttsLanguage: val, ttsVoice: ''),
              );
            }
          },
        ),
        const SizedBox(height: 16),

        // TTS Voice
        _VoiceSelector(settings: settings),
        const SizedBox(height: 16),

        // TTS Speed
        Row(
          children: [
            const Text('Speed'),
            Expanded(
              child: Slider(
                value: settings.ttsSpeed,
                min: 0.25,
                max: 2.0,
                divisions: 7,
                label: '${settings.ttsSpeed}×',
                onChanged: (val) {
                  notifier.update(settings.copyWith(ttsSpeed: val));
                },
              ),
            ),
            Text('${settings.ttsSpeed.toStringAsFixed(2)}×'),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Speed changes take effect immediately, restarting the current paragraph.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Divider(height: 32),

        Text('Display', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),

        DropdownButtonFormField<ThemePreference>(
          initialValue: settings.themePreference,
          decoration: const InputDecoration(
            labelText: 'Theme',
            border: OutlineInputBorder(),
          ),
          items:
              ThemePreference.values.map((pref) {
                final label = switch (pref) {
                  ThemePreference.system => 'System default',
                  ThemePreference.light => 'Light',
                  ThemePreference.dark => 'Dark',
                };
                return DropdownMenuItem(value: pref, child: Text(label));
              }).toList(),
          onChanged: (val) {
            if (val != null) {
              notifier.update(settings.copyWith(themePreference: val));
            }
          },
        ),
        const SizedBox(height: 16),

        // Font size
        Row(
          children: [
            const Text('Font size'),
            Expanded(
              child: Slider(
                value: settings.fontSize,
                min: 12,
                max: 30,
                divisions: 18,
                label: '${settings.fontSize.round()}pt',
                onChanged: (val) {
                  notifier.update(settings.copyWith(fontSize: val));
                },
              ),
            ),
            Text('${settings.fontSize.round()}pt'),
          ],
        ),

        // Preview
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Preview: The quick brown fox jumps over the lazy dog.',
            style: TextStyle(fontSize: settings.fontSize, height: 1.7),
          ),
        ),
        const Divider(height: 32),

        Text('Reading', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),

        // Auto-next
        SwitchListTile(
          title: const Text('Auto-next page'),
          subtitle: const Text(
            'Automatically open the next page when reading finishes',
          ),
          value: settings.autoNext,
          onChanged: (val) {
            notifier.update(settings.copyWith(autoNext: val));
          },
        ),
      ],
    );
  }
}

class _VoiceSelector extends ConsumerWidget {
  final Settings settings;

  const _VoiceSelector({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voicesAsync = ref.watch(voicesProvider(settings.ttsLanguage));
    final notifier = ref.read(settingsProvider.notifier);

    return voicesAsync.when(
      loading:
          () => const InputDecorator(
            decoration: InputDecoration(
              labelText: 'Voice',
              border: OutlineInputBorder(),
            ),
            child: SizedBox(height: 20, child: LinearProgressIndicator()),
          ),
      error:
          (_, __) => const InputDecorator(
            decoration: InputDecoration(
              labelText: 'Voice',
              border: OutlineInputBorder(),
            ),
            child: Text('Voices unavailable'),
          ),
      data: (voices) {
        if (voices.isEmpty) return const SizedBox.shrink();

        String displayName(String name) {
          if (name.isEmpty) return 'Default (system)';
          var d = name;
          final h = d.indexOf('#');
          if (h >= 0) d = d.substring(h + 1);
          d = d.replaceAll(RegExp(r'-(local|remote)$'), '');
          return d.isNotEmpty ? d : name;
        }

        final currentVoice = settings.ttsVoice;

        return DropdownButtonFormField<String>(
          initialValue:
              voices.any((v) => v['name'] == currentVoice) ? currentVoice : '',
          decoration: const InputDecoration(
            labelText: 'Voice',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Default (system)')),
            ...voices.map(
              (v) => DropdownMenuItem(
                value: v['name'],
                child: Text(displayName(v['name'] ?? '')),
              ),
            ),
          ],
          onChanged: (val) {
            if (val == null) return;
            notifier.update(settings.copyWith(ttsVoice: val));
            // Apply immediately to TTS engine
            final locale =
                val.isEmpty
                    ? settings.ttsLanguage
                    : voices.firstWhere(
                          (v) => v['name'] == val,
                          orElse: () => {'locale': settings.ttsLanguage},
                        )['locale'] ??
                        settings.ttsLanguage;
            ref.read(ttsProvider.notifier).setVoice(val, locale);
          },
        );
      },
    );
  }
}
