import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:web_reader/core/theme/app_theme.dart';
import 'package:web_reader/data/database/app_database.dart';
import 'package:web_reader/domain/entities/settings.dart';
import 'package:web_reader/presentation/providers/providers.dart';
import 'package:web_reader/presentation/providers/tts_notifier.dart';
import 'package:web_reader/presentation/screens/home_screen.dart';
import 'package:web_reader/presentation/screens/reader_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.database;
  // AudioService.init() must be called after the first frame so Android has
  // had time to attach the Activity to the plugin host. We show a brief
  // loading screen, then swap in the full app once the handler is ready.
  runApp(const _AppInitializer());
}

/// Shows a loading screen until AudioService is initialised, then mounts the
/// full ProviderScope + app tree with the handler override in place.
class _AppInitializer extends StatefulWidget {
  const _AppInitializer();

  @override
  State<_AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<_AppInitializer> {
  TtsAudioHandler? _handler;

  @override
  void initState() {
    super.initState();
    // addPostFrameCallback fires after the first frame, which guarantees the
    // Activity is attached and AudioServicePlugin can find a FlutterEngine.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAudioService());
  }

  Future<void> _initAudioService() async {
    TtsAudioHandler handler;
    try {
      handler = await AudioService.init(
        builder: () => TtsAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.webreader.web_reader.tts',
          androidNotificationChannelName: 'WebReader TTS',
          androidNotificationOngoing: false,
          rewindInterval: Duration(seconds: 10),
          fastForwardInterval: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      // Notification controls won't work, but TTS still functions normally.
      debugPrint('[WebReader] AudioService.init failed: $e');
      handler = TtsAudioHandler();
    }
    if (mounted) setState(() => _handler = handler);
  }

  @override
  Widget build(BuildContext context) {
    final handler = _handler;
    if (handler == null) {
      // Shown for < 1 second on first launch while AudioService initialises.
      return MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return ProviderScope(
      overrides: [ttsAudioHandlerProvider.overrideWithValue(handler)],
      child: const _ShareIntentWrapper(),
    );
  }
}

ThemeMode _themeModeFor(ThemePreference preference) {
  return switch (preference) {
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
    ThemePreference.system => ThemeMode.system,
  };
}

class _ShareIntentWrapper extends ConsumerStatefulWidget {
  const _ShareIntentWrapper();

  @override
  ConsumerState<_ShareIntentWrapper> createState() =>
      _ShareIntentWrapperState();
}

class _ShareIntentWrapperState extends ConsumerState<_ShareIntentWrapper> {
  StreamSubscription? _intentSub;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedMedia,
      onError: (_) {},
    );
    // Delay initial media handling until after the first frame so the
    // navigator is mounted and _navigatorKey.currentState is non-null.
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleSharedMedia(files),
      );
    });
  }

  /// Extracts a URL from a shared media file, checking both [path] and
  /// [message] fields since different apps populate different fields.
  String? _urlFromFile(SharedMediaFile file) {
    for (final candidate in [file.path, file.message ?? '']) {
      final text = candidate.trim();
      if (text.isEmpty) continue;
      final uri = Uri.tryParse(text);
      if (uri != null && uri.hasScheme && uri.hasAuthority) return text;
    }
    return null;
  }

  void _handleSharedMedia(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    for (final file in files) {
      final url = _urlFromFile(file);
      if (url != null) {
        _openUrl(url);
        ReceiveSharingIntent.instance.reset();
        break;
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final repo = ref.read(articleRepositoryProvider);
    try {
      final article = await repo.fetchArticle(url);
      await ref.read(settingsRepositoryProvider).setLastArticleUrl(url);
      ref.read(recentArticlesProvider.notifier).load();
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(article: article, autoPlay: true),
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final themeMode =
        settingsAsync.valueOrNull == null
            ? ThemeMode.system
            : _themeModeFor(settingsAsync.valueOrNull!.themePreference);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'WebReader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}
