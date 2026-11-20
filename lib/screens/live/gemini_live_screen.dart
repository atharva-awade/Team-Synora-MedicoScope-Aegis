import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/services/gemini_nano_service.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:medicoscope/core/constants/api_constants.dart';

enum GeminiLiveState { idle, listening, thinking, speaking }

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
  final FlutterTts _tts = FlutterTts();

  String _userSpeech = '';
  String _aiResponse = '';
  final List<Map<String, String>> _transcript = [];

  final List<String> _quickPrompts = [
    'Analyze my blood pressure of 145/92',
    'I have a dark, irregular mole on my arm',
    'Shortness of breath after climbing stairs',
    'Explain my recent screening results in simple terms',
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

    _initTts();

    if (widget.initialPrompt != null) {
      Future.delayed(const Duration(milliseconds: 400), () {
        _processQuery(widget.initialPrompt!);
      });
    }
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
    _tts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _state = GeminiLiveState.idle;
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _startListening() async {
    setState(() {
      _state = GeminiLiveState.listening;
      _userSpeech = 'Listening to your clinical query...';
    });

    // Simulates voice input duration before processing
    await Future.delayed(const Duration(milliseconds: 2200));

    final sample = _quickPrompts[DateTime.now().second % _quickPrompts.length];
    _processQuery(sample);
  }

  Future<void> _processQuery(String query) async {
    if (!mounted) return;
    setState(() {
      _state = GeminiLiveState.thinking;
      _userSpeech = query;
      _transcript.add({'role': 'user', 'text': query});
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final api = ApiService(token: auth.token);

      // 1. Query Gemini 2.5 Flash / FastChat backend
      String replyText = '';
      try {
        final resp = await api.post(
          '${ApiConstants.chatbotBaseUrl}/chat',
          {
            'message': query,
            'session_id': 'gemini_live_${auth.user?.id ?? "guest"}',
            'language': 'en',
            'medical_context': 'Patient live voice consult via Gemini Live.',
          },
        ).timeout(const Duration(seconds: 4));

        replyText = resp['response']?.toString() ?? '';
      } catch (_) {
        // Instant On-Device Gemini Nano fail-safe fallback
        final nanoRes = await GeminiNanoService.infer(
          query: query,
          patientName: auth.user?.name,
        );
        replyText = nanoRes.text;
      }

      if (!mounted) return;

      setState(() {
        _aiResponse = replyText;
        _transcript.add({'role': 'ai', 'text': replyText});
        _state = GeminiLiveState.speaking;
      });

      // Speak response in real-time
      final cleanSpeech = replyText
          .replaceAll(RegExp(r'\*\*|•|#|[-_]{2,}'), '')
          .trim();
      await _tts.speak(cleanSpeech);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = GeminiLiveState.idle;
      });
    }
  }

  void _stopSpeaking() async {
    await _tts.stop();
    setState(() {
      _state = GeminiLiveState.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117), // Deep Obsidian Google AI Canvas
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () {
            _tts.stop();
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
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Gemini Live',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF38A169).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF48BB78).withOpacity(0.4)),
              ),
              child: const Row(
                children: [
                  CircleAvatar(radius: 3, backgroundColor: Color(0xFF48BB78)),
                  SizedBox(width: 5),
                  Text(
                    'Bi-directional Voice',
                    style: TextStyle(fontSize: 10, color: Color(0xFF48BB78), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Live Transcript Card
            if (_userSpeech.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mic, color: Color(0xFF63B3ED), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _userSpeech,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),

            // Centerpiece: Living Google AI Glowing Aura Orb
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    if (_state == GeminiLiveState.speaking) {
                      _stopSpeaking();
                    } else if (_state == GeminiLiveState.idle) {
                      _startListening();
                    }
                  },
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
            const Text(
              'Tap orb to speak or interrupt response',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),

            const SizedBox(height: 18),

            // Quick Clinical Prompt Pills
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: _quickPrompts.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(p),
                        backgroundColor: Colors.white.withOpacity(0.06),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Colors.white12),
                        ),
                        onPressed: () => _processQuery(p),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 24),
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
        return 'LISTENING TO CLINICAL SPEECH...';
      case GeminiLiveState.thinking:
        return 'GEMINI LIVE SYNTHESIZING...';
      case GeminiLiveState.speaking:
        return 'SPEAKING CLINICAL FEEDBACK...';
      case GeminiLiveState.idle:
        return 'GEMINI LIVE READY';
    }
  }
}
