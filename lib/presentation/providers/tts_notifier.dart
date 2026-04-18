import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:web_reader/domain/repositories/settings_repository.dart';

// ─── Status ──────────────────────────────────────────────────────────────────

enum TtsStatus { idle, loading, playing, paused, stopped, error }

// ─── State ────────────────────────────────────────────────────────────────────

class TtsState {
  final TtsStatus status;
  final int currentIndex;
  final int total;
  final double speed;
  final String language;
  final String? errorMessage;

  /// Char offset of the word start within the current paragraph's display text.
  /// -1 when no word is currently highlighted.
  final int wordStart;

  /// Char offset of the word end (exclusive) within the current paragraph's
  /// display text. -1 when no word is currently highlighted.
  final int wordEnd;

  /// Currently active voice name. Empty string = system default.
  final String voiceName;

  const TtsState({
    required this.status,
    required this.currentIndex,
    required this.total,
    required this.speed,
    required this.language,
    this.errorMessage,
    this.wordStart = -1,
    this.wordEnd = -1,
    this.voiceName = '',
  });

  const TtsState.initial()
    : status = TtsStatus.idle,
      currentIndex = 0,
      total = 0,
      speed = 0.5,
      language = 'en-US',
      errorMessage = null,
      wordStart = -1,
      wordEnd = -1,
      voiceName = '';

  bool get isPlaying => status == TtsStatus.playing;
  bool get isPaused => status == TtsStatus.paused;
  bool get isActive =>
      status == TtsStatus.playing || status == TtsStatus.paused;

  TtsState copyWith({
    TtsStatus? status,
    int? currentIndex,
    int? total,
    double? speed,
    String? language,
    String? errorMessage,
    int? wordStart,
    int? wordEnd,
    String? voiceName,
  }) => TtsState(
    status: status ?? this.status,
    currentIndex: currentIndex ?? this.currentIndex,
    total: total ?? this.total,
    speed: speed ?? this.speed,
    language: language ?? this.language,
    errorMessage: errorMessage,
    wordStart: wordStart ?? this.wordStart,
    wordEnd: wordEnd ?? this.wordEnd,
    voiceName: voiceName ?? this.voiceName,
  );
}

// ─── Audio Handler (owns FlutterTts, drives notification) ────────────────────

class TtsAudioHandler extends BaseAudioHandler {
  final FlutterTts _tts = FlutterTts();

  List<String> _paragraphs = [];
  int _currentIndex = 0;

  /// Char offset within the current paragraph's display text where speaking
  /// started. Used to convert TTS progress offsets back to absolute positions.
  int _startOffset = 0;

  double _speed = 0.5;
  String _language = 'en-US';
  String _voiceName = '';
  String _voiceLocale = '';

  final _stateCtrl = StreamController<TtsState>.broadcast();
  TtsState _ttsState = const TtsState.initial();
  final _initCompleter = Completer<void>();

  TtsState get currentTtsState => _ttsState;
  Stream<TtsState> get ttsStateStream => _stateCtrl.stream;
  Future<void> get initialized => _initCompleter.future;

  TtsAudioHandler() {
    _init()
        .then((_) {
          if (!_initCompleter.isCompleted) _initCompleter.complete();
        })
        .catchError((e) {
          if (!_initCompleter.isCompleted) _initCompleter.complete();
        });
  }

  Future<void> _init() async {
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speed);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Word-level progress (Android 8+, iOS)
    _tts.setProgressHandler((String text, int start, int end, String word) {
      // start/end are relative to the spoken text (which may be trimmed).
      // Add _startOffset to convert to absolute position in the paragraph.
      _emit(
        _ttsState.copyWith(
          wordStart: _startOffset + start,
          wordEnd: _startOffset + end,
        ),
      );
    });

    _tts.setCompletionHandler(() {
      final next = _currentIndex + 1;
      if (next < _paragraphs.length) {
        _currentIndex = next;
        _startOffset = 0; // subsequent paragraphs always start at 0
        _emit(
          _ttsState.copyWith(currentIndex: next, wordStart: -1, wordEnd: -1),
        );
        _speakCurrent();
      } else {
        _currentIndex = 0;
        _startOffset = 0;
        _emit(
          _ttsState.copyWith(
            status: TtsStatus.idle,
            currentIndex: 0,
            wordStart: -1,
            wordEnd: -1,
          ),
        );
        _publishPlaybackState(AudioProcessingState.completed, false);
      }
    });

    _tts.setErrorHandler((msg) {
      _emit(
        _ttsState.copyWith(
          status: TtsStatus.error,
          errorMessage: msg?.toString(),
          wordStart: -1,
          wordEnd: -1,
        ),
      );
    });
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  void _emit(TtsState s) {
    _ttsState = s;
    _stateCtrl.add(s);
    _publishPlaybackState(
      s.isPlaying || s.isPaused
          ? AudioProcessingState.ready
          : AudioProcessingState.idle,
      s.isPlaying,
    );
  }

