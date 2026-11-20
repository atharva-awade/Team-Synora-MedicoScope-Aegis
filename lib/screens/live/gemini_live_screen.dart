import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/services/gemini_nano_service.dart';
import 'package:medicoscope/services/gemini_tts_service.dart';
import 'package:medicoscope/core/constants/api_constants.dart';

enum GeminiLiveState {
  idle,
  listening,
  thinking,
  speaking,
}

/// Gemini Live Telehealth Screen - Real-Time Bidirectional Voice Consult.
///
/// Features:
/// - True hands-free bidirectional voice loop (Auto-listen on TTS completion)
/// - Instant interruption / barge-in (Tap orb while AI speaks to ask follow-up)
/// - Google Cloud Run Gemini 1.5 Pro / Flash engine via /chat
/// - Fail-safe Google Gemini Nano on-device AICore fallback (<50ms)
/// - Multilingual speech recognition and Google Neural voice synthesis
class GeminiLiveScreen extends StatefulWidget {
  final String? initialPrompt;

  const GeminiLiveScreen({super.key, this.initialPrompt});

  @override
  State<GeminiLiveScreen> createState() => _GeminiLiveScreenState();
}

class _GeminiLiveScreenState extends State<GeminiLiveScreen>
    with TickerProviderStateMixin {
  GeminiLiveState _state = GeminiLiveState.idle;
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isProcessing = false;
  bool _continuousMode = true; // Auto-listen after AI responds for fluent bidirectional chat
  Timer? _silenceTimer;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _transcriptScrollController = ScrollController();

  String _userSpeech = '';
  String _aiResponse = '';
  final List<Map<String, String>> _transcript = [];
  String _selectedLanguage = 'en';

  static const Map<String, String> _languages = {
    'en': 'English',
    'hi': 'Hindi (हिंदी)',
    'mr': 'Marathi (मराठी)',
    'ta': 'Tamil (தமிழ்)',
    'te': 'Telugu (తెలుగు)',
    'kn': 'Kannada (ಕನ್ನಡ)',
    'bn': 'Bengali (বাংলা)',
  };

  static const Map<String, String> _sttLocales = {
    'en': 'en_IN',
    'hi': 'hi_IN',
    'mr': 'mr_IN',
    'ta': 'ta_IN',
    'te': 'te_IN',
    'kn': 'kn_IN',
    'bn': 'bn_IN',
  };

  final List<String> _quickPrompts = [
    'Analyze my blood pressure of 145/92',
    'I have a persistent dry cough and slight fever',
    'What do the ABCDE criteria mean for skin moles?',
    'Guide me through a calming 432Hz breathing exercise',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    _speech = stt.SpeechToText();
    GeminiTTSService.init();
    GeminiTTSService.stateNotifier.addListener(_onTTSStateChange);
    _initSpeechRecognizer();

    if (widget.initialPrompt != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _processQuery(widget.initialPrompt!);
      });
    }
  }

  void _onTTSStateChange() {
    if (!mounted) return;
    if (GeminiTTSService.state == TTSState.idle && _state == GeminiLiveState.speaking) {
      if (_continuousMode) {
        // Fluent bidirectional loop: wait a gentle breather, then listen for user follow-up
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && _state == GeminiLiveState.speaking) {
            _startListening();
          }
        });
      } else {
        setState(() {
          _state = GeminiLiveState.idle;
        });
      }
    }
  }

  Future<void> _initSpeechRecognizer() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (val) {
          if (mounted && _state == GeminiLiveState.listening) {
            setState(() {
              _state = GeminiLiveState.idle;
            });
          }
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted &&
                _state == GeminiLiveState.listening &&
                _userSpeech.trim().isNotEmpty &&
                !_isProcessing) {
              _processQuery(_userSpeech);
            }
          }
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _pulseController.dispose();
    _rotationController.dispose();
    GeminiTTSService.stateNotifier.removeListener(_onTTSStateChange);
    GeminiTTSService.stop();
    _speech.stop();
    _textController.dispose();
    _transcriptScrollController.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (!mounted) return;
    _silenceTimer?.cancel();
    await GeminiTTSService.stop();

    setState(() {
      _state = GeminiLiveState.listening;
      _userSpeech = '';
    });

    if (_speechAvailable) {
      final locId = _sttLocales[_selectedLanguage] ?? 'en_IN';
      try {
        await _speech.listen(
          onResult: (result) {
            if (!mounted || _state != GeminiLiveState.listening) return;
            setState(() {
              _userSpeech = result.recognizedWords;
            });
            _silenceTimer?.cancel();
            if (result.recognizedWords.trim().isNotEmpty) {
              if (result.finalResult && !_isProcessing) {
                _processQuery(result.recognizedWords);
              } else {
                // Auto-submit after 1.6s of silence for natural conversational turn-taking
                _silenceTimer = Timer(const Duration(milliseconds: 1600), () {
                  if (mounted &&
                      _state == GeminiLiveState.listening &&
                      _userSpeech.trim().isNotEmpty &&
                      !_isProcessing) {
                    _speech.stop();
                    _processQuery(_userSpeech);
                  }
                });
              }
            }
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
          localeId: locId,
        );
      } catch (_) {
        setState(() => _state = GeminiLiveState.idle);
      }
    } else {
      setState(() {
        _userSpeech = 'Microphone active. Tap any clinical prompt or type below.';
      });
    }
  }

  Future<void> _toggleListening() async {
    // If speaking: barge-in / interrupt immediately and start listening to user
    if (_state == GeminiLiveState.speaking) {
      await _startListening();
      return;
    }

    // If listening: stop immediately and process whatever user spoke
    if (_state == GeminiLiveState.listening) {
      _silenceTimer?.cancel();
      await _speech.stop();
      if (_userSpeech.trim().isNotEmpty && !_isProcessing) {
        _processQuery(_userSpeech);
      } else {
        setState(() => _state = GeminiLiveState.idle);
      }
      return;
    }

    // If idle or thinking: start listening
    await _startListening();
  }

  Future<void> _processQuery(String query) async {
    if (!mounted || query.trim().isEmpty || _isProcessing) return;

    _isProcessing = true;
    _silenceTimer?.cancel();
    if (_speech.isListening) {
      await _speech.stop();
    }

    final trimmed = query.trim();

    setState(() {
      _state = GeminiLiveState.thinking;
      _userSpeech = trimmed;
      _transcript.add({'role': 'user', 'text': trimmed});
    });

    _scrollTranscriptToBottom();

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      String replyText = '';

      try {
        // 1. Direct call to Google Cloud Run Gemini Telehealth Engine
        final url = Uri.parse('${ApiConstants.chatbotBaseUrl}/chat');
        final headers = {
          'Content-Type': 'application/json',
          if (auth.token != null) 'Authorization': 'Bearer ${auth.token}',
        };
        final body = jsonEncode({
          'message': trimmed,
          'session_id': 'gemini_live_${auth.user?.id ?? "guest"}',
          'language': _selectedLanguage,
          'medical_context': 'Patient live bi-directional telehealth consultation with Google Gemini Live.',
        });

        final resp = await http
            .post(url, headers: headers, body: body)
            .timeout(const Duration(seconds: 9));

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final data = jsonDecode(resp.body);
          replyText = data['response']?.toString() ?? '';
        }
      } catch (_) {
        replyText = '';
      }

      // 2. Fail-Safe: On-Device Google Gemini Nano Edge Engine (<50ms)
      if (replyText.trim().isEmpty) {
        final nanoRes = await GeminiNanoService.infer(
          query: trimmed,
          patientName: auth.user?.name,
        );
        replyText = nanoRes.text;
      }

      if (!mounted) return;

      setState(() {
        _aiResponse = replyText;
        _transcript.add({'role': 'ai', 'text': replyText});
        _state = GeminiLiveState.speaking;
        _isProcessing = false;
      });

      _scrollTranscriptToBottom();

      // Clean markdown asterisks and bullets for smooth Google Neural speech playback
      final cleanSpeech = replyText
          .replaceAll(RegExp(r'\*\*|•|#|[-_]{2,}'), '')
          .replaceAll(RegExp(r'\n+'), ' ')
          .trim();

      // Speak using high-fidelity Google Neural voice synthesis in chosen language
      await GeminiTTSService.speak(
        text: cleanSpeech,
        languageCode: _selectedLanguage,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = GeminiLiveState.idle;
        _isProcessing = false;
      });
    }
  }

  void _stopSpeaking() async {
    _silenceTimer?.cancel();
    await GeminiTTSService.stop();
    if (mounted) {
      setState(() {
        _state = GeminiLiveState.idle;
        _isProcessing = false;
      });
    }
  }

  void _scrollTranscriptToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_transcriptScrollController.hasClients) {
        _transcriptScrollController.animateTo(
          _transcriptScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117), // Google AI Obsidian Canvas
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () {
            GeminiTTSService.stop();
            _speech.stop();
            Navigator.of(context).pop();
          },
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Gemini Live',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Continuous auto-listen indicator
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  _continuousMode = !_continuousMode;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: _continuousMode
                      ? const Color(0xFF48BB78).withOpacity(0.18)
                      : Colors.white12,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _continuousMode
                        ? const Color(0xFF48BB78).withOpacity(0.5)
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: _continuousMode
                          ? const Color(0xFF48BB78)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _continuousMode ? 'Auto-Listen' : 'Push-to-Talk',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: _continuousMode
                            ? const Color(0xFF48BB78)
                            : Colors.white60,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Select Language',
            initialValue: _selectedLanguage,
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.white12),
            ),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2230),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language, size: 14, color: Color(0xFFD6BCFA)),
                  const SizedBox(width: 4),
                  Text(
                    _selectedLanguage.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFD6BCFA),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFFD6BCFA)),
                ],
              ),
            ),
            onSelected: (val) {
              setState(() {
                _selectedLanguage = val;
              });
            },
            itemBuilder: (ctx) {
              return _languages.entries.map((e) {
                return PopupMenuItem<String>(
                  value: e.key,
                  child: Row(
                    children: [
                      Text(
                        e.value,
                        style: TextStyle(
                          color: e.key == _selectedLanguage
                              ? const Color(0xFF7C4DFF)
                              : Colors.white,
                          fontWeight: e.key == _selectedLanguage
                              ? FontWeight.w800
                              : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      if (e.key == _selectedLanguage) ...[
                        const Spacer(),
                        const Icon(Icons.check, color: Color(0xFF7C4DFF), size: 16),
                      ],
                    ],
                  ),
                );
              }).toList();
            },
          ),
          if (_transcript.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 20),
              tooltip: 'Reset Conversation',
              onPressed: () {
                _stopSpeaking();
                setState(() {
                  _transcript.clear();
                  _userSpeech = '';
                  _aiResponse = '';
                  _state = GeminiLiveState.idle;
                });
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Live Dialogue / Transcript Area
            if (_transcript.isNotEmpty)
              Container(
                height: 140,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListView.builder(
                  controller: _transcriptScrollController,
                  itemCount: _transcript.length,
                  itemBuilder: (context, index) {
                    final item = _transcript[index];
                    final isUser = item['role'] == 'user';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isUser ? Icons.person : Icons.auto_awesome,
                            size: 14,
                            color: isUser ? const Color(0xFF63B3ED) : const Color(0xFF81E6D9),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item['text'] ?? '',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isUser ? Colors.white : const Color(0xFFE2E8F0),
                                fontWeight: isUser ? FontWeight.w600 : FontWeight.w400,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ).animate().fadeIn(duration: 250.ms),

            // Live recognized words banner
            if (_state == GeminiLiveState.listening && _userSpeech.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF4285F4).withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mic, color: Color(0xFF4285F4), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _userSpeech,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Centerpiece: Living Google AI Pulsing Aura Orb
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: _toggleListening,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Rotating ambient halo
                      RotationTransition(
                        turns: _rotationController,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, _) {
                            final scale = 1.0 + (_pulseController.value * 0.18);
                            return Container(
                              width: 220 * scale,
                              height: 220 * scale,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    _orbPrimaryColor().withOpacity(0.4),
                                    _orbSecondaryColor().withOpacity(0.18),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Core pulsing orb
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, _) {
                          final scale = 1.0 + (_pulseController.value * 0.08);
                          return Container(
                            width: 140 * scale,
                            height: 140 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _orbPrimaryColor(),
                                  _orbSecondaryColor(),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _orbPrimaryColor().withOpacity(0.6),
                                  blurRadius: 28,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                _orbIcon(),
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // State Headline
            Text(
              _stateHeadline(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _orbPrimaryColor(),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _state == GeminiLiveState.speaking
                  ? 'Tap orb to interrupt & ask follow-up'
                  : _state == GeminiLiveState.listening
                      ? 'Listening... tap orb or stop speaking to send'
                      : 'Tap orb to speak with Google Gemini Live',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),

            const SizedBox(height: 16),

            // Quick Clinical Prompt Pills (Dark Glassmorphic Styling - No blank white boxes)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: _quickPrompts.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _processQuery(p),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C2230),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF7C4DFF).withOpacity(0.4),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bolt, size: 14, color: Color(0xFFFBBC05)),
                                const SizedBox(width: 6),
                                Text(
                                  p,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Bottom Text & Voice Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Type clinical query or tap orb to speak...',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            _processQuery(val);
                            _textController.clear();
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _state == GeminiLiveState.listening ? Icons.stop_circle : Icons.mic,
                        color: _orbPrimaryColor(),
                      ),
                      onPressed: _toggleListening,
                    ),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF4285F4)),
                      onPressed: () {
                        if (_textController.text.trim().isNotEmpty) {
                          _processQuery(_textController.text);
                          _textController.clear();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _orbPrimaryColor() {
    switch (_state) {
      case GeminiLiveState.listening:
        return const Color(0xFF4285F4); // Google Blue
      case GeminiLiveState.thinking:
        return const Color(0xFFFBBC05); // Google Amber
      case GeminiLiveState.speaking:
        return const Color(0xFF34A853); // Google Emerald
      case GeminiLiveState.idle:
        return const Color(0xFF7C4DFF); // Google Violet
    }
  }

  Color _orbSecondaryColor() {
    switch (_state) {
      case GeminiLiveState.listening:
        return const Color(0xFF00C9FF);
      case GeminiLiveState.thinking:
        return const Color(0xFFFF6B6B);
      case GeminiLiveState.speaking:
        return const Color(0xFF00F2FE);
      case GeminiLiveState.idle:
        return const Color(0xFF92FE9D);
    }
  }

  IconData _orbIcon() {
    switch (_state) {
      case GeminiLiveState.listening:
        return Icons.mic;
      case GeminiLiveState.thinking:
        return Icons.psychology;
      case GeminiLiveState.speaking:
        return Icons.volume_up_rounded;
      case GeminiLiveState.idle:
        return Icons.auto_awesome;
    }
  }

  String _stateHeadline() {
    switch (_state) {
      case GeminiLiveState.listening:
        return 'LISTENING TO YOUR SPEECH...';
      case GeminiLiveState.thinking:
        return 'GEMINI LIVE SYNTHESIZING...';
      case GeminiLiveState.speaking:
        return 'SPEAKING CLINICAL FEEDBACK...';
      case GeminiLiveState.idle:
        return 'GEMINI LIVE READY';
    }
  }
}
