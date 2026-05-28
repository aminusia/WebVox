import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webvox/core/constants/app_constants.dart';
import 'package:webvox/core/services/platform_service.dart';
import 'package:webvox/core/utils/language_detector.dart';
import 'package:webvox/domain/entities/settings.dart';
import 'package:webvox/presentation/providers/providers.dart';
import 'package:webvox/presentation/screens/cache_log_screen.dart';

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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Section label style: small-caps, primary colour
    Widget sectionHeader(String title) => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: tt.labelSmall?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );

    // Rounded card that clips its children (so ListTiles get rounded corners)
    Widget sectionCard(List<Widget> children) => Card(
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // ── Text-to-Speech ──────────────────────────────────────────────
        sectionHeader('Text-to-Speech'),
        sectionCard([
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _TtsEngineSelector(settings: settings),
          ),
          Divider(height: 1, color: Colors.white.withAlpha(15)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: DropdownButtonFormField<String>(
              initialValue: settings.ttsLanguage,
              decoration: const InputDecoration(labelText: 'TTS Language'),
              items:
                  LanguageDetector.supportedLanguages
                      .map(
                        (lang) =>
                            DropdownMenuItem(value: lang, child: Text(lang)),
                      )
                      .toList(),
              onChanged: (val) {
                if (val != null) {
                  notifier.update(
                    settings.copyWith(ttsLanguage: val, ttsVoice: ''),
                  );
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _VoiceSelector(settings: settings),
          ),
          Divider(height: 1, color: Colors.white.withAlpha(15)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Text('Speed'),
                Expanded(
                  child: Slider(
                    value: settings.ttsSpeed,
                    min: 0.25,
                    max: 2.0,
                    divisions: 7,
                    label: '${settings.ttsSpeed}×',
                    onChanged:
                        (val) =>
                            notifier.update(settings.copyWith(ttsSpeed: val)),
                  ),
                ),
                Text('${settings.ttsSpeed.toStringAsFixed(2)}×'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Speed changes take effect immediately, restarting the current paragraph.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Divider(height: 1, color: Colors.white.withAlpha(15)),
          _VoiceTestTile(),
          Divider(height: 1, color: Colors.white.withAlpha(15)),
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: const Text('Android TTS settings'),
            subtitle: const Text('Add voices, change the default engine'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => PlatformService.openTtsSettings(),
          ),
        ]),
        const SizedBox(height: 20),

        // ── Display ─────────────────────────────────────────────────────
        sectionHeader('Display'),
        sectionCard([
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: DropdownButtonFormField<ThemePreference>(
              initialValue: settings.themePreference,
              decoration: const InputDecoration(labelText: 'Theme'),
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
          ),
          Divider(height: 1, color: Colors.white.withAlpha(15)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Text('Font size'),
                Expanded(
                  child: Slider(
                    value: settings.fontSize,
                    min: 12,
                    max: 30,
                    divisions: 18,
                    label: '${settings.fontSize.round()}pt',
                    onChanged:
                        (val) =>
                            notifier.update(settings.copyWith(fontSize: val)),
                  ),
                ),
                Text('${settings.fontSize.round()}pt'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Preview: The quick brown fox jumps over the lazy dog.',
                style: TextStyle(fontSize: settings.fontSize, height: 1.7),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),

        // ── Reading ──────────────────────────────────────────────────────
        sectionHeader('Reading'),
        sectionCard([
          SwitchListTile(
            title: const Text('Auto-read on open'),
            subtitle: const Text(
              'Automatically start reading aloud when a page is opened',
            ),
            value: settings.autoRead,
            onChanged:
                (val) => notifier.update(settings.copyWith(autoRead: val)),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('Auto-next page'),
            subtitle: const Text(
              'Automatically open the next page when reading finishes',
            ),
            value: settings.autoNext,
            onChanged:
                (val) => notifier.update(settings.copyWith(autoNext: val)),
          ),
        ]),
        const SizedBox(height: 20),

        // ── Highlighting ─────────────────────────────────────────────────
        sectionHeader('Highlighting'),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Customize how the active paragraph and word are highlighted during playback.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Paragraph',
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        sectionCard([
          Padding(
            padding: const EdgeInsets.all(16),
            child: _HighlightStyleEditor(
              colorValue: settings.paragraphHighlightColor,
              backgroundValue: settings.paragraphHighlightBackground,
              decoration: settings.paragraphHighlightDecoration,
              onChanged: ({
                required int colorValue,
                required int? backgroundValue,
                required HighlightDecoration decoration,
              }) {
                notifier.update(
                  settings.copyWith(
                    paragraphHighlightColor: colorValue,
                    paragraphHighlightBackground: backgroundValue,
                    paragraphHighlightDecoration: decoration,
                  ),
                );
              },
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Word',
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        sectionCard([
          Padding(
            padding: const EdgeInsets.all(16),
            child: _HighlightStyleEditor(
              colorValue: settings.wordHighlightColor,
              backgroundValue: settings.wordHighlightBackground,
              decoration: settings.wordHighlightDecoration,
              onChanged: ({
                required int colorValue,
                required int? backgroundValue,
                required HighlightDecoration decoration,
              }) {
                notifier.update(
                  settings.copyWith(
                    wordHighlightColor: colorValue,
                    wordHighlightBackground: backgroundValue,
                    wordHighlightDecoration: decoration,
                  ),
                );
              },
            ),
          ),
        ]),
        const SizedBox(height: 20),

        // ── Cache ────────────────────────────────────────────────────────
        sectionHeader('Cache'),
        sectionCard([
          SwitchListTile(
            title: const Text('Enable background caching'),
            subtitle: const Text('Pre-fetch next articles while reading'),
            value: settings.cachingEnabled,
            onChanged:
                (val) =>
                    notifier.update(settings.copyWith(cachingEnabled: val)),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            title: const Text('Cache while in background'),
            subtitle: const Text(
              'Continue pre-fetching when the app is minimised',
            ),
            value: settings.cacheInBackground && settings.cachingEnabled,
            onChanged:
                settings.cachingEnabled
                    ? (val) => notifier.update(
                      settings.copyWith(cacheInBackground: val),
                    )
                    : null,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('Cache log'),
            subtitle: const Text('View background caching activity'),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CacheLogScreen()),
                ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _ClearCacheButton(),
        ]),
        const SizedBox(height: 20),

        // ── About ────────────────────────────────────────────────────────
        sectionHeader('About'),
        sectionCard([const _AppVersionTile()]),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _ClearCacheButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ClearCacheButton> createState() => _ClearCacheButtonState();
}

class _ClearCacheButtonState extends ConsumerState<_ClearCacheButton> {
  bool _busy = false;

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Clear cache?'),
            content: const Text(
              'All cached articles (except bookmarks) will be deleted. '
              'The cache queue will also be cleared.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final repo = ref.read(articleRepositoryProvider);
      final cacheService = ref.read(articleCacheServiceProvider);
      final deleted = await repo.clearCachedArticles();
      await cacheService.clearQueue();
      ref.read(recentArticlesProvider.notifier).load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cache cleared ($deleted articles removed).')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          _busy
              ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.delete_sweep_outlined),
      title: const Text('Clear cache'),
      subtitle: const Text('Delete all cached articles except bookmarks'),
      onTap: _busy ? null : _clear,
    );
  }
}

class _TtsEngineSelector extends ConsumerWidget {
  final Settings settings;

  const _TtsEngineSelector({required this.settings});

  String _engineLabel(String name) {
    if (name == AppConstants.googleTtsEngine) return 'Google Text-to-Speech';
    if (name.isEmpty) return 'System default';
    // Use the last segment of the package name as a readable label
    return name.split('.').last;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enginesAsync = ref.watch(enginesProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return enginesAsync.when(
      loading:
          () => const InputDecorator(
            decoration: InputDecoration(labelText: 'TTS Engine'),
            child: SizedBox(height: 20, child: LinearProgressIndicator()),
          ),
      error: (_, __) => const SizedBox.shrink(),
      data: (engines) {
        // Only show selector if there are multiple engines.
        if (engines.length <= 1) return const SizedBox.shrink();

        final currentEngine = settings.ttsEngine;
        final validEngine =
            engines.any((e) => e['name'] == currentEngine) ? currentEngine : '';

        return DropdownButtonFormField<String>(
          value: validEngine,
          decoration: const InputDecoration(labelText: 'TTS Engine'),
          items: [
            const DropdownMenuItem(value: '', child: Text('System default')),
            ...engines.map(
              (e) => DropdownMenuItem(
                value: e['name'],
                child: Text(_engineLabel(e['name'] ?? '')),
              ),
            ),
          ],
          onChanged: (val) {
            if (val == null) return;
            // Clear voice when engine changes
            notifier.update(settings.copyWith(ttsEngine: val, ttsVoice: ''));
            ref.read(ttsProvider.notifier).setEngine(val);
          },
        );
      },
    );
  }
}

class _VoiceTestTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_VoiceTestTile> createState() => _VoiceTestTileState();
}

class _VoiceTestTileState extends ConsumerState<_VoiceTestTile> {
  bool _busy = false;

  Future<void> _runTest() async {
    setState(() => _busy = true);
    try {
      await ref.read(ttsProvider.notifier).speakTest();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          _busy
              ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.volume_up_rounded),
      title: const Text('Test voice'),
      subtitle: const Text('"This is a voice test."'),
      trailing: FilledButton.tonal(
        onPressed: _busy ? null : _runTest,
        child: const Text('Play'),
      ),
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
            decoration: InputDecoration(labelText: 'Voice'),
            child: SizedBox(height: 20, child: LinearProgressIndicator()),
          ),
      error:
          (_, __) => const InputDecorator(
            decoration: InputDecoration(labelText: 'Voice'),
            child: Text('Voices unavailable'),
          ),
      data: (voices) {
        if (voices.isEmpty) return const SizedBox.shrink();

        String displayName(Map<String, String> v) =>
            v['display_name']?.isNotEmpty == true
                ? v['display_name']!
                : (v['name'] ?? '');

        final currentVoice = settings.ttsVoice;

        return DropdownButtonFormField<String>(
          initialValue:
              voices.any((v) => v['name'] == currentVoice) ? currentVoice : '',
          decoration: const InputDecoration(labelText: 'Voice'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Default (system)')),
            ...voices.map(
              (v) => DropdownMenuItem(
                value: v['name'],
                child: Text(displayName(v)),
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

// ─── App version ─────────────────────────────────────────────────────────────

class _AppVersionTile extends StatefulWidget {
  const _AppVersionTile();

  @override
  State<_AppVersionTile> createState() => _AppVersionTileState();
}

class _AppVersionTileState extends State<_AppVersionTile> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() {
          _version = '${info.version} (${info.buildNumber})';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('Version'),
      trailing: Text(
        _version.isEmpty ? '…' : _version,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ─── Highlight style editor ───────────────────────────────────────────────────

typedef _OnHighlightChanged =
    void Function({
      required int colorValue,
      required int? backgroundValue,
      required HighlightDecoration decoration,
    });

class _HighlightStyleEditor extends StatelessWidget {
  final int colorValue;
  final int? backgroundValue;
  final HighlightDecoration decoration;
  final _OnHighlightChanged onChanged;

  const _HighlightStyleEditor({
    required this.colorValue,
    required this.backgroundValue,
    required this.decoration,
    required this.onChanged,
  });

  void _pickColor(BuildContext context, bool isBackground) {
    final currentColor =
        isBackground
            ? (backgroundValue != null ? Color(backgroundValue!) : null)
            : Color(colorValue);

    showDialog<Color?>(
      context: context,
      builder:
          (ctx) => _ColorPickerDialog(
            selectedColor: currentColor,
            allowNone: isBackground,
          ),
    ).then((picked) {
      if (!context.mounted) return;
      if (isBackground) {
        // null means "remove background"
        onChanged(
          colorValue: colorValue,
          backgroundValue:
              picked == null && backgroundValue != null
                  ? null
                  : picked?.toARGB32() ?? backgroundValue,
          decoration: decoration,
        );
      } else if (picked != null) {
        onChanged(
          colorValue: picked.toARGB32(),
          backgroundValue: backgroundValue,
          decoration: decoration,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Color(colorValue);
    final bgColor = backgroundValue != null ? Color(backgroundValue!) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preview
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Sample highlighted text',
            style: TextStyle(
              color: textColor,
              backgroundColor: bgColor,
              decoration: _toTextDecoration(decoration),
              decorationColor: textColor,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Text color row
        Row(
          children: [
            const SizedBox(width: 2),
            const Text('Text color'),
            const Spacer(),
            GestureDetector(
              onTap: () => _pickColor(context, false),
              child: _ColorSwatch(color: textColor),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Background color row
        Row(
          children: [
            const SizedBox(width: 2),
            const Text('Background'),
            const Spacer(),
            GestureDetector(
              onTap: () => _pickColor(context, true),
              child:
                  bgColor != null
                      ? _ColorSwatch(color: bgColor)
                      : _ColorSwatchNone(),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Decoration dropdown
        DropdownButtonFormField<HighlightDecoration>(
          initialValue: decoration,
          decoration: const InputDecoration(labelText: 'Decoration'),
          items: const [
            DropdownMenuItem(
              value: HighlightDecoration.none,
              child: Text('None'),
            ),
            DropdownMenuItem(
              value: HighlightDecoration.underline,
              child: Text('Underline'),
            ),
            DropdownMenuItem(
              value: HighlightDecoration.lineThrough,
              child: Text('Strikethrough'),
            ),
            DropdownMenuItem(
              value: HighlightDecoration.overline,
              child: Text('Overline'),
            ),
          ],
          onChanged: (val) {
            if (val == null) return;
            onChanged(
              colorValue: colorValue,
              backgroundValue: backgroundValue,
              decoration: val,
            );
          },
        ),
      ],
    );
  }

  TextDecoration _toTextDecoration(HighlightDecoration d) {
    switch (d) {
      case HighlightDecoration.underline:
        return TextDecoration.underline;
      case HighlightDecoration.lineThrough:
        return TextDecoration.lineThrough;
      case HighlightDecoration.overline:
        return TextDecoration.overline;
      case HighlightDecoration.none:
        return TextDecoration.none;
    }
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;

  const _ColorSwatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _ColorSwatchNone extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Center(
        child: Icon(Icons.block, size: 18, color: Colors.grey),
      ),
    );
  }
}

// ─── Color picker dialog ──────────────────────────────────────────────────────

class _ColorPickerDialog extends StatelessWidget {
  final Color? selectedColor;
  final bool allowNone;

  const _ColorPickerDialog({
    required this.selectedColor,
    this.allowNone = false,
  });

  static const List<Color> _palette = [
    Color(0xFF2196F3),
    Color(0xFFB8860B),
    Color(0xFF4CAF50),
    Color(0xFFF44336),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFE91E63),
    Color(0xFF795548),
    Color(0xFF607D8B),
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFFFFEB3B), // yellow
    Color(0xFF8BC34A), // light green
    Color(0xFF03A9F4), // light blue
    Color(0xFFFF5722), // deep orange
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick a color'),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (allowNone)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(null),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(Icons.block, size: 20, color: Colors.grey),
                      ),
                    ),
                  ),
                ..._palette.map(
                  (c) => GestureDetector(
                    onTap: () => Navigator.of(context).pop(c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        border: Border.all(
                          color:
                              selectedColor == c
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                          width: selectedColor == c ? 3 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(selectedColor),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
