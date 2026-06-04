import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webvox/core/constants/app_constants.dart';
import 'package:webvox/core/theme/app_theme.dart';

// ─── Steps ───────────────────────────────────────────────────────────────────

enum ReaderTutorialStep { bookmark, toggleTtsBar, voiceSelection, readArticle }

// ─── Controller ──────────────────────────────────────────────────────────────

/// Manages the lifecycle of the reader-screen tutorial.
///
/// Call [checkShouldShow] right after the first frame and it will decide
/// whether to start the sequence.  Each step is shown via [showStep] and
/// advanced with [nextStep].  [dismissTutorial] tears everything down and
/// marks the tutorial as completed so it never appears again.
class ReaderTutorialController {
  ReaderTutorialController({
    required this.context,
    required this.onShowOverlay,
    required this.onRemoveOverlay,
    required this.getTargetBox,
    required this.onOpenTtsBar,
    required this.isTtsBarOpen,
  });

  final BuildContext context;
  final void Function(OverlayEntry entry) onShowOverlay;
  final void Function() onRemoveOverlay;

  /// Returns the [RenderBox] of the target widget for the given step,
  /// or `null` if the widget is not yet in the tree.
  final RenderBox? Function(ReaderTutorialStep step) getTargetBox;

  /// Called before showing Step 3 so the TTS bar is guaranteed open.
  final Future<void> Function() onOpenTtsBar;

  /// Returns whether the TTS bar is currently visible.
  final bool Function() isTtsBarOpen;

  ReaderTutorialStep? _currentStep;
  OverlayEntry? _overlayEntry;
  bool _dismissed = false;

  bool get isRunning => _currentStep != null;

  /// Check if the tutorial should be shown and start it if so.
  Future<void> checkShouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    final completed =
        prefs.getBool(AppConstants.prefReaderTutorialCompleted) ?? false;
    if (completed) return;
    // Small delay so the first frame paints.
    await Future.delayed(const Duration(milliseconds: 500));
    if (context.mounted) startTutorial();
  }

  void startTutorial() {
    _dismissed = false;
    showStep(ReaderTutorialStep.bookmark);
  }

  Future<void> showStep(ReaderTutorialStep step) async {
    if (_dismissed) return;
    _currentStep = step;

    // Auto-open TTS bar before voice-selection / read-article steps.
    if ((step == ReaderTutorialStep.voiceSelection ||
            step == ReaderTutorialStep.readArticle) &&
        !isTtsBarOpen()) {
      await onOpenTtsBar();
      // Give the layout a frame to settle.
      await Future.delayed(const Duration(milliseconds: 350));
    }

    if (_dismissed || !context.mounted) return;

    final targetBox = getTargetBox(step);
    if (targetBox == null) {
      // Target not available — skip this step.
      nextStep();
      return;
    }

    final targetOffset = targetBox.localToGlobal(Offset.zero);
    final targetSize = targetBox.size;

    _overlayEntry?.remove();
    _overlayEntry = OverlayEntry(
      builder:
          (_) => _TutorialBalloonOverlay(
            targetOffset: targetOffset,
            targetSize: targetSize,
            step: step,
            isLastStep: step == ReaderTutorialStep.readArticle,
            onNext: nextStep,
            onDismiss: dismissTutorial,
          ),
    );
    onShowOverlay(_overlayEntry!);
  }

  void nextStep() {
    if (_dismissed) return;
    _overlayEntry?.remove();
    _overlayEntry = null;

    final steps = ReaderTutorialStep.values;
    final idx = steps.indexOf(_currentStep!);
    if (idx < steps.length - 1) {
      showStep(steps[idx + 1]);
    } else {
      completeTutorial();
    }
  }

  void dismissTutorial() {
    if (_dismissed) return;
    _dismissed = true;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _currentStep = null;
    _persistCompleted();
  }

  void completeTutorial() {
    _dismissed = true;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _currentStep = null;
    _persistCompleted();
  }

  void cancelIfRunning() {
    if (!isRunning) return;
    _dismissed = true;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _currentStep = null;
    // Do NOT persist — user left before finishing.
  }

  Future<void> _persistCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefReaderTutorialCompleted, true);
  }
}

// ─── Overlay (dimming + balloon) ─────────────────────────────────────────────

class _TutorialBalloonOverlay extends StatefulWidget {
  final Offset targetOffset;
  final Size targetSize;
  final ReaderTutorialStep step;
  final bool isLastStep;
  final VoidCallback onNext;
  final VoidCallback onDismiss;

  const _TutorialBalloonOverlay({
    required this.targetOffset,
    required this.targetSize,
    required this.step,
    required this.isLastStep,
    required this.onNext,
    required this.onDismiss,
  });

  @override
  State<_TutorialBalloonOverlay> createState() =>
      _TutorialBalloonOverlayState();
}