  void _publishPlaybackState(AudioProcessingState proc, bool playing) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
        ],
        systemActions: const {MediaAction.rewind, MediaAction.fastForward},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: proc,
        playing: playing,
        updatePosition: Duration(seconds: _ttsState.currentIndex),
        bufferedPosition: Duration(seconds: _ttsState.currentIndex),
        speed: _speed,
        updateTime: DateTime.now(),
      ),
    );
  }

  Future<void> _speakCurrent() async {
    if (_currentIndex >= _paragraphs.length) return;
    var text = _paragraphs[_currentIndex].replaceFirst(RegExp(r'^##\s*'), '');
    if (_startOffset > 0 && _startOffset < text.length) {
      text = text.substring(_startOffset);
    } else {
      _startOffset = 0;
    }
    await _tts.speak(text);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns voices available on the device filtered to [locale]'s language.
  Future<List<Map<String, String>>> getVoicesForLocale(String locale) async {
    final raw = await _tts.getVoices;
    if (raw == null) return [];
    final langCode = locale.split('-')[0].split('_')[0].toLowerCase();
    final result = <Map<String, String>>[];
    for (final v in raw as List) {
      final map = v as Map;
      final name = map['name'] as String? ?? '';
      final vLocale = map['locale'] as String? ?? '';
      if (name.isNotEmpty && vLocale.toLowerCase().startsWith(langCode)) {
        result.add({'name': name, 'locale': vLocale});
      }
    }
    return result;
  }

  Future<void> setVoice(String voiceName, String locale) async {
    _voiceName = voiceName;
    _voiceLocale = locale;
    if (voiceName.isNotEmpty) {
      await _tts.setVoice({'name': voiceName, 'locale': locale});
    }
    _emit(_ttsState.copyWith(voiceName: voiceName));
    if (_ttsState.isPlaying) {
      await _tts.stop();
      _startOffset = 0;
      await _speakCurrent();
    }
  }

  Future<void> loadAndPlay({
    required List<String> paragraphs,
    required int startIndex,
    int wordOffset = 0,
    String? language,
    String? articleTitle,
  }) async {
    await _tts.stop();
    _paragraphs = paragraphs;
    _currentIndex = startIndex.clamp(0, paragraphs.length - 1);
    _startOffset = wordOffset;

    if (language != null && language != _language) {
      _language = language;
      await _tts.setLanguage(language);
    }

    if (_voiceName.isNotEmpty) {
      await _tts.setVoice({
        'name': _voiceName,
        'locale': _voiceLocale.isNotEmpty ? _voiceLocale : _language,
      });
    }

    if (articleTitle != null) {
      mediaItem.add(
        MediaItem(
          id: startIndex.toString(),
          title: articleTitle,
          artist: 'WebReader',
          duration: Duration(seconds: paragraphs.length),
        ),
      );
    }

    _emit(
      _ttsState.copyWith(
        status: TtsStatus.playing,
        currentIndex: _currentIndex,
        total: paragraphs.length,
        language: _language,
        errorMessage: null,
        wordStart: -1,
        wordEnd: -1,
      ),
    );
    await _speakCurrent();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _tts.setSpeechRate(speed);
    _emit(_ttsState.copyWith(speed: speed));
    if (_ttsState.isPlaying) {
      await _tts.stop();
      _startOffset = 0; // restart from beginning of current paragraph
      await _speakCurrent();
    }
  }

  Future<void> setLanguage(String language) async {
    _language = language;
    await _tts.setLanguage(language);
    _emit(_ttsState.copyWith(language: language));
    if (_ttsState.isPlaying) {
      await _tts.stop();
      _startOffset = 0;
      await _speakCurrent();
    }
  }

  // ── BaseAudioHandler overrides (notification button handlers) ──────────────

  @override
  Future<void> play() async {
    if (_ttsState.isPaused) {
      _emit(_ttsState.copyWith(status: TtsStatus.playing));
      _startOffset = 0; // resume restarts current paragraph
      await _speakCurrent();
    }
  }

  @override
  Future<void> pause() async {
    if (_ttsState.isPlaying) {
      // Stop the engine so that resume (play) restarts from the beginning of
      // the current paragraph — keeping audio and word-highlight in sync.
      await _tts.stop();
      _startOffset = 0;
      _emit(
        _ttsState.copyWith(
          status: TtsStatus.paused,
          wordStart: -1,
          wordEnd: -1,
        ),
      );
    }
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _currentIndex = 0;
    _startOffset = 0;
    _emit(
      _ttsState.copyWith(
        status: TtsStatus.stopped,
        currentIndex: 0,
        wordStart: -1,
        wordEnd: -1,
      ),
    );
  }

  @override
  Future<void> skipToNext() async {
    if (_paragraphs.isEmpty) return;
    await _tts.stop();
    _currentIndex = (_currentIndex + 1).clamp(0, _paragraphs.length - 1);
    _startOffset = 0;
    _emit(
      _ttsState.copyWith(
        currentIndex: _currentIndex,
        status: TtsStatus.playing,
        wordStart: -1,
        wordEnd: -1,
      ),
    );
    await _speakCurrent();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_paragraphs.isEmpty) return;
    await _tts.stop();
    _currentIndex = (_currentIndex - 1).clamp(0, _paragraphs.length - 1);
    _startOffset = 0;
    _emit(
      _ttsState.copyWith(
        currentIndex: _currentIndex,
        status: TtsStatus.playing,
        wordStart: -1,
        wordEnd: -1,
      ),
    );
    await _speakCurrent();
  }

  @override
  Future<void> rewind() => _seekBySeconds(-10);

  @override
  Future<void> fastForward() => _seekBySeconds(10);

  Future<void> _seekBySeconds(int seconds) async {
    if (_paragraphs.isEmpty) return;
    // Approximate chars per second: ~12.5 at speed 1.0
    final charsDelta = (12.5 * _speed * seconds.abs()).round();
    await _tts.stop();
    if (seconds < 0) {
      final newOffset = _startOffset - charsDelta;
      if (newOffset > 0) {
        _startOffset = newOffset;
      } else if (_currentIndex > 0) {
        _currentIndex -= 1;
        _startOffset = 0;
      } else {
        _startOffset = 0;
      }
    } else {
      final text = _paragraphs[_currentIndex].replaceFirst(
        RegExp(r'^##\s*'),
        '',
      );
      final newOffset = _startOffset + charsDelta;
      if (newOffset < text.length) {
        _startOffset = newOffset;
      } else if (_currentIndex < _paragraphs.length - 1) {
        _currentIndex += 1;
        _startOffset = 0;
      }
    }
    _emit(
      _ttsState.copyWith(
        currentIndex: _currentIndex,
        status: TtsStatus.playing,
        wordStart: -1,
        wordEnd: -1,
      ),
    );
    await _speakCurrent();
  }
}

