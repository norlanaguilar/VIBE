import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/mini_player_bar.dart';
import 'library_screen.dart';
import 'liked_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    LibraryScreen(),
    LikedScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Row(
          children: [
            // Desktop Navigation Drawer Sidebar
            Container(
              width: 260,
              color: AppColors.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Profile & Logo Header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.primaryContainer,
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VibeLocal User',
                            style: AppTypography.headlineSm.copyWith(
                              fontSize: 14,
                              color: AppColors.primaryContainer,
                            ),
                          ),
                          Text(
                            'Premium Member',
                            style: AppTypography.bodySm.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Navigation Links
                  _buildDesktopNavItem(0, Icons.folder_open, 'Local Files'),
                  _buildDesktopNavItem(1, Icons.favorite, 'Me gusta'),
                  _buildDesktopNavItem(2, Icons.settings, 'Ajustes'),

                  const Spacer(),
                  Text(
                    '1.2GB Cache',
                    style: AppTypography.monoLabel.copyWith(color: AppColors.outlineVariant),
                  ),
                ],
              ),
            ),

            // Main Body + MiniPlayer
            Expanded(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _currentIndex,
                    children: _pages,
                  ),
                  const Positioned(
                    left: 20,
                    right: 20,
                    bottom: 12,
                    child: MiniPlayerBar(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile Navigation Shell
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0, // Pegado 100% flush directamente sobre la barra de navegación inferior
            child: MiniPlayerBar(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _currentIndex = idx;
          });
        },
        backgroundColor: AppColors.surfaceContainer.withOpacity(0.95),
        indicatorColor: AppColors.secondaryContainer,
        height: 64,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined, color: AppColors.onSurfaceVariant),
            selectedIcon: Icon(Icons.library_music, color: AppColors.onSecondaryContainer),
            label: 'Biblioteca',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline, color: AppColors.onSurfaceVariant),
            selectedIcon: Icon(Icons.favorite, color: AppColors.onSecondaryContainer),
            label: 'Me gusta',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: AppColors.onSurfaceVariant),
            selectedIcon: Icon(Icons.settings, color: AppColors.onSecondaryContainer),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? Colors.white : AppColors.onSurfaceVariant),
        title: Text(
          label,
          style: AppTypography.bodyLg.copyWith(
            color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        onTap: () {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
