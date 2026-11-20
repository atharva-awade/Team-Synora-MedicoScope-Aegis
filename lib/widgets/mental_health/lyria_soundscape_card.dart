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
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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
    setState(() {
      _isPlaying = LyriaSoundscapeService.isPlaying;
    });
  }

  void _selectPreset(LyriaPreset preset) async {
    setState(() {
      _selectedPreset = preset;
    });
    if (_isPlaying) {
      await LyriaSoundscapeService.playPreset(preset);
      setState(() {
        _isPlaying = LyriaSoundscapeService.isPlaying;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6B46C1).withOpacity(0.22),
            const Color(0xFF3182CE).withOpacity(0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF9F7AEA).withOpacity(0.4),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF805AD5).withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Color(0xFFD6BCFA),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Google Lyria',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFD6BCFA),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF38A169).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Acoustic DTx',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF68D391),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedPreset.title,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                // Play / Pause Circle Button
                GestureDetector(
                  onTap: _togglePlay,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isPlaying
                            ? [const Color(0xFFE53E3E), const Color(0xFFDD6B20)]
                            : [const Color(0xFF805AD5), const Color(0xFF3182CE)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isPlaying ? const Color(0xFFE53E3E) : const Color(0xFF805AD5))
                              .withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  icon: Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white60,
                    size: 20,
                  ),
                ),
              ],
            ),

            // Soundwave Visualizer Bars (when playing)
            if (_isPlaying) ...[
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: _waveController,
                builder: (context, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(24, (index) {
                      final val = (_waveController.value + (index / 24)) % 1.0;
                      final height = 6.0 + 26.0 * (0.5 + 0.5 * (val > 0.5 ? 1.0 - val : val));
                      return Container(
                        width: 3,
                        height: height,
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            const Color(0xFFD6BCFA),
                            const Color(0xFF63B3ED),
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
              const SizedBox(height: 6),
              Text(
                _selectedPreset.clinicalBenefit,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Colors.white70,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: LyriaSoundscapeService.presets.map((p) {
                  final isSelected = p.id == _selectedPreset.id;
                  return ChoiceChip(
                    label: Text('${p.frequencyHz} Hz'),
                    selected: isSelected,
                    onSelected: (_) => _selectPreset(p),
                    selectedColor: const Color(0xFF805AD5).withOpacity(0.5),
                    backgroundColor: Colors.white.withOpacity(0.06),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.white60,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFFD6BCFA)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
