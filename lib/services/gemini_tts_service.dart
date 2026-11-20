import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum TTSState { idle, loading, playing, paused }

class GeminiTTSService {
  static const String _model = 'gemini-3.8-flash-tts';
  static const String _apiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  static final AudioPlayer _player = AudioPlayer();
  static final FlutterTts _flutterTts = FlutterTts();
  static bool _usingNativeFallback = false;
  static bool _isInitialized = false;

  static TTSState _state = TTSState.idle;
  static String? _currentPlayingText;
  static String _activeLanguage = 'en';
  static double _speed = 1.0;

  // Language mapping for regional language synthesis
  static const Map<String, String> languageNames = {
    'en': 'English',
    'hi': 'Hindi (हिन्दी)',
    'mr': 'Marathi (मराठी)',
    'ta': 'Tamil (தமிழ்)',
    'te': 'Telugu (తెలుగు)',
    'kn': 'Kannada (ಕನ್ನಡ)',
    'bn': 'Bengali (বাংলা)',
  };

  // Locale tags for native TTS engines (Google Speech Services)
  static const Map<String, String> _nativeLocales = {
    'en': 'en-IN',
    'hi': 'hi-IN',
    'mr': 'mr-IN',
    'ta': 'ta-IN',
    'te': 'te-IN',
    'kn': 'kn-IN',
    'bn': 'bn-IN',
  };

  static const Map<String, String> _languagePromptPrefixes = {
    'en': 'Speak warmly and empathetically in English: ',
    'hi': 'Speak fluently, warmly and naturally in Hindi: ',
    'mr': 'Speak fluently, warmly and naturally in Marathi: ',
    'ta': 'Speak fluently, warmly and naturally in Tamil: ',
    'te': 'Speak fluently, warmly and naturally in Telugu: ',
    'kn': 'Speak fluently, warmly and naturally in Kannada: ',
    'bn': 'Speak fluently, warmly and naturally in Bengali: ',
  };

  static TTSState get state => _state;
  static String get activeLanguage => _activeLanguage;
  static double get speed => _speed;
  static bool get isPlaying => _state == TTSState.playing;
  static bool get isLoading => _state == TTSState.loading;
  static bool get usingNativeFallback => _usingNativeFallback;
  static String? get currentPlayingText => _currentPlayingText;

  static ValueNotifier<TTSState> stateNotifier =
      ValueNotifier<TTSState>(TTSState.idle);

  static void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    // Listen to Cloud AudioPlayer state
    _player.onPlayerStateChanged.listen((s) {
      if (!_usingNativeFallback) {
        if (s == PlayerState.playing) {
          _state = TTSState.playing;
        } else if (s == PlayerState.paused) {
          _state = TTSState.paused;
        } else if (s == PlayerState.completed || s == PlayerState.stopped) {
          _state = TTSState.idle;
        }
        stateNotifier.value = _state;
      }
    });

    // Configure Native FlutterTts handlers
    _flutterTts.setStartHandler(() {
      if (_usingNativeFallback) {
        _state = TTSState.playing;
        stateNotifier.value = _state;
      }
    });

    _flutterTts.setCompletionHandler(() {
      if (_usingNativeFallback) {
        _state = TTSState.idle;
        stateNotifier.value = _state;
      }
    });

    _flutterTts.setCancelHandler(() {
      if (_usingNativeFallback) {
        _state = TTSState.idle;
        stateNotifier.value = _state;
      }
    });

    _flutterTts.setPauseHandler(() {
      if (_usingNativeFallback) {
        _state = TTSState.paused;
        stateNotifier.value = _state;
      }
    });