// ─── TtsNotifier ─────────────────────────────────────────────────────────────

class TtsNotifier extends StateNotifier<TtsState> {
  final TtsAudioHandler _handler;
  final SettingsRepository _settingsRepo;
  StreamSubscription<TtsState>? _sub;
  Timer? _wordTapTimer;

  TtsNotifier(this._handler, this._settingsRepo)
    : super(_handler.currentTtsState) {
    _sub = _handler.ttsStateStream.listen((s) {
      if (mounted) state = s;
    });
    _applyStoredVoice();
  }

  Future<void> _applyStoredVoice() async {
    await _handler.initialized;
    if (!mounted) return;
    try {
      final settings = await _settingsRepo.getSettings();
      if (mounted && settings.ttsVoice.isNotEmpty) {
        await _handler.setVoice(settings.ttsVoice, settings.ttsLanguage);
      }
    } catch (_) {}
  }

  Future<void> play(
    List<String> paragraphs, {
    int startIndex = 0,
    int wordOffset = 0,
    String? language,
    String? articleTitle,
  }) => _handler.loadAndPlay(
    paragraphs: paragraphs,
    startIndex: startIndex,
    wordOffset: wordOffset,
    language: language,
    articleTitle: articleTitle,
  );

  Future<void> pause() => _handler.pause();
  Future<void> resume() => _handler.play();
  Future<void> stop() => _handler.stop();
  Future<void> skipNext() => _handler.skipToNext();
  Future<void> skipPrevious() => _handler.skipToPrevious();
  Future<void> rewind() => _handler.rewind();
  Future<void> fastForward() => _handler.fastForward();
  Future<void> setSpeed(double speed) => _handler.setSpeed(speed);
  Future<void> setLanguage(String language) => _handler.setLanguage(language);
  Future<void> setVoice(String voiceName, String locale) =>
      _handler.setVoice(voiceName, locale);
  Future<List<Map<String, String>>> getVoicesForLocale(String locale) =>
      _handler.getVoicesForLocale(locale);

  /// Schedule TTS start from a tapped word, cancelling any previous schedule.
  /// Shows immediate visual feedback (paragraph highlight) before playback
  /// actually begins after [delay].
  void schedulePlayFromWord({
    required List<String> paragraphs,
    required int paragraphIndex,
    required int charOffset,
    String? language,
    String? articleTitle,
    Duration delay = const Duration(seconds: 2),
  }) {
    _wordTapTimer?.cancel();
    _wordTapTimer = Timer(delay, () {
      _handler.loadAndPlay(
        paragraphs: paragraphs,
        startIndex: paragraphIndex,
        wordOffset: charOffset,
        language: language,
        articleTitle: articleTitle,
      );
    });
  }

  void cancelScheduledPlay() {
    _wordTapTimer?.cancel();
    _wordTapTimer = null;
  }

  @override
  void dispose() {
    _wordTapTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
