import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/glass_container.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioPlayerService>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top App Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Settings',
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.primary,
                        fontSize: 26,
                      ),
                    ),
                    const Icon(Icons.settings, color: AppColors.primary),
                  ],
                ),
              ),
            ),

            // Master Equalizer Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(20),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Master Equalizer',
                            style: AppTypography.headlineSm.copyWith(
                              color: AppColors.primary,
                              fontSize: 18,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => audioService.resetEqualizer(),
                            icon: const Icon(Icons.restart_alt, size: 16, color: AppColors.secondary),
                            label: Text(
                              'Reset',
                              style: AppTypography.labelCaps.copyWith(color: AppColors.secondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Equalizer Presets Row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: audioService.availablePresets.map((preset) {
                            final isSelected = audioService.activePreset == preset;
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  preset,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: AppColors.primaryContainer,
                                backgroundColor: AppColors.surfaceContainerHigh,
                                onSelected: (_) {
                                  audioService.applyEqualizerPreset(preset);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 5 Frequency Equalizer Sliders
                      SizedBox(
                        height: 180,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildEqSlider('60Hz', 0, audioService),
                            _buildEqSlider('230Hz', 1, audioService),
                            _buildEqSlider('910Hz', 2, audioService),
                            _buildEqSlider('4kHz', 3, audioService),
                            _buildEqSlider('14kHz', 4, audioService),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // AI Auto-Tagger & Playback Settings Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(20),
                  padding: const EdgeInsets.all(20),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Playback & AI Features',
                          style: AppTypography.headlineSm.copyWith(
                            color: AppColors.primary,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // AI Auto-Tagger Switch
                        SwitchListTile(
                          activeColor: AppColors.primary,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Identificador IA y Etiquetado Automático',
                            style: AppTypography.bodyLg.copyWith(fontSize: 15),
                          ),
                          subtitle: Text(
                            'Identifica canciones y descarga portadas automáticamente',
                            style: AppTypography.bodySm.copyWith(fontSize: 12),
                          ),
                          value: audioService.enableAiTagging,
                          onChanged: (val) => audioService.setAiTagging(val),
                        ),
                        const Divider(color: AppColors.outlineVariant, height: 24),

                        // Gapless Playback Switch
                        SwitchListTile(
                          activeColor: AppColors.primary,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Gapless Playback',
                            style: AppTypography.bodyLg.copyWith(fontSize: 15),
                          ),
                          subtitle: Text(
                            'Smooth transitions between tracks',
                            style: AppTypography.bodySm.copyWith(fontSize: 12),
                          ),
                          value: true,
                          onChanged: (val) {},
                        ),
                        const Divider(color: AppColors.outlineVariant, height: 24),

                        // Audio Quality Tile
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Calidad de Audio',
                            style: AppTypography.bodyLg.copyWith(fontSize: 15),
                          ),
                          subtitle: Text(
                            'Wi-Fi Streaming & Downloads',
                            style: AppTypography.bodySm.copyWith(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Muy Alta (320kbps)',
                                style: AppTypography.bodySm.copyWith(color: AppColors.primary),
                              ),
                              const Icon(Icons.chevron_right, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEqSlider(String label, int index, AudioPlayerService audioService) {
    final val = audioService.equalizerGains[index];
    return Column(
      children: [
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.surfaceContainerHighest,
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withOpacity(0.2),
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: val,
                min: 0.0,
                max: 1.0,
                onChanged: (newGain) {
                  audioService.setEqualizerGain(index, newGain);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTypography.monoLabel.copyWith(
            fontSize: 11,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