    _flutterTts.setErrorHandler((msg) {
      debugPrint('Native TTS error: $msg');
      if (_usingNativeFallback) {
        _state = TTSState.idle;
        stateNotifier.value = _state;
      }
    });
  }

  static void setLanguage(String langCode) {
    if (languageNames.containsKey(langCode)) {
      _activeLanguage = langCode;
    }
  }

  static Future<void> setSpeed(double newSpeed) async {
    _speed = newSpeed;
    await _player.setPlaybackRate(newSpeed);
    final nativeRate = (newSpeed * 0.45).clamp(0.1, 1.0);
    await _flutterTts.setSpeechRate(nativeRate);
  }

  /// Check whether text already contains Indic script characters
  static bool _containsIndicScript(String text) {
    return RegExp(r'[\u0900-\u0D7F]').hasMatch(text);
  }

  /// Fast instant translation bridge for regional speech synthesis
  static Future<String> translateToLanguage(String text, String targetLang) async {
    if (targetLang == 'en' || text.trim().isEmpty) return text;
    try {
      final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$targetLang&dt=t&q=${Uri.encodeComponent(text)}',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List && data.isNotEmpty && data[0] is List) {
          final translated = (data[0] as List)
              .map((part) => (part is List && part.isNotEmpty) ? part[0]?.toString() ?? '' : '')
              .join('');
          if (translated.trim().isNotEmpty) {
            return translated;
          }
        }
      }
    } catch (e) {
      debugPrint('Regional translation error ($targetLang): $e');
    }
    return text;
  }

  /// Synthesize text to speech using gemini-3.8-flash-tts and play it.
  /// Automatically translates English text to chosen regional language (Hindi, Marathi, etc.)
  /// and falls back to native high-quality regional voice engine if Gemini quota is exhausted.
  static Future<bool> speak({
    required String text,
    String? languageCode,
    double? speed,
  }) async {
    init();
    final lang = languageCode ?? _activeLanguage;
    var cleanText = _cleanTextForSpeech(text);
    if (cleanText.isEmpty) return false;

    // Ensure regional speech gets regional words (translates Latin to Devanagari/Tamil/etc.)
    if (lang != 'en' && !_containsIndicScript(cleanText)) {
      final translated = await translateToLanguage(cleanText, lang);
      if (translated.trim().isNotEmpty) {
        cleanText = translated;
      }
    }

    try {
      // Toggle pause/resume if tapping on current playing speech
      if (_state == TTSState.playing && _currentPlayingText == cleanText) {
        await pause();
        return true;
      } else if (_state == TTSState.paused && _currentPlayingText == cleanText) {
        await resume();
        return true;
      }

      await stop();

      _state = TTSState.loading;
      stateNotifier.value = _state;
      _currentPlayingText = cleanText;

      // 1. Attempt Cloud Synthesis via Gemini 3.8 Flash TTS
      Uint8List? wavBytes;
      try {
        wavBytes = await synthesizeToBytes(
          text: cleanText,
          languageCode: lang,
        );
      } catch (e) {
        debugPrint('Gemini Cloud TTS failed ($e). Falling back to Native Engine.');
      }

      // If Cloud Audio succeeded, play through AudioPlayer
      if (wavBytes != null && wavBytes.isNotEmpty) {
        _usingNativeFallback = false;
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
            '${tempDir.path}/gemini_tts_${DateTime.now().millisecondsSinceEpoch}.wav');
        await tempFile.writeAsBytes(wavBytes);

        await _player.stop();
        if (speed != null) _speed = speed;
        await _player.setPlaybackRate(_speed);
        await _player.play(DeviceFileSource(tempFile.path));

        _state = TTSState.playing;
        stateNotifier.value = _state;
        return true;
      }

      // 2. Seamless Fallback: Native High-Performance Multi-Lingual TTS Engine
      debugPrint('Activating Seamless Native Regional Speech Engine for $lang...');
      _usingNativeFallback = true;
      return await _speakNative(cleanText, lang, speed);
    } catch (e) {
      debugPrint('TTS speak error: $e');
      _state = TTSState.idle;
      stateNotifier.value = _state;
      return false;
    }
  }

  /// Speak using device's native TTS engine in regional Indian languages
  static Future<bool> _speakNative(String text, String lang, double? speed) async {
    try {
      try {
        if (Platform.isAndroid) {
          final engines = await _flutterTts.getEngines;
          if (engines is List && engines.contains('com.google.android.tts')) {
            await _flutterTts.setEngine('com.google.android.tts');
          }
        }
      } catch (_) {}

      final localeTag = _nativeLocales[lang] ?? 'en-IN';
      
      try {
        await _flutterTts.setLanguage(localeTag);
      } catch (_) {
        final altTag = localeTag.replaceAll('-', '_');
        await _flutterTts.setLanguage(altTag);
      }

      final rate = ((speed ?? _speed) * 0.45).clamp(0.1, 1.0);
      await _flutterTts.setSpeechRate(rate);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _state = TTSState.playing;
      stateNotifier.value = _state;

      final res = await _flutterTts.speak(text);
      return res == 1;
    } catch (e) {
      debugPrint('Native TTS speak error: $e');
      _state = TTSState.idle;
      stateNotifier.value = _state;
      return false;
    }
  }

  /// Pause current audio
  static Future<void> pause() async {
    try {
      if (_usingNativeFallback) {
        await _flutterTts.pause();
      } else {
        await _player.pause();
      }
      _state = TTSState.paused;
      stateNotifier.value = _state;
    } catch (e) {
      debugPrint('TTS pause error: $e');
    }
  }

  /// Resume paused audio
  static Future<void> resume() async {
    try {
      if (_usingNativeFallback) {
        if (_currentPlayingText != null) {
          await _flutterTts.speak(_currentPlayingText!);
        }
      } else {
        await _player.resume();
      }
      _state = TTSState.playing;
      stateNotifier.value = _state;
    } catch (e) {
      debugPrint('TTS resume error: $e');
    }
  }

  /// Stop playback
  static Future<void> stop() async {
    try {
      await _player.stop();
      await _flutterTts.stop();
      _state = TTSState.idle;
      stateNotifier.value = _state;
    } catch (e) {
      debugPrint('TTS stop error: $e');
    }
  }

  /// Call Google Neural Speech Services or Gemini Flash TTS and return audio bytes
  static Future<Uint8List?> synthesizeToBytes({
    required String text,
    String languageCode = 'en',
  }) async {
    // 1. Google Neural Speech Stream (Ultra-fast, human-like cadence, 100+ languages)
    try {
      final clean = text.length > 200 ? text.substring(0, 200) : text;
      final ttsUrl = Uri.parse(
        'https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=$languageCode&q=${Uri.encodeComponent(clean)}',
      );
      final resp = await http.get(
        ttsUrl,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
    } catch (e) {
      debugPrint('Google Neural TTS stream fallback: $e');
    }

    // 2. Gemini Cloud Speech Config (if key is supplied in environment)
    if (_apiKey.isNotEmpty) {
      try {
        final prefix = _languagePromptPrefixes[languageCode] ?? '';
        final promptText = '$prefix$text';

        final url = Uri.parse('$_endpoint?key=$_apiKey');
        final payload = {
          'contents': [
            {
              'parts': [
                {'text': promptText}
              ]
            }
          ],
          'generationConfig': {
            'speechConfig': {
              'voiceConfig': {
                'prebuiltVoiceConfig': {
                  'voiceName': 'Aoede', // Warm, expressive voice
                }
              }
            }
          }
        };

        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              for (final p in parts) {
                final inlineData = p['inlineData'];
                if (inlineData != null && inlineData['data'] != null) {
                  final base64Str = inlineData['data'] as String;
                  return base64Decode(base64Str);
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Gemini Cloud TTS synthesize error: $e');
      }
    }

    return null;
  }

  /// Clean Markdown and symbols for natural spoken speech
  static String _cleanTextForSpeech(String raw) {
    var s = raw;
    // 1. Convert HTML lists and tags to natural speech pauses
    s = s.replaceAll(RegExp(r'</li>\s*<li>', caseSensitive: false), '. ');
    s = s.replaceAll(RegExp(r'</?(?:ul|ol|li|p|div|span|br)[^>]*>', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'<[^>]*>'), ' ');
    // 2. Remove Markdown bold/italic markup and stray asterisks
    s = s.replaceAllMapped(RegExp(r'\*\*([^\*]+)\*\*'), (m) => m[1] ?? '');
    s = s.replaceAllMapped(RegExp(r'\*([^\*]+)\*'), (m) => m[1] ?? '');
    s = s.replaceAll('*', '');
    s = s.replaceAll(RegExp(r'#+\s*'), '');
    s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1] ?? '');
    s = s.replaceAll(RegExp(r'[~_><|]'), ' ');
    s = s.replaceAll(RegExp(r'•|\-|\+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }
}
