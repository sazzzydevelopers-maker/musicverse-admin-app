import 'package:flutter/material.dart';

import '../../dashboard/screens/dashboard_screen.dart';
import '../../students/screens/student_management_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  final List<_AdminNavigationItem> _navigationItems = const [
    _AdminNavigationItem(title: 'Dashboard', icon: Icons.dashboard_outlined),
    _AdminNavigationItem(title: 'Students', icon: Icons.people_outline),
    _AdminNavigationItem(title: 'Teachers', icon: Icons.groups_outlined),
    _AdminNavigationItem(title: 'Courses', icon: Icons.library_books_outlined),
    _AdminNavigationItem(title: 'Payments', icon: Icons.credit_card_outlined),
    _AdminNavigationItem(
      title: 'Attendance',
      icon: Icons.calendar_month_outlined,
    ),
    _AdminNavigationItem(title: 'Practice', icon: Icons.flag_outlined),
    _AdminNavigationItem(title: 'Assignments', icon: Icons.assignment_outlined),
    _AdminNavigationItem(title: 'Quizzes', icon: Icons.quiz_outlined),
    _AdminNavigationItem(
      title: 'Certificates',
      icon: Icons.workspace_premium_outlined,
    ),
    _AdminNavigationItem(title: 'Reports', icon: Icons.bar_chart_outlined),
    _AdminNavigationItem(title: 'Settings', icon: Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1020),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  // ============================================================
  // SIDEBAR
  // ============================================================

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: const Color(0xFF101326),
      child: Column(
        children: [
          // LOGO
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MusicVerse',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Admin Portal',
                  style: TextStyle(color: Color(0xFF7C4DFF), fontSize: 16),
                ),
              ],
            ),
          ),

          const Divider(color: Color(0xFF252A42), height: 1),

          const SizedBox(height: 18),

          // NAVIGATION
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _navigationItems.length,
              itemBuilder: (context, index) {
                final item = _navigationItems[index];

                // Only Dashboard and Students are currently implemented.
                final isImplemented = index == 0 || index == 1;

                final isSelected = _selectedIndex == index;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      if (isImplemented) {
                        // Dashboard or Students
                        setState(() {
                          _selectedIndex = index;
                        });
                      } else {
                        // All other sections
                        _showComingSoonDialog(item.title);
                      }
                    },
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF27204D)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: isSelected
                            ? const Border(
                                left: BorderSide(
                                  color: Color(0xFF7C4DFF),
                                  width: 4,
                                ),
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),

                          Icon(
                            item.icon,
                            size: 23,
                            color: isSelected
                                ? const Color(0xFF7C4DFF)
                                : const Color(0xFFB0B5D3),
                          ),

                          const SizedBox(width: 16),

                          Text(
                            item.title,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFFB0B5D3),
                              fontSize: 16,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // FOOTER
          const Padding(
            padding: EdgeInsets.all(20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'MusicVerse Academy Admin',
                style: TextStyle(color: Color(0xFFB0B5D3), fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MAIN CONTENT
  // ============================================================

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0:
        return const DashboardScreen();

      case 1:
        return const StudentManagementScreen();

      default:
        return const DashboardScreen();
    }
  }

  // ============================================================
  // COMING SOON POPUP
  // ============================================================

  void _showComingSoonDialog(String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF171C35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ICON
                Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    color: Color(0xFF27204D),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.construction_outlined,
                    color: Color(0xFF7C4DFF),
                    size: 36,
                  ),
                ),

                const SizedBox(height: 20),

                // TITLE
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                // MESSAGE
                const Text(
                  'Coming Soon',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF9D6BFF),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'This section is currently under development.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB0B5D3), fontSize: 14),
                ),

                const SizedBox(height: 24),

                // OK BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4DFF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// NAVIGATION ITEM MODEL
// ============================================================

class _AdminNavigationItem {
  final String title;
  final IconData icon;

  const _AdminNavigationItem({required this.title, required this.icon});
}
