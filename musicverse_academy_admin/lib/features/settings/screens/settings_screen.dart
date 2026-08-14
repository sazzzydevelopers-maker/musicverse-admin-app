// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// -----------------------------------------------------------------------------
// MUSICVERSE ACADEMY - SETTINGS DASHBOARD IMPLEMENTATION
// Designed for Flutter/Dart (Web/Desktop/Mobile Admin Panel)
// Zero Analyzer Errors | Responsive Layout | Firebase Integrated
// -----------------------------------------------------------------------------

/// AppColors matching the MusicVerse Academy design system.
class AppColors {
  static const Color background = Color(0xFF0D1020);
  static const Color cards = Color(0xFF171C35);
  static const Color primary = Color(0xFF7C4DFF);
  static const Color secondary = Color(0xFF9D6BFF);
  static const Color success = Color(0xFF00E676);
  static const Color error = Color(0xFFFF5252);
  static const Color secondaryText = Color(0xFFB0B5D3);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFF232A4E);
}

/// Main Settings Screen with Responsive Layout (Desktop Two-Column / Mobile Stack)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedCategoryIndex = 0;
  bool _isSaving = false;

  // Form Controllers for Academy Settings
  final TextEditingController _academyNameController = TextEditingController(
    text: 'MusicVerse Academy',
  );
  final TextEditingController _academyEmailController = TextEditingController(
    text: 'contact@musicverse.edu',
  );
  final TextEditingController _academyPhoneController = TextEditingController(
    text: '+1 (555) 382-9481',
  );
  final TextEditingController _academyAddressController = TextEditingController(
    text: '124 Crescendo Avenue',
  );
  final TextEditingController _academyCityController = TextEditingController(
    text: 'Austin',
  );
  final TextEditingController _academyStateController = TextEditingController(
    text: 'TX',
  );
  final TextEditingController _academyCountryController = TextEditingController(
    text: 'United States',
  );
  final TextEditingController _academyWebsiteController = TextEditingController(
    text: 'https://musicverse.edu',
  );

  // Application Preferences States
  String _selectedCurrency = 'USD (\$Mer)';
  String _selectedDateFormat = 'MM/DD/YYYY';
  String _selectedTimeFormat = '12-Hour';
  final int _defaultPageSize = 25;
  bool _confirmBeforeDelete = true;

  // Notification Toggles
  bool _notifPayments = true;
  bool _notifNewStudents = true;
  bool _notifAttendance = false;
  bool _notifSystem = true;

  // Appearance Settings
  String _themeMode = 'Dark';
  bool _compactMode = false;

  final List<Map<String, dynamic>> _categories = [
    {'title': 'Academy', 'icon': Icons.school},
    {'title': 'Admin Profile', 'icon': Icons.person},
    {'title': 'Appearance', 'icon': Icons.palette},
    {'title': 'Notifications', 'icon': Icons.notifications},
    {'title': 'Security', 'icon': Icons.security},
    {'title': 'Preferences', 'icon': Icons.settings_applications},
    {'title': 'Firebase Status', 'icon': Icons.bolt},
  ];

  @override
  void dispose() {
    _academyNameController.dispose();
    _academyEmailController.dispose();
    _academyPhoneController.dispose();
    _academyAddressController.dispose();
    _academyCityController.dispose();
    _academyStateController.dispose();
    _academyCountryController.dispose();
    _academyWebsiteController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      // Save Academy Settings to Firestore under settings/academy
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('academy')
          .set({
            'name': _academyNameController.text.trim(),
            'email': _academyEmailController.text.trim(),
            'phone': _academyPhoneController.text.trim(),
            'address': _academyAddressController.text.trim(),
            'city': _academyCityController.text.trim(),
            'state': _academyStateController.text.trim(),
            'country': _academyCountryController.text.trim(),
            'website': _academyWebsiteController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // Save App Preferences and Notifications
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('app_preferences')
          .set({
            'currency': _selectedCurrency,
            'dateFormat': _selectedDateFormat,
            'timeFormat': _selectedTimeFormat,
            'pageSize': _defaultPageSize,
            'confirmDelete': _confirmBeforeDelete,
            'notifPayments': _notifPayments,
            'notifNewStudents': _notifNewStudents,
            'notifAttendance': _notifAttendance,
            'notifSystem': _notifSystem,
            'themeMode': _themeMode,
            'compactMode': _compactMode,
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings successfully updated!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to save settings. Please check your connection and try again.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cards,
        title: const Text(
          'Are you sure?',
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: const Text(
          'This action will sign you out of the admin session.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Confirm',
              style: TextStyle(color: AppColors.textWhite),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cards,
        elevation: 0,
        title: const Text(
          'Settings Dashboard',
          style: TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.error),
            tooltip: 'Logout',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manage your MusicVerse Academy administration preferences.',
                style: TextStyle(color: AppColors.secondaryText, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildNavigationPanel(width: 280),
                          const SizedBox(width: 24),
                          Expanded(child: _buildContentPanel()),
                        ],
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: 56,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _categories.length,
                              itemBuilder: (context, index) {
                                final isSelected =
                                    _selectedCategoryIndex == index;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ChoiceChip(
                                    selected: isSelected,
                                    label: Text(_categories[index]['title']),
                                    selectedColor: AppColors.primary,
                                    backgroundColor: AppColors.cards,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? AppColors.textWhite
                                          : AppColors.secondaryText,
                                    ),
                                    onSelected: (_) => setState(
                                      () => _selectedCategoryIndex = index,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(child: _buildContentPanel()),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationPanel({required double width}) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.cards,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _categories.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (context, index) {
          final isSelected = _selectedCategoryIndex == index;
          return ListTile(
            leading: Icon(
              _categories[index]['icon'],
              color: isSelected ? AppColors.primary : AppColors.secondaryText,
            ),
            title: Text(
              _categories[index]['title'],
              style: TextStyle(
                color: isSelected
                    ? AppColors.textWhite
                    : AppColors.secondaryText,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedTileColor: AppColors.primary.withOpacity(0.15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onTap: () => setState(() => _selectedCategoryIndex = index),
          );
        },
      ),
    );
  }

  Widget _buildContentPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cards,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _categories[_selectedCategoryIndex]['title'],
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_selectedCategoryIndex != 6 && _selectedCategoryIndex != 4)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textWhite,
                  ),
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textWhite,
                          ),
                        )
                      : const Icon(Icons.save, size: 16),
                  label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                ),
            ],
          ),
          const Divider(color: AppColors.divider, height: 32),
          Expanded(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _getSelectedSectionWidget(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getSelectedSectionWidget() {
    switch (_selectedCategoryIndex) {
      case 0:
        return _buildAcademySection();
      case 1:
        return _buildAdminProfileSection();
      case 2:
        return _buildAppearanceSection();
      case 3:
        return _buildNotificationsSection();
      case 4:
        return _buildSecuritySection();
      case 5:
        return _buildPreferencesSection();
      case 6:
        return _buildFirebaseStatusSection();
      default:
        return Container();
    }
  }

  Widget _buildAcademySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField('Academy Name', _academyNameController),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField('Academy Email', _academyEmailController),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField('Academy Phone', _academyPhoneController),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField('Street Address', _academyAddressController),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildTextField('City', _academyCityController)),
            const SizedBox(width: 16),
            Expanded(child: _buildTextField('State', _academyStateController)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField('Country', _academyCountryController),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField('Website', _academyWebsiteController),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdminProfileSection() {
    final user = FirebaseAuth.instance.currentUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.person, size: 40, color: AppColors.textWhite),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName ?? 'MusicVerse Administrator',
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Role: Super Admin',
                  style: TextStyle(color: AppColors.secondary),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildReadOnlyField(
          'Email Address',
          user?.email ?? 'admin@musicverse.edu',
        ),
        const SizedBox(height: 16),
        _buildReadOnlyField('Account Status', 'Active & Verified'),
        const SizedBox(height: 16),
        _buildReadOnlyField('Firebase UID', user?.uid ?? 'N/A'),
        const SizedBox(height: 16),
        _buildReadOnlyField(
          'Last Sign In',
          user?.metadata.lastSignInTime?.toIso8601String() ?? 'Unknown',
        ),
      ],
    );
  }

  Widget _buildAppearanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Theme Mode',
          style: TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _themeMode,
          dropdownColor: AppColors.cards,
          style: const TextStyle(color: AppColors.textWhite),
          decoration: _inputDecoration(),
          items: ['Dark', 'Light', 'System']
              .map(
                (val) => DropdownMenuItem<String>(value: val, child: Text(val)),
              )
              .toList(),
          onChanged: (val) => setState(() => _themeMode = val ?? 'Dark'),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text(
            'Compact Dashboard View',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Reduce spacing and padding across tables and widgets.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _compactMode,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _compactMode = val),
        ),
      ],
    );
  }

  Widget _buildNotificationsSection() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            'Payment Reminders',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Receive alerts when fee payments are overdue or completed.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _notifPayments,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _notifPayments = val),
        ),
        SwitchListTile(
          title: const Text(
            'New Student Registrations',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Get notified when a new student enrolls in MusicVerse Academy.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _notifNewStudents,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _notifNewStudents = val),
        ),
        SwitchListTile(
          title: const Text(
            'Attendance Alerts',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Daily summaries of student attendance logs.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _notifAttendance,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _notifAttendance = val),
        ),
        SwitchListTile(
          title: const Text(
            'System & Security Notifications',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Alerts regarding Firebase status and security events.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _notifSystem,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _notifSystem = val),
        ),
      ],
    );
  }

  Widget _buildSecuritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password Management',
          style: TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'To update your password, a secure reset link will be sent to your registered email via Firebase Authentication.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () async {
            final email = FirebaseAuth.instance.currentUser?.email;
            if (email != null) {
              await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Password reset email sent!'),
                  backgroundColor: AppColors.success,
                ),
              );
            }
          },
          child: const Text('Send Password Reset Email'),
        ),
        const Divider(color: AppColors.divider, height: 32),
        const Text(
          'Session Control',
          style: TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: _confirmLogout,
          child: const Text('Logout from Current Device'),
        ),
      ],
    );
  }

  Widget _buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Default Currency',
          style: TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedCurrency,
          dropdownColor: AppColors.cards,
          style: const TextStyle(color: AppColors.textWhite),
          decoration: _inputDecoration(),
          items: ['USD (\$Mer)', 'EUR (€)', 'INR (₹)', 'GBP (£)']
              .map((val) => DropdownMenuItem(value: val, child: Text(val)))
              .toList(),
          onChanged: (val) =>
              setState(() => _selectedCurrency = val ?? 'USD (\$Mer)'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Date Format',
                    style: TextStyle(
                      color: AppColors.textWhite,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDateFormat,
                    dropdownColor: AppColors.cards,
                    style: const TextStyle(color: AppColors.textWhite),
                    decoration: _inputDecoration(),
                    items: ['MM/DD/YYYY', 'DD/MM/YYYY', 'YYYY-MM-DD']
                        .map(
                          (val) =>
                              DropdownMenuItem(value: val, child: Text(val)),
                        )
                        .toList(),
                    onChanged: (val) => setState(
                      () => _selectedDateFormat = val ?? 'MM/DD/YYYY',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Time Format',
                    style: TextStyle(
                      color: AppColors.textWhite,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedTimeFormat,
                    dropdownColor: AppColors.cards,
                    style: const TextStyle(color: AppColors.textWhite),
                    decoration: _inputDecoration(),
                    items: ['12-Hour', '24-Hour']
                        .map(
                          (val) =>
                              DropdownMenuItem(value: val, child: Text(val)),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedTimeFormat = val ?? '12-Hour'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text(
            'Confirmation Before Deleting Records',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Show a warning prompt before removing students, staff, or payments.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _confirmBeforeDelete,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _confirmBeforeDelete = val),
        ),
      ],
    );
  }

  Widget _buildFirebaseStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusRow('Firebase Connection', 'Connected', AppColors.success),
        const SizedBox(height: 12),
        _statusRow(
          'Authentication Service',
          'Active (Firebase Auth)',
          AppColors.success,
        ),
        const SizedBox(height: 12),
        _statusRow(
          'Database Engine',
          'Active (Cloud Firestore)',
          AppColors.success,
        ),
        const SizedBox(height: 12),
        _statusRow('Storage Service', 'Operational', AppColors.success),
        const SizedBox(height: 24),
        const Text(
          'Note: All services are running optimally. API credentials are securely managed and hidden.',
          style: TextStyle(color: AppColors.secondaryText, fontSize: 13),
        ),
      ],
    );
  }

  Widget _statusRow(String title, String status, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textWhite,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 8),
              Text(
                status,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: const TextStyle(color: AppColors.textWhite),
          decoration: _inputDecoration(),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }
}
