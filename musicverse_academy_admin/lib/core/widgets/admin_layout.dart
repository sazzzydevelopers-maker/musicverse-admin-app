import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminLayout extends StatelessWidget {
  final Widget child;

  const AdminLayout({super.key, required this.child});

  static const Color bgColor = Color(0xFF0D1020);
  static const Color cardColor = Color(0xFF171C35);
  static const Color primaryColor = Color(0xFF7C4DFF);
  static const Color textSecondary = Color(0xFFB0B5D3);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          // ==========================================
          // PERMANENT SIDEBAR
          // ==========================================
          Container(
            width: 290,
            color: cardColor,
            child: _buildSidebar(context),
          ),

          // ==========================================
          // PAGE CONTENT
          // ==========================================
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final currentLocation = GoRouterState.of(context).uri.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 50),

        // ==========================================
        // LOGO / TITLE
        // ==========================================
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'MusicVerse',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(height: 8),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Admin Portal',
            style: TextStyle(
              color: primaryColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        const SizedBox(height: 30),

        // ==========================================
        // DASHBOARD
        // ==========================================
        _buildMenuItem(
          context: context,
          icon: Icons.dashboard_rounded,
          title: 'Dashboard',
          route: '/dashboard',
          selected: currentLocation == '/dashboard',
        ),

        // ==========================================
        // STUDENTS
        // ==========================================
        _buildMenuItem(
          context: context,
          icon: Icons.people_rounded,
          title: 'Students',
          route: '/students',
          selected: currentLocation == '/students',
        ),

        const Spacer(),

        // ==========================================
        // VERSION
        // ==========================================
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'MusicVerse Academy Admin',
            style: TextStyle(color: textSecondary, fontSize: 12),
          ),
        ),

        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String route,
    required bool selected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected
            ? primaryColor.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            context.go(route);
          },
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? const Border(
                      left: BorderSide(color: primaryColor, width: 3),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 23,
                  color: selected ? primaryColor : textSecondary,
                ),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: TextStyle(
                    color: selected ? Colors.white : textSecondary,
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
