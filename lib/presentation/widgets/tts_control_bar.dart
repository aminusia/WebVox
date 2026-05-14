import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webreader/core/theme/app_theme.dart';
import 'package:webreader/presentation/providers/providers.dart';
import 'package:webreader/presentation/providers/tts_notifier.dart';

/// Returns a human-readable label from a raw TTS voice name.
/// E.g. "en-us-x-sfg#female_1-local" → "female_1"
String _voiceDisplayName(String name) {
  if (name.isEmpty) return 'Default';
  var display = name;
  final hash = display.indexOf('#');
  if (hash >= 0) display = display.substring(hash + 1);
  display = display.replaceAll(RegExp(r'-(local|remote)$'), '');
  return display.isNotEmpty ? display : name;
}

class TtsControlBar extends ConsumerWidget {
  final List<String> paragraphs;
  final String articleLanguage;
  final String? articleTitle;
  final int startIndex;
  final int startWordOffset;
  final void Function(int index)? onParagraphChanged;

  const TtsControlBar({
    super.key,
    required this.paragraphs,
    required this.articleLanguage,
    this.articleTitle,
    this.startIndex = 0,
    this.startWordOffset = 0,
    this.onParagraphChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(ttsProvider);
    final notifier = ref.read(ttsProvider.notifier);
    final voicesAsync = ref.watch(voicesProvider(articleLanguage));

    ref.listen<TtsState>(ttsProvider, (_, next) {
      if (next.isActive) {
        onParagraphChanged?.call(next.currentIndex);
      }
    });

    // Wrap in a Theme so all icons and text render light on the dark bar.
    final barTheme = Theme.of(context).copyWith(
      iconTheme: const IconThemeData(color: AppColors.onBar),
      disabledColor: Colors.white38,
    );

    return Theme(
      data: barTheme,
      child: Card(
        color: AppColors.barColor,
        margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ttsState.total > 0)
                LinearProgressIndicator(
                  value: (ttsState.currentIndex + 1) / ttsState.total,
                  minHeight: 2,
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Speed selector
                  _SpeedButton(
                    speed: ttsState.speed,
                    onChanged: notifier.setSpeed,
                  ),
                  // Skip previous
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.skip_previous_rounded),
                    tooltip: 'Previous paragraph',
                    onPressed:
                        ttsState.isActive
                            ? () {
                              HapticFeedback.mediumImpact();
                              notifier.skipPrevious();
                            }
                            : null,
                  ),
                  // Play / Pause
                  if (!ttsState.isActive)
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Read'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        notifier.play(
                          paragraphs,
                          startIndex: startIndex,
                          wordOffset: startWordOffset,
                          language: articleLanguage,
                          articleTitle: articleTitle,
                        );
                      },
                    )
                  else if (ttsState.isPlaying)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.pause_rounded),
                      tooltip: 'Pause',
                      color: AppColors.onBar,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        notifier.pause();
                      },
                    )
                  else
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.play_arrow_rounded),
                      tooltip: 'Resume',
                      color: AppColors.onBar,
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        notifier.resume();
                      },
                    ),
                  // Skip next
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.skip_next_rounded),
                    tooltip: 'Next paragraph',
                    onPressed:
                        ttsState.isActive
                            ? () {
                              HapticFeedback.mediumImpact();
                              notifier.skipNext();
                            }
                            : null,
                  ),
                  // Voice selector (inline, compact)
                  voicesAsync.maybeWhen(
                    data: (voices) {
                      if (voices.isEmpty) return const SizedBox.shrink();
                      return _VoiceButton(
                        voices: voices,
                        currentVoice: ttsState.voiceName,
                        language: articleLanguage,
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                  // Position text
                  Text(
                    ttsState.total > 0
                        ? '${ttsState.currentIndex + 1}/${ttsState.total}'
                        : '',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppColors.onBar),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceButton extends ConsumerWidget {
  final List<Map<String, String>> voices;
  final String currentVoice;
  final String language;

  const _VoiceButton({
    required this.voices,
    required this.currentVoice,
    required this.language,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = _voiceDisplayName(currentVoice);

    return PopupMenuButton<String>(
      tooltip: 'Select voice',
      initialValue: currentVoice.isEmpty ? '' : currentVoice,
      onSelected: (name) {
        final voiceMap = voices.firstWhere(
          (v) => v['name'] == name,
          orElse: () => {'locale': language},
        );
        final locale = voiceMap['locale'] ?? language;
        ref.read(ttsProvider.notifier).setVoice(name, locale);
        ref.read(settingsProvider).whenData((s) {
          ref
              .read(settingsProvider.notifier)
              .update(s.copyWith(ttsVoice: name));
        });
      },
      itemBuilder:
          (_) => [
            const PopupMenuItem<String>(value: '', child: Text('Default')),
            ...voices.map(
              (v) => PopupMenuItem<String>(
                value: v['name'],
                child: Text(_voiceDisplayName(v['name'] ?? '')),
              ),
            ),
          ],
      child: Tooltip(
        message: label,
        child: Icon(
          Icons.record_voice_over_rounded,
          size: 20,
          // On the dark bar, use full white when a voice is selected,
          // dim white when using the default.
          color: currentVoice.isEmpty ? Colors.white54 : AppColors.onBar,
        ),
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  final double speed;
  final Future<void> Function(double) onChanged;

  const _SpeedButton({required this.speed, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final label =
        speed == speed.truncateToDouble()
            ? '${speed.toInt()}×'
            : '${speed.toStringAsFixed(1)}×';

    return PopupMenuButton<double>(
      tooltip: 'Speed',
      initialValue: speed,
      onSelected: onChanged,
      itemBuilder:
          (_) => const [
            PopupMenuItem(value: 0.25, child: Text('0.25×')),
            PopupMenuItem(value: 0.5, child: Text('0.5×')),
            PopupMenuItem(value: 0.75, child: Text('0.75×')),
            PopupMenuItem(value: 1.0, child: Text('1.0×')),
            PopupMenuItem(value: 1.25, child: Text('1.25×')),
            PopupMenuItem(value: 1.5, child: Text('1.5×')),
            PopupMenuItem(value: 2.0, child: Text('2.0×')),
          ],
      child: Chip(visualDensity: VisualDensity.compact, label: Text(label)),
    );
  }
}