class _TutorialBalloonOverlayState extends State<_TutorialBalloonOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    // Same timing as the existing _PlayHereOverlay.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _animateOutAndExecute(VoidCallback action) async {
    await _controller.reverse();
    if (mounted) action();
  }

  // ── Copy helpers (matches _PlayHereOverlay style) ────────────────────────

  String _stepTitle() {
    switch (widget.step) {
      case ReaderTutorialStep.bookmark:
        return 'Bookmark';
      case ReaderTutorialStep.toggleTtsBar:
        return 'Text-to-Speech';
      case ReaderTutorialStep.voiceSelection:
        return 'Voice';
      case ReaderTutorialStep.readArticle:
        return 'Read Aloud';
    }
  }

  String _stepDescription() {
    switch (widget.step) {
      case ReaderTutorialStep.bookmark:
        return 'Save this article to your bookmarks\nfor quick access later.';
      case ReaderTutorialStep.toggleTtsBar:
        return 'Open the text-to-speech controls\nto listen to this article.';
      case ReaderTutorialStep.voiceSelection:
        return 'Choose the voice that will\nread the article.';
      case ReaderTutorialStep.readArticle:
        return 'Start reading the article aloud\nusing the selected voice.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final target = widget.targetOffset;
    final targetSize = widget.targetSize;

    // Spotlight cutout rect with some padding.
    const spotlightPad = 8.0;
    final spotlightRect = Rect.fromLTWH(
      target.dx - spotlightPad,
      target.dy - spotlightPad,
      targetSize.width + spotlightPad * 2,
      targetSize.height + spotlightPad * 2,
    );

    // Balloon positioning: prefer below the target, flip to above if not
    // enough room.  Horizontally centered on the target.
    const balloonMaxWidth = 280.0;
    const gap = 12.0;

    final spaceBelow =
        screen.height - target.dy - targetSize.height - padding.bottom;
    final showBelow = spaceBelow > 120;

    final balloonTop =
        showBelow ? target.dy + targetSize.height + gap : target.dy - gap;

    // Clamp horizontal so the balloon stays on-screen.
    double balloonLeft = target.dx + targetSize.width / 2 - balloonMaxWidth / 2;
    balloonLeft = balloonLeft.clamp(
      16.0,
      screen.width - balloonMaxWidth - 16.0,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onNext,
            child: Stack(
              children: [
                // ── Dimming layer with spotlight cutout ──────────────────────
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SpotlightPainter(
                      spotlight: spotlightRect,
                      opacity: _opacity.value * 0.45,
                    ),
                  ),
                ),
                // ── Elevated target ─────────────────────────────────────────
                Positioned(
                  left: spotlightRect.left,
                  top: spotlightRect.top,
                  width: spotlightRect.width,
                  height: spotlightRect.height,
                  child: Opacity(
                    opacity: 1.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryColor.withAlpha(
                              (_opacity.value * 120).round(),
                            ),
                            blurRadius: 16,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // ── Balloon ─────────────────────────────────────────────────
                Positioned(
                  left: balloonLeft,
                  top:
                      showBelow
                          ? target.dy + targetSize.height + gap
                          : balloonTop - 100,
                  width: balloonMaxWidth,
                  child: Opacity(
                    opacity: _opacity.value,
                    child: ScaleTransition(
                      scale: _scale,
                      alignment: Alignment(0, showBelow ? -1.0 : 1.0),
                      child: _TutorialBalloon(
                        title: _stepTitle(),
                        description: _stepDescription(),
                        buttonText: widget.isLastStep ? 'Got it' : 'Next',
                        onPressed: () {
                          _animateOutAndExecute(widget.onNext);
                        },
                        onClose: () {
                          _animateOutAndExecute(widget.onDismiss);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Spotlight painter ───────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect spotlight;
  final double opacity;

  _SpotlightPainter({required this.spotlight, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.black.withAlpha((opacity * 255).round())
          ..style = PaintingStyle.fill;

    final path =
        Path()
          ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
          ..addRRect(
            RRect.fromRectAndRadius(spotlight, const Radius.circular(12)),
          )
          ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Subtle border around the spotlight.
    final borderPaint =
        Paint()
          ..color = AppColors.primaryColor.withAlpha((opacity * 200).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(spotlight, const Radius.circular(12)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.opacity != opacity;
}

// ─── Balloon widget (reuses the same animation timings as _PlayHereOverlay) ──

class _TutorialBalloon extends StatelessWidget {
  final String title;
  final String description;
  final String buttonText;
  final VoidCallback onPressed;
  final VoidCallback onClose;

  const _TutorialBalloon({
    required this.title,
    required this.description,
    required this.buttonText,
    required this.onPressed,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.barColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(90),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and close button.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.titleColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Description.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                description,
                style: const TextStyle(
                  color: AppColors.bodyColor,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
