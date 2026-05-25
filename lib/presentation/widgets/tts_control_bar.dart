import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webvox/core/theme/app_theme.dart';
import 'package:webvox/presentation/providers/providers.dart';
import 'package:webvox/presentation/providers/tts_notifier.dart';

/// Returns a human-readable label from a raw TTS voice name.
/// Handles Google TTS voice patterns like:
///   "en-us-x-sfg#female_1-local"  → "female 1 ✦" (Google, local)
///   "en-us-x-sfg#male_2-remote"   → "male 2 ☁" (Google, remote/network)
///   Plain names are returned as-is (trimmed).
String _voiceDisplayName(String name) {
  if (name.isEmpty) return 'Default';

  // Google TTS pattern: contains '#'
  if (name.contains('#')) {
    final hashIdx = name.indexOf('#');
    final variant = name.substring(hashIdx + 1);
    final isRemote = variant.endsWith('-remote');
    final label = variant
        .replaceAll(RegExp(r'-(local|remote)$'), '')
        .replaceAll('_', ' ');
    final suffix = isRemote ? ' ☁' : '';
    return '${label.isNotEmpty ? label : name}$suffix';
  }

  return name;
}

class TtsControlBar extends ConsumerWidget {
  final List<String> paragraphs;
  final String articleLanguage;
  final String? articleTitle;
  final int startIndex;
  final int startWordOffset;
  final void Function(int index)? onParagraphChanged;

  /// When non-null, the position-text is replaced by a tappable article icon
  /// that calls this callback (used on the home screen to navigate to reader).
  final VoidCallback? onNavigateToReader;

  const TtsControlBar({
    super.key,
    required this.paragraphs,
    required this.articleLanguage,
    this.articleTitle,
    this.startIndex = 0,
    this.startWordOffset = 0,
    this.onParagraphChanged,
    this.onNavigateToReader,
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

    // Wrap in a fixed dark Theme so all icons and text render with AppColors.onBar
    // regardless of the app's light/dark setting.
    final barTheme = ThemeData.dark().copyWith(
      iconTheme: const IconThemeData(color: AppColors.onBar),
      disabledColor: Colors.white38,
    );

    return Theme(
      data: barTheme,
      child: Container(
        margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(90),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Card(
          color: AppColors.barColor,
          margin: EdgeInsets.zero,
          elevation: 8,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ttsState.total > 0)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    child: LinearProgressIndicator(
                      value: (ttsState.currentIndex + 1) / ttsState.total,
                      minHeight: 4,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primaryColor,
                      ),
                      backgroundColor: Colors.white12,
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Speed selector
                    // _SpeedButton(
                    //   speed: ttsState.speed,
                    //   onChanged: notifier.setSpeed,
                    // ),
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
                    // Skip previous
                    Opacity(
                      opacity: ttsState.isActive ? 0.85 : 0.4,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.skip_previous_rounded,
                          color: AppColors.onBar,
                          size: 20,
                        ),
                        tooltip: 'Previous paragraph',
                        onPressed:
                            ttsState.isActive
                                ? () {
                                  HapticFeedback.mediumImpact();
                                  notifier.skipPrevious();
                                }
                                : null,
                      ),
                    ),
                    // Play / Pause
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0,
                        end: ttsState.isPlaying ? 1.0 : 0.0,
                      ),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOut,
                      builder: (context, glowValue, child) {
                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow:
                                glowValue > 0
                                    ? [
                                      BoxShadow(
                                        color: AppColors.primaryColor.withAlpha(
                                          (glowValue * 100).round(),
                                        ),
                                        blurRadius: glowValue * 20,
                                        spreadRadius: glowValue * 2,
                                      ),
                                    ]
                                    : null,
                          ),
                          child: child,
                        );
                      },
                      child: Builder(
                        builder: (context) {
                          if (!ttsState.isActive) {
                            return FilledButton.icon(
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: const Text('Read'),
                              style: FilledButton.styleFrom(
                                foregroundColor: AppColors.onBar,
                                backgroundColor: AppColors.primaryColor,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
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
                            );
                          } else if (ttsState.isPlaying) {
                            return IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.pause_rounded,
                                color: AppColors.onBar,
                              ),
                              tooltip: 'Pause',
                              color: AppColors.onBar,
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                notifier.pause();
                              },
                            );
                          } else {
                            return IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                color: AppColors.onBar,
                              ),
                              tooltip: 'Resume',
                              color: AppColors.onBar,
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                notifier.resume();
                              },
                            );
                          }
                        },
                      ),
                    ),
                    // Skip next
                    Opacity(
                      opacity: ttsState.isActive ? 0.85 : 0.4,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: AppColors.onBar,
                          size: 20,
                        ),
                        tooltip: 'Next paragraph',
                        onPressed:
                            ttsState.isActive
                                ? () {
                                  HapticFeedback.mediumImpact();
                                  notifier.skipNext();
                                }
                                : null,
                      ),
                    ),
                    // Position text or navigate-to-reader icon
                    if (onNavigateToReader != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.article_outlined,
                          color: AppColors.onBar,
                        ),
                        tooltip: 'Go to article',
                        onPressed: onNavigateToReader,
                      )
                    else
                      Text(
                        ttsState.total > 0
                            ? '${ttsState.currentIndex + 1}/${ttsState.total}'
                            : '~',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.onBar,
                        ),
                      ),
                  ],
                ),
              ],
            ),
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
          color: AppColors.onBar,
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
