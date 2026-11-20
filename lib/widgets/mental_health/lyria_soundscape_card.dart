import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/services/lyria_soundscape_service.dart';

class LyriaSoundscapeCard extends StatefulWidget {
  final double? voiceMarkerScore;
  const LyriaSoundscapeCard({super.key, this.voiceMarkerScore});

  @override
  State<LyriaSoundscapeCard> createState() => _LyriaSoundscapeCardState();
}

class _LyriaSoundscapeCardState extends State<LyriaSoundscapeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  LyriaPreset _selectedPreset = LyriaSoundscapeService.presets[0];
  bool _isPlaying = false;
  bool _isExpanded = true;
  double _volume = LyriaSoundscapeService.volume;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    if (widget.voiceMarkerScore != null) {
      _selectedPreset =
          LyriaSoundscapeService.recommendForTension(widget.voiceMarkerScore);
    }
    _isPlaying = LyriaSoundscapeService.isPlaying;
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    await LyriaSoundscapeService.playPreset(_selectedPreset);
    if (mounted) {
      setState(() {
        _isPlaying = LyriaSoundscapeService.isPlaying;
      });
    }
  }

  void _selectPreset(LyriaPreset preset) async {
    setState(() {
      _selectedPreset = preset;
    });
    if (_isPlaying) {
      await LyriaSoundscapeService.playPreset(preset);
      if (mounted) {
        setState(() {
          _isPlaying = LyriaSoundscapeService.isPlaying;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26), // Dark obsidian glass canvas
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF7C4DFF).withOpacity(0.4),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C4DFF).withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF7C4DFF).withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Color(0xFFD6BCFA),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Google Lyria',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFD6BCFA),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF10B981).withOpacity(0.4),
                              ),
                            ),
                            child: const Text(
                              'Acoustic DTx',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF34D399),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _selectedPreset.title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF1F2F6),
                        ),
                      ),
                    ],
                  ),
                ),
                // Play / Pause Button
                GestureDetector(
                  onTap: _togglePlay,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isPlaying
                            ? [const Color(0xFFEF4444), const Color(0xFFF97316)]
                            : [const Color(0xFF7C4DFF), const Color(0xFF3B82F6)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isPlaying ? const Color(0xFFEF4444) : const Color(0xFF7C4DFF))
                              .withOpacity(0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  icon: Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white70,
                    size: 22,
                  ),
                ),
              ],
            ),

            // Soundwave Visualizer Bars (when playing)
            if (_isPlaying) ...[
              const SizedBox(height: 14),
              AnimatedBuilder(
                animation: _waveController,
                builder: (context, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(24, (index) {
                      final val = (_waveController.value + (index / 24)) % 1.0;
                      final height = 6.0 + 26.0 * (0.5 + 0.5 * (val > 0.5 ? 1.0 - val : val));
                      return Container(
                        width: 3.5,
                        height: height,
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            const Color(0xFFD6BCFA),
                            const Color(0xFF60A5FA),
                            index / 24,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  );
                },
              ),
            ],

            if (_isExpanded) ...[
              const SizedBox(height: 12),
              const Divider(color: Colors.white12),
              const SizedBox(height: 4),
              Text(
                _selectedPreset.description,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Color(0xFFCBD5E1),
                ),
              ),
              const SizedBox(height: 12),
              // Dark custom frequency selector pills - High contrast, ZERO white boxes
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: LyriaSoundscapeService.presets.map((p) {
                  final isSelected = p.id == _selectedPreset.id;
                  return GestureDetector(
                    onTap: () => _selectPreset(p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF7C4DFF).withOpacity(0.35)
                            : const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFA78BFA)
                              : Colors.white24,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 13,
                            color: isSelected ? const Color(0xFFA78BFA) : Colors.white54,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${p.frequencyHz} Hz',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              // Volume Slider Bar
              Row(
                children: [
                  const Icon(Icons.volume_down_rounded, color: Colors.white54, size: 16),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF7C4DFF),
                        inactiveTrackColor: Colors.white12,
                        thumbColor: const Color(0xFFA78BFA),
                        overlayColor: const Color(0xFF7C4DFF).withOpacity(0.2),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: _volume,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (val) {
                          setState(() => _volume = val);
                          LyriaSoundscapeService.setVolume(val);
                        },
                      ),
                    ),
                  ),
                  const Icon(Icons.volume_up_rounded, color: Colors.white54, size: 16),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
