import 'dart:async';
import 'package:flutter/material.dart';
// ignore: unnecessary_import
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

class StudentManagementScreen extends StatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  final TextEditingController _searchController = TextEditingController();

  // Keeps the search field focused while the student list rebuilds.
  final FocusNode _searchFocusNode = FocusNode();

  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');
  Timer? _searchDebounce;
  String _selectedAccountStatus = 'All';
  String _selectedFeeStatus = 'All';
  String _selectedCourse = 'All';

  // ============================================================
  // THEME COLORS
  // ============================================================

  static const Color bgColor = Color(0xFF0D1020);

  static const Color cardColor = Color(0xFF171C35);

  static const Color primaryColor = Color(0xFF7C4DFF);

  static const Color secondaryColor = Color(0xFF9D6BFF);

  static const Color successColor = Color(0xFF00E676);

  static const Color errorColor = Color(0xFFFF5252);

  static const Color warningColor = Color(0xFFFFC107);

  static const Color textSecondary = Color(0xFFB0B5D3);

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchQueryNotifier.dispose();
    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,

      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            context.go('/dashboard');
          },
        ),

        title: const Text(
          'Student Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),

        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),

            icon: const Icon(Icons.person_add, size: 18),

            label: const Text('Add Student'),

            onPressed: () {
              _showAddOrEditStudentDialog(context);
            },
          ),

          const SizedBox(width: 16),
        ],
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load students.',
                style: TextStyle(color: errorColor),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          // ====================================================
          // STATISTICS
          // ====================================================

          final int totalStudents = docs.length;

          final int activeStudents = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;

            return data['is_active'] == true ||
                data['accountStatus'] == 'Active';
          }).length;

          final int inactiveStudents = totalStudents - activeStudents;

          final int paidStudents = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;

            return data['feeStatus'] == 'Paid';
          }).length;

          final int pendingFees = totalStudents - paidStudents;

          // ====================================================
          // COURSES
          // ====================================================
          //
          // Keep the course filter fixed instead of generating the
          // list from the students currently stored in Firestore.
          // This ensures every course is always available in the
          // Student Management search/filter dropdown.
          //
          // Required course list:
          // Piano, Guitar, Drums, Flute, Violin
          //
          final List<String> availableCourses = [
            'All',
            'Piano',
            'Guitar',
            'Drums',
            'Flute',
            'Violin',
          ];

          return ValueListenableBuilder<String>(
            valueListenable: _searchQueryNotifier,
            builder: (context, searchQuery, _) {
              // ====================================================
              // FILTER
              // ====================================================

              final filteredDocs = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;

                final firstName = (data['first_name'] ?? '')
                    .toString()
                    .toLowerCase();

                final lastName = (data['last_name'] ?? '')
                    .toString()
                    .toLowerCase();

                final studentId = (data['studentId'] ?? '')
                    .toString()
                    .toLowerCase();

                final email = (data['email'] ?? '').toString().toLowerCase();

                final phone = (data['phone_number'] ?? '')
                    .toString()
                    .toLowerCase();

                final fullName = '$firstName $lastName';

                final accountStatus = data['accountStatus'] ?? 'Inactive';

                final feeStatus = data['feeStatus'] ?? 'Pending';

                final course = data['course'] ?? '';

                final bool matchesSearch =
                    searchQuery.isEmpty ||
                    fullName.contains(searchQuery) ||
                    studentId.contains(searchQuery) ||
                    email.contains(searchQuery) ||
                    phone.contains(searchQuery);

                final bool matchesAccount =
                    _selectedAccountStatus == 'All' ||
                    accountStatus == _selectedAccountStatus;

                final bool matchesFee =
                    _selectedFeeStatus == 'All' ||
                    feeStatus == _selectedFeeStatus;

                final bool matchesCourse =
                    _selectedCourse == 'All' || course == _selectedCourse;

                return matchesSearch &&
                    matchesAccount &&
                    matchesFee &&
                    matchesCourse;
              }).toList();

              return LayoutBuilder(
                builder: (context, constraints) {
                  final bool isDesktop = constraints.maxWidth > 900;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        const Text(
                          'Manage and monitor all MusicVerse Academy students.',
                          style: TextStyle(color: textSecondary, fontSize: 14),
                        ),

                        const SizedBox(height: 20),

                        // ==================================================
                        // STAT CARDS
                        // ==================================================
                        GridView.count(
                          crossAxisCount: constraints.maxWidth > 1200
                              ? 5
                              : constraints.maxWidth > 700
                              ? 3
                              : 2,

                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,

                          shrinkWrap: true,

                          physics: const NeverScrollableScrollPhysics(),

                          childAspectRatio: 1.6,

                          children: [
                            _buildStatCard(
                              'Total Students',
                              totalStudents.toString(),
                              primaryColor,
                              Icons.people,
                            ),

                            _buildStatCard(
                              'Active Students',
                              activeStudents.toString(),
                              successColor,
                              Icons.check_circle,
                            ),

                            _buildStatCard(
                              'Inactive Students',
                              inactiveStudents.toString(),
                              errorColor,
                              Icons.cancel,
                            ),

                            _buildStatCard(
                              'Paid Students',
                              paidStudents.toString(),
                              secondaryColor,
                              Icons.payment,
                            ),

                            _buildStatCard(
                              'Pending Fees',
                              pendingFees.toString(),
                              warningColor,
                              Icons.pending,
                            ),
                          ],
                        ),

                        const SizedBox(height: 28),

                        // ==================================================
                        // SEARCH + FILTERS
                        // ==================================================
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,

                          children: [
                            SizedBox(
                              width: isDesktop ? 300 : double.infinity,

                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,

                                style: const TextStyle(color: Colors.white),

                                onChanged: (value) {
                                  // Smooth live search:
                                  // - keep the TextField mounted
                                  // - keep keyboard/cursor focus
                                  // - avoid unnecessary rapid rebuilds
                                  // - update only the filtered student list
                                  _searchDebounce?.cancel();

                                  final String query = value
                                      .trim()
                                      .toLowerCase();

                                  _searchDebounce = Timer(
                                    const Duration(milliseconds: 180),
                                    () {
                                      if (!mounted) {
                                        return;
                                      }

                                      _searchQueryNotifier.value = query;
                                    },
                                  );
                                },

                                decoration: InputDecoration(
                                  hintText: 'Search students...',

                                  hintStyle: const TextStyle(
                                    color: textSecondary,
                                  ),

                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: textSecondary,
                                  ),

                                  filled: true,

                                  fillColor: cardColor,

                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),

                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),

                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: primaryColor,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            _buildDropdownFilter(
                              'Account',
                              _selectedAccountStatus,
                              ['All', 'Active', 'Inactive'],
                              (value) {
                                setState(() {
                                  _selectedAccountStatus = value!;
                                });
                              },
                            ),

                            _buildDropdownFilter(
                              'Fee',
                              _selectedFeeStatus,
                              ['All', 'Paid', 'Pending'],
                              (value) {
                                setState(() {
                                  _selectedFeeStatus = value!;
                                });
                              },
                            ),

                            _buildDropdownFilter(
                              'Course',
                              _selectedCourse,
                              availableCourses,
                              (value) {
                                setState(() {
                                  _selectedCourse = value!;
                                });
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // ==================================================
                        // STUDENT LIST
                        // ==================================================
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                          child: filteredDocs.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(40),
                                  child: Center(
                                    child: Text(
                                      'No students found',
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  itemCount: filteredDocs.length,
                                  separatorBuilder: (context, index) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      child: Divider(
                                        color: Colors.white.withValues(
                                          alpha: 0.07,
                                        ),
                                        height: 1,
                                      ),
                                    );
                                  },
                                  itemBuilder: (context, index) {
                                    final doc = filteredDocs[index];

                                    final data =
                                        doc.data() as Map<String, dynamic>;

                                    final String docId = doc.id;

                                    final String firstName =
                                        data['first_name']?.toString() ?? '';

                                    final String lastName =
                                        data['last_name']?.toString() ?? '';

                                    final String studentId =
                                        data['studentId']?.toString() ?? 'N/A';

                                    final String course =
                                        (data['preferred_instrument'] ??
                                                data['course'] ??
                                                'General')
                                            .toString();

                                    final String phone =
                                        data['phone_number']?.toString() ??
                                        'N/A';

                                    final String feeStatus =
                                        data['feeStatus']?.toString() ??
                                        'Pending';

                                    final String accountStatus =
                                        data['is_active'] == true ||
                                            data['accountStatus'] == 'Active'
                                        ? 'Active'
                                        : 'Inactive';

                                    final String profilePhoto =
                                        (data['profile_photo'] ??
                                                data['profilePhoto'] ??
                                                '')
                                            .toString();

                                    return _buildStudentManagementCard(
                                      context: context,
                                      data: data,
                                      docId: docId,
                                      firstName: firstName,
                                      lastName: lastName,
                                      studentId: studentId,
                                      course: course,
                                      phone: phone,
                                      feeStatus: feeStatus,
                                      accountStatus: accountStatus,
                                      profilePhoto: profilePhoto,
                                      isDesktop: isDesktop,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ============================================================
  // RESPONSIVE STUDENT CARD
  // ============================================================

  Widget _buildStudentManagementCard({
    required BuildContext context,
    required Map<String, dynamic> data,
    required String docId,
    required String firstName,
    required String lastName,
    required String studentId,
    required String course,
    required String phone,
    required String feeStatus,
    required String accountStatus,
    required String profilePhoto,
    required bool isDesktop,
  }) {
    final String fullName = '$firstName $lastName'.trim().isEmpty
        ? 'Unnamed Student'
        : '$firstName $lastName'.trim();

    final bool isPaid = feeStatus == 'Paid';
    final bool isActive = accountStatus == 'Active';

    // Gender and Grade are read directly from the same Firestore
    // student document. Existing students that do not yet have these
    // fields will safely display "Not Set".
    final String gender = data['gender']?.toString().trim().isNotEmpty == true
        ? data['gender'].toString().trim()
        : 'Not Set';

    final String grade = data['grade']?.toString().trim().isNotEmpty == true
        ? data['grade'].toString().trim()
        : 'Not Set';

    // ============================================================
    // EMAIL + VERIFICATION STATUS
    // ============================================================

    final String email = data['email']?.toString().trim().isNotEmpty == true
        ? data['email'].toString().trim()
        : 'Not Set';

    final bool emailVerified = data['email_verified'] == true;

    final String emailVerificationText = emailVerified
        ? 'Verified'
        : 'Not Verified';

    final Color emailVerificationColor = emailVerified
        ? successColor
        : errorColor;

    final IconData emailVerificationIcon = emailVerified
        ? Icons.verified_outlined
        : Icons.mark_email_unread_outlined;
    final Widget menu = PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: textSecondary),
      color: cardColor,
      tooltip: 'Student actions',
      onSelected: (value) {
        if (value == 'view') {
          _showStudentDetailsModal(context, data);
        }

        if (value == 'edit') {
          _showAddOrEditStudentDialog(
            context,
            docId: docId,
            existingData: data,
          );
        }

        if (value == 'toggle') {
          _confirmToggleAccountStatus(context, docId, accountStatus);
        }

        if (value == 'send_verification') {
          _sendVerificationMail(context, data);
        }

        if (value == 'delete') {
          _showDeleteAccountDialog(context, docId, data);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'view',
          child: Text('View Details', style: TextStyle(color: Colors.white)),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Text('Edit Student', style: TextStyle(color: Colors.white)),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Text(
            isActive ? 'Deactivate' : 'Activate',
            style: TextStyle(color: isActive ? errorColor : successColor),
          ),
        ),

        if (!emailVerified)
          const PopupMenuItem(
            value: 'send_verification',
            child: Row(
              children: [
                Icon(
                  Icons.mark_email_unread_outlined,
                  color: primaryColor,
                  size: 20,
                ),
                SizedBox(width: 10),
                Text(
                  'Send Verification Mail',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          )
        else
          const PopupMenuItem(
            enabled: false,
            value: 'email_verified',
            child: Row(
              children: [
                Icon(Icons.verified_outlined, color: successColor, size: 20),
                SizedBox(width: 10),
                Text('Email Verified', style: TextStyle(color: successColor)),
              ],
            ),
          ),

        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete Account', style: TextStyle(color: errorColor)),
        ),
      ],
    );

    final Widget avatar = _buildProfileAvatar(
      profilePhoto,
      firstName,
      lastName,
    );

    final Widget nameAndId = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          studentId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: textSecondary, fontSize: 12.5),
        ),
      ],
    );

    final Widget details = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildStudentInfoPill(Icons.music_note_rounded, course),
        _buildStudentInfoPill(Icons.phone_rounded, phone),
        _buildStudentInfoPill(Icons.person_outline_rounded, gender),
        _buildStudentInfoPill(Icons.school_outlined, grade),
      ],
    );

    final Widget statusArea = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildStudentStatusBadge(
          feeStatus,
          isPaid ? successColor : errorColor,
          isPaid ? Icons.check_circle_outline : Icons.pending_outlined,
        ),

        _buildStudentStatusBadge(
          accountStatus,
          isActive ? successColor : Colors.grey,
          isActive ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
        ),

        _buildStudentStatusBadge(
          emailVerificationText,
          emailVerificationColor,
          emailVerificationIcon,
        ),
      ],
    );

    // ------------------------------------------------------------
    // MOBILE / SMALL SCREEN
    // ------------------------------------------------------------
    if (!isDesktop) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? primaryColor.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.07),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                avatar,
                const SizedBox(width: 14),
                Expanded(child: nameAndId),
                const SizedBox(width: 4),
                menu,
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgColor.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStudentDetailLine(
                    'Course',
                    course,
                    Icons.music_note_rounded,
                  ),
                  const SizedBox(height: 9),

                  _buildStudentDetailLine('Email', email, Icons.email_outlined),
                  const SizedBox(height: 9),

                  _buildStudentDetailLine('Phone', phone, Icons.phone_rounded),
                  const SizedBox(height: 9),
                  _buildStudentDetailLine(
                    'Gender',
                    gender,
                    Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 9),
                  _buildStudentDetailLine(
                    'Grade',
                    grade,
                    Icons.school_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            statusArea,
          ],
        ),
      );
    }

    // ------------------------------------------------------------
    // DESKTOP / LARGE SCREEN
    // ------------------------------------------------------------
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          avatar,
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [nameAndId, const SizedBox(height: 10), details],
            ),
          ),
          const SizedBox(width: 20),
          statusArea,
          const SizedBox(width: 12),
          menu,
        ],
      ),
    );
  }

  Widget _buildStudentInfoPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: secondaryColor),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentStatusBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentDetailLine(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: secondaryColor),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            color: textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PROFILE AVATAR
  // ============================================================

  Widget _buildProfileAvatar(
    String profilePhoto,
    String firstName,
    String lastName,
  ) {
    if (profilePhoto.isNotEmpty) {
      return CircleAvatar(
        radius: 24,

        backgroundColor: primaryColor,

        backgroundImage: NetworkImage(profilePhoto),
      );
    }

    return CircleAvatar(
      radius: 24,

      backgroundColor: primaryColor,

      child: Text(
        _getInitials(firstName, lastName),

        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getInitials(String firstName, String lastName) {
    final String first = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';

    final String last = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';

    final String initials = '$first$last';

    return initials.isEmpty ? 'S' : initials;
  }

  // ============================================================
  // STAT CARD
  // ============================================================

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius: BorderRadius.circular(12),

        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        mainAxisAlignment: MainAxisAlignment.center,

        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [
              Text(
                title,
                style: const TextStyle(color: textSecondary, fontSize: 13),
              ),

              Icon(icon, color: color, size: 20),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            value,

            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DROPDOWN FILTER
  // ============================================================

  Widget _buildDropdownFilter(
    String label,
    String currentValue,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius: BorderRadius.circular(8),
      ),

      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(currentValue) ? currentValue : items.first,

          dropdownColor: cardColor,

          style: const TextStyle(color: Colors.white, fontSize: 14),

          icon: const Icon(Icons.arrow_drop_down, color: textSecondary),

          items: items
              .map(
                (item) =>
                    DropdownMenuItem(value: item, child: Text('$label: $item')),
              )
              .toList(),

          onChanged: onChanged,
        ),
      ),
    );
  }

  // ============================================================
  // ADD / EDIT STUDENT DIALOG
  // ============================================================

  void _showAddOrEditStudentDialog(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? existingData,
  }) {
    final bool isEditing = docId != null;

    // ==========================================================
    // CONTROLLERS
    // ==========================================================

    final firstNameController = TextEditingController(
      text: existingData?['first_name']?.toString() ?? '',
    );

    final lastNameController = TextEditingController(
      text: existingData?['last_name']?.toString() ?? '',
    );

    final emailController = TextEditingController(
      text: existingData?['email']?.toString() ?? '',
    );

    final phoneController = TextEditingController(
      text: existingData?['phone_number']?.toString() ?? '',
    );

    final monthlyFeeController = TextEditingController(
      text: existingData?['monthlyFee']?.toString() ?? '',
    );

    // Student ID is generated only for a NEW student.
    // In Edit Student, the existing ID is never shown as an editable field.
    final studentIdController = TextEditingController(
      text: isEditing
          ? (existingData?['studentId']?.toString() ?? '')
          : _generateStudentId(),
    );

    // ==========================================================
    // FORM KEY
    // ==========================================================

    final formKey = GlobalKey<FormState>();

    // ==========================================================
    // PHOTO VARIABLES
    // ==========================================================

    Uint8List? selectedImageBytes;

    String? existingImageUrl =
        (existingData?['profile_photo'] ?? existingData?['profilePhoto'])
            ?.toString();
    // Selected course for the required course dropdown.
    //
    // IMPORTANT:
    // The dropdown has only these allowed values:
    // Piano, Guitar, Drums, Flute, Violin.
    //
    // Older Firestore records may contain values such as
    // "Advanced Piano". If that value is used directly as the
    // DropdownButton value, Flutter throws:
    // "There should be exactly one item with DropdownButton's value."
    //
    // Therefore, only use the existing value when it is one of
    // the current allowed course values. Otherwise show "Select Course"
    // and require the admin to choose a valid course before saving.
    const List<String> courseOptions = [
      'Piano',
      'Guitar',
      'Drums',
      'Flute',
      'Violin',
      'Vocals',
    ];

    final String? existingCourse = existingData?['preferred_instrument']
        ?.toString()
        .trim();
    String? selectedCourse =
        existingCourse != null && courseOptions.contains(existingCourse)
        ? existingCourse
        : null;

    const List<String> genderOptions = ['Male', 'Female', 'Other'];

    final String? existingGender = existingData?['gender']?.toString().trim();

    String? selectedGender =
        existingGender != null && genderOptions.contains(existingGender)
        ? existingGender
        : null;

    const List<String> gradeOptions = [
      'Grade 1',
      'Grade 2',
      'Grade 3',
      'Grade 4',
      'Grade 5',
      'Grade 6',
      'Grade 7',
      'Grade 8',
      'Grade 9',
      'Other',
    ];

    final String? existingGrade = existingData?['grade']?.toString().trim();

    String? selectedGrade =
        existingGrade != null && gradeOptions.contains(existingGrade)
        ? existingGrade
        : null;

    bool saving = false;

    // ==========================================================
    // SHOW DIALOG
    // ==========================================================

    showDialog(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // ==================================================
            // PICK PHOTO
            // ==================================================

            Future<void> pickStudentImage() async {
              try {
                // ==========================================================
                // 1. SELECT IMAGE
                // ==========================================================

                final ImagePicker picker = ImagePicker();

                final XFile? pickedImage = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 90,
                );

                // User cancelled image selection
                if (pickedImage == null) {
                  return;
                }

                // The dialog may have been closed while the gallery was open.
                if (!dialogContext.mounted) {
                  return;
                }

                // ==========================================================
                // 2. OPEN ADJUSTABLE CROP EDITOR
                // ==========================================================

                final CroppedFile? croppedFile = await ImageCropper().cropImage(
                  sourcePath: pickedImage.path,

                  uiSettings: [
                    // ======================================================
                    // ANDROID
                    // ======================================================
                    AndroidUiSettings(
                      toolbarTitle: 'Adjust Photo',
                      toolbarColor: bgColor,
                      toolbarWidgetColor: Colors.white,
                      activeControlsWidgetColor: primaryColor,

                      cropStyle: CropStyle.circle,

                      aspectRatioPresets: [CropAspectRatioPreset.square],

                      lockAspectRatio: true,

                      hideBottomControls: false,
                    ),

                    // ======================================================
                    // iOS
                    // ======================================================
                    IOSUiSettings(
                      title: 'Adjust Photo',

                      cropStyle: CropStyle.circle,

                      aspectRatioPresets: [CropAspectRatioPreset.square],

                      resetAspectRatioEnabled: false,
                      aspectRatioLockEnabled: true,

                      rotateButtonsHidden: false,
                      rotateClockwiseButtonHidden: false,

                      doneButtonTitle: 'Done',
                      cancelButtonTitle: 'Cancel',
                    ),

                    // ======================================================
                    // WEB
                    // ======================================================
                    WebUiSettings(
                      context: dialogContext,
                      presentStyle: WebPresentStyle.dialog,
                      barrierColor: Colors.black87,

                      dragMode: WebDragMode.move,

                      // Image controls
                      movable: true,
                      scalable: true,
                      zoomable: true,
                      rotatable: true,

                      zoomOnWheel: true,
                      zoomOnTouch: true,

                      // Fixed crop box
                      cropBoxMovable: false,
                      cropBoxResizable: false,

                      toggleDragModeOnDblclick: false,

                      // UI
                      guides: true,
                      center: true,
                      highlight: true,
                      background: true,

                      // Square crop
                      viewwMode: WebViewMode.mode_2,
                      initialAspectRatio: 1,

                      minCropBoxWidth: 250,
                      minCropBoxHeight: 250,

                      size: const CropperSize(width: 500, height: 350),
                    ),
                  ],
                );

                // ==========================================================
                // 3. USER CANCELLED CROPPING
                // ==========================================================

                if (croppedFile == null) {
                  return;
                }

                // ==========================================================
                // 4. READ CROPPED IMAGE
                // ==========================================================

                final Uint8List croppedBytes = await croppedFile.readAsBytes();

                if (!dialogContext.mounted) {
                  return;
                }

                // ==========================================================
                // 5. STORE THE ADJUSTED IMAGE
                // ==========================================================

                setDialogState(() {
                  selectedImageBytes = croppedBytes;
                });
              } catch (e) {
                debugPrint('Error selecting student image: $e');

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to select image: $e')),
                );
              }
            }

            // ==================================================
            // UPLOAD PHOTO
            // ==================================================

            Future<String?> uploadStudentImage(
              String documentId,
              Uint8List imageBytes,
            ) async {
              try {
                final String fileName =
                    '${DateTime.now().millisecondsSinceEpoch}.jpg';

                final Reference storageRef = FirebaseStorage.instance
                    .ref()
                    .child('student_profiles')
                    .child(documentId)
                    .child(fileName);

                await storageRef.putData(
                  imageBytes,
                  SettableMetadata(contentType: 'image/jpeg'),
                );

                final String downloadUrl = await storageRef.getDownloadURL();

                return downloadUrl;
              } catch (e) {
                // Photo is optional. A Storage failure must never
                // prevent the student record from being saved.
                debugPrint('Photo upload failed: $e');
                return null;
              }
            }

            // ==================================================
            // SAVE STUDENT
            // ==================================================

            Future<void> saveStudent() async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              setDialogState(() {
                saving = true;
              });

              try {
                final String firstName = firstNameController.text.trim();
                final String lastName = lastNameController.text.trim();
                final String email = emailController.text.trim();

                final Map<String, dynamic> studentData = {
                  'first_name': firstName,
                  'last_name': lastName,
                  'full_name': '$firstName $lastName'.trim(),
                  'email': email,
                  'phone_number': phoneController.text.trim(),
                  'preferred_instrument': selectedCourse!,
                  'gender': selectedGender!,
                  'grade': selectedGrade!,
                  'monthlyFee': double.parse(monthlyFeeController.text.trim()),
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                // ==================================================
                // EDIT EXISTING STUDENT
                // ==================================================

                if (isEditing) {
                  final String editingDocId = docId;

                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(editingDocId)
                      .update(studentData);

                  final Uint8List? imageBytesToUpload = selectedImageBytes;

                  if (imageBytesToUpload != null) {
                    uploadStudentImage(editingDocId, imageBytesToUpload).then((
                      imageUrl,
                    ) async {
                      if (imageUrl != null && imageUrl.isNotEmpty) {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(editingDocId)
                            .update({
                              'profile_photo': imageUrl,
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                      }
                    });
                  }

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Student updated successfully.'),
                    ),
                  );

                  return;
                }

                // ==================================================
                // ADD NEW STUDENT
                // ==================================================

                String newStudentId = studentIdController.text.trim();

                final CollectionReference<Map<String, dynamic>> users =
                    FirebaseFirestore.instance.collection('users');

                for (int attempt = 0; attempt < 20; attempt++) {
                  final QuerySnapshot<Map<String, dynamic>> existingId =
                      await users
                          .where('studentId', isEqualTo: newStudentId)
                          .limit(1)
                          .get();

                  if (existingId.docs.isEmpty) {
                    break;
                  }

                  newStudentId = _generateStudentId();
                }

                final QuerySnapshot<Map<String, dynamic>> finalCheck =
                    await users
                        .where('studentId', isEqualTo: newStudentId)
                        .limit(1)
                        .get();

                if (finalCheck.docs.isNotEmpty) {
                  throw Exception('Unable to generate a unique Student ID.');
                }

                // ==================================================
                // CREATE FIREBASE AUTH ACCOUNT
                // ==================================================
                //
                // A secondary Firebase app is used so the Admin
                // account remains logged in.
                //
                final Map<String, String> authResult =
                    await _createStudentAuthAccount(email: email);

                final String studentUid = authResult['uid']!;
                final String temporaryPassword =
                    authResult['temporaryPassword']!;

                // ==================================================
                // CREATE USERS/{AUTH_UID}
                // ==================================================
                //
                // Firestore document ID is the same Firebase Auth UID.
                //
                final DocumentReference<Map<String, dynamic>> newStudentRef =
                    users.doc(studentUid);

                studentData.addAll({
                  'uid': studentUid,
                  'studentId': newStudentId,
                  'role': 'student',
                  'email_verified': false,
                  'is_active': true,
                  'accountStatus': 'Active',
                  'feeStatus': 'Pending',
                  'must_change_password': true,
                  'profile_completed': false,
                  'presentDays': 0,
                  'absentDays': 0,
                  'todayAttendance': 'Pending',
                  'practiceProgress': 0,
                  'profile_photo': '',
                  'createdAt': FieldValue.serverTimestamp(),
                });

                await newStudentRef.set(studentData);

                // ==================================================
                // OPTIONAL PHOTO
                // ==================================================

                final Uint8List? imageBytesToUpload = selectedImageBytes;

                if (imageBytesToUpload != null) {
                  uploadStudentImage(studentUid, imageBytesToUpload).then((
                    imageUrl,
                  ) async {
                    if (imageUrl != null && imageUrl.isNotEmpty) {
                      await newStudentRef.update({
                        'profile_photo': imageUrl,
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                    }
                  });
                }

                // ==================================================
                // CLOSE ADD DIALOG
                // ==================================================

                if (!dialogContext.mounted) {
                  return;
                }

                Navigator.of(dialogContext).pop();

                // ==================================================
                // SHOW TEMPORARY PASSWORD
                // ==================================================

                await _showTemporaryPasswordDialog(
                  context,
                  studentName: '$firstName $lastName'.trim(),
                  email: email,
                  studentId: newStudentId,
                  temporaryPassword: temporaryPassword,
                );
              } catch (e) {
                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  saving = false;
                });

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Failed to save student: $e')),
                );
              }
            }

            // ==================================================
            // PHOTO PREVIEW
            // ==================================================

            Widget photoPreview;

            // --------------------------------------------------
            // NEWLY SELECTED PHOTO
            // --------------------------------------------------

            if (selectedImageBytes != null) {
              photoPreview = ClipOval(
                child: SizedBox(
                  width: 110,
                  height: 110,

                  child: Image.memory(
                    selectedImageBytes!,

                    width: 110,
                    height: 110,

                    // IMPORTANT:
                    // Fill the circle correctly.
                    fit: BoxFit.cover,

                    alignment: Alignment.center,
                  ),
                ),
              );
            }
            // --------------------------------------------------
            // EXISTING FIREBASE PHOTO
            // --------------------------------------------------
            else if (existingImageUrl != null &&
                existingImageUrl.trim().isNotEmpty) {
              final String existingPhotoUrl = existingImageUrl.trim();

              photoPreview = ClipOval(
                child: SizedBox(
                  width: 110,
                  height: 110,

                  child: Image.network(
                    existingPhotoUrl,

                    width: 110,
                    height: 110,

                    fit: BoxFit.cover,

                    alignment: Alignment.center,

                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 110,
                        height: 110,

                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,

                          color: primaryColor,
                        ),

                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 48,
                        ),
                      );
                    },
                  ),
                ),
              );
            }
            // --------------------------------------------------
            // NO PHOTO
            // --------------------------------------------------
            else {
              photoPreview = Container(
                width: 110,
                height: 110,

                decoration: const BoxDecoration(
                  shape: BoxShape.circle,

                  color: primaryColor,
                ),

                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 42,
                ),
              );
            }

            // ==================================================
            // DIALOG
            // ==================================================

            return AlertDialog(
              backgroundColor: cardColor,

              title: Text(
                isEditing ? 'Edit Student' : 'Add New Student',

                style: const TextStyle(
                  color: Colors.white,

                  fontWeight: FontWeight.bold,

                  fontSize: 24,
                ),
              ),

              content: SizedBox(
                width: 450,

                // Prevent the dialog
                // from becoming too tall.
                height: 570,

                child: Form(
                  key: formKey,

                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        // ======================================
                        // PHOTO
                        // ======================================
                        GestureDetector(
                          onTap: saving ? null : pickStudentImage,

                          child: photoPreview,
                        ),

                        const SizedBox(height: 10),

                        TextButton.icon(
                          onPressed: saving ? null : pickStudentImage,

                          icon: const Icon(
                            Icons.photo_library,
                            color: primaryColor,
                          ),

                          label: Text(
                            selectedImageBytes != null
                                ? 'Change Photo'
                                : 'Select Photo',

                            style: const TextStyle(
                              color: Colors.white,

                              fontSize: 14,
                            ),
                          ),
                        ),

                        const Text(
                          'Student Photo',
                          style: TextStyle(color: textSecondary, fontSize: 13),
                        ),

                        const SizedBox(height: 20),

                        // ======================================
                        // FIRST NAME
                        // ======================================
                        _buildRequiredTextField(
                          label: 'First Name',

                          controller: firstNameController,
                        ),

                        const SizedBox(height: 12),

                        // ======================================
                        // LAST NAME
                        // ======================================
                        _buildRequiredTextField(
                          label: 'Last Name',

                          controller: lastNameController,
                        ),

                        const SizedBox(height: 12),

                        // ======================================
                        // STUDENT ID
                        // ======================================
                        // Add Student: show an automatic read-only ID.
                        // Edit Student: do not show the ID field at all.
                        if (!isEditing) ...[
                          TextFormField(
                            controller: studentIdController,
                            readOnly: true,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Student ID',
                              helperStyle: const TextStyle(
                                color: textSecondary,
                              ),
                              labelStyle: const TextStyle(color: textSecondary),
                              filled: true,
                              fillColor: bgColor,
                              prefixIcon: const Icon(
                                Icons.badge_outlined,
                                color: primaryColor,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        _buildRequiredTextField(
                          label: 'Phone',

                          controller: phoneController,

                          keyboardType: TextInputType.phone,

                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Phone is required';
                            }

                            final phone = value.trim();

                            final phoneRegex = RegExp(r'^[0-9]{10}$');

                            if (!phoneRegex.hasMatch(phone)) {
                              return 'Enter a valid 10-digit phone number';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 12),
                        // ======================================
                        // EMAIL
                        // ======================================
                        _buildRequiredTextField(
                          label: 'Email',

                          controller: emailController,

                          keyboardType: TextInputType.emailAddress,

                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Email is required';
                            }

                            final email = value.trim();

                            final emailRegex = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            );

                            if (!emailRegex.hasMatch(email)) {
                              return 'Enter a valid email address';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 12),

                        // ======================================
                        // COURSE DROPDOWN
                        // ======================================
                        DropdownButtonFormField<String>(
                          initialValue: selectedCourse,

                          dropdownColor: cardColor,

                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),

                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: textSecondary,
                          ),

                          decoration: InputDecoration(
                            labelText: 'Course',
                            hintText: 'Select Course',

                            labelStyle: const TextStyle(color: textSecondary),

                            hintStyle: const TextStyle(color: textSecondary),

                            filled: true,
                            fillColor: bgColor,

                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),

                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),

                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: primaryColor,
                                width: 1.5,
                              ),
                            ),

                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: errorColor),
                            ),

                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: errorColor,
                                width: 1.5,
                              ),
                            ),

                            errorStyle: const TextStyle(
                              color: errorColor,
                              fontSize: 12,
                            ),
                          ),

                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty ||
                                !courseOptions.contains(value)) {
                              return 'Course is required';
                            }

                            return null;
                          },

                          items: courseOptions
                              .map(
                                (course) => DropdownMenuItem<String>(
                                  value: course,
                                  child: Text(course),
                                ),
                              )
                              .toList(),

                          onChanged: saving
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedCourse = value;
                                  });
                                },
                        ),

                        const SizedBox(height: 12),

                        // ======================================
                        // GENDER
                        // ======================================
                        DropdownButtonFormField<String>(
                          initialValue: selectedGender,
                          dropdownColor: cardColor,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: textSecondary,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Gender',
                            hintText:
                                existingGender != null &&
                                    existingGender.isNotEmpty
                                ? existingGender
                                : 'Select Gender',
                            labelStyle: const TextStyle(color: textSecondary),
                            hintStyle: const TextStyle(color: textSecondary),
                            filled: true,
                            fillColor: bgColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: primaryColor,
                                width: 1.5,
                              ),
                            ),
                            errorStyle: const TextStyle(
                              color: errorColor,
                              fontSize: 12,
                            ),
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty ||
                                !genderOptions.contains(value)) {
                              return 'Gender is required';
                            }
                            return null;
                          },
                          items: genderOptions.map((gender) {
                            return DropdownMenuItem<String>(
                              value: gender,
                              child: Text(gender),
                            );
                          }).toList(),
                          onChanged: saving
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedGender = value;
                                  });
                                },
                        ),

                        const SizedBox(height: 12),

                        // ======================================
                        // GRADE
                        // ======================================
                        DropdownButtonFormField<String>(
                          initialValue: selectedGrade,
                          dropdownColor: cardColor,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: textSecondary,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Grade',
                            hintText:
                                existingGrade != null &&
                                    existingGrade.isNotEmpty
                                ? existingGrade
                                : 'Select Grade',
                            labelStyle: const TextStyle(color: textSecondary),
                            hintStyle: const TextStyle(color: textSecondary),
                            filled: true,
                            fillColor: bgColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: primaryColor,
                                width: 1.5,
                              ),
                            ),
                            errorStyle: const TextStyle(
                              color: errorColor,
                              fontSize: 12,
                            ),
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.trim().isEmpty ||
                                !gradeOptions.contains(value)) {
                              return 'Grade is required';
                            }
                            return null;
                          },
                          items: gradeOptions.map((grade) {
                            return DropdownMenuItem<String>(
                              value: grade,
                              child: Text(grade),
                            );
                          }).toList(),
                          onChanged: saving
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedGrade = value;
                                  });
                                },
                        ),

                        const SizedBox(height: 12),

                        // ======================================
                        // MONTHLY FEE
                        // ======================================
                        _buildRequiredTextField(
                          label: 'Monthly Fee',

                          controller: monthlyFeeController,

                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),

                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Monthly Fee is required';
                            }

                            final fee = double.tryParse(value.trim());

                            if (fee == null || fee <= 0) {
                              return 'Enter a valid fee amount';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),

              // ==================================================
              // ACTION BUTTONS
              // ==================================================
              actions: [
                // ------------------------------------------------
                // CANCEL
                // ------------------------------------------------
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },

                  child: const Text(
                    'Cancel',

                    style: TextStyle(color: textSecondary),
                  ),
                ),

                // ------------------------------------------------
                // SAVE
                // ------------------------------------------------
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,

                    foregroundColor: Colors.white,

                    minimumSize: const Size(90, 44),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  onPressed: saving ? null : saveStudent,

                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,

                          child: CircularProgressIndicator(
                            strokeWidth: 2,

                            color: Colors.white,
                          ),
                        )
                      : Text(isEditing ? 'Update' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // REQUIRED TEXT FIELD
  // ============================================================

  Widget _buildRequiredTextField({
    required String label,

    required TextEditingController controller,

    TextInputType keyboardType = TextInputType.text,

    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,

      keyboardType: keyboardType,

      style: const TextStyle(color: Colors.white),

      validator:
          validator ??
          (value) {
            if (value == null || value.trim().isEmpty) {
              return '$label is required';
            }

            return null;
          },

      decoration: InputDecoration(
        labelText: label,

        labelStyle: const TextStyle(color: textSecondary),

        filled: true,

        fillColor: bgColor,

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),

          borderSide: BorderSide.none,
        ),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),

          borderSide: BorderSide.none,
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),

          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),

        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),

          borderSide: const BorderSide(color: errorColor),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),

          borderSide: const BorderSide(color: errorColor, width: 1.5),
        ),

        errorStyle: const TextStyle(color: errorColor, fontSize: 12),
      ),
    );
  }

  // ============================================================
  // CREATE STUDENT FIREBASE AUTH ACCOUNT
  // ============================================================
  //
  // Uses a SECONDARY Firebase App so creating a student account
  // does NOT sign the Admin out.
  //
  // The Auth account and Firestore users/{uid} document are linked
  // using the same Firebase Authentication UID.
  // ============================================================

  Future<Map<String, String>> _createStudentAuthAccount({
    required String email,
  }) async {
    final String cleanEmail = email.trim();

    if (cleanEmail.isEmpty) {
      throw Exception('Student email is required.');
    }

    final String temporaryPassword = _generateTemporaryPassword();

    FirebaseApp? secondaryApp;
    FirebaseAuth? secondaryAuth;

    try {
      final FirebaseApp primaryApp = Firebase.app();

      secondaryApp = await Firebase.initializeApp(
        name: 'studentCreator_${DateTime.now().microsecondsSinceEpoch}',
        options: primaryApp.options,
      );

      secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      final UserCredential credential = await secondaryAuth
          .createUserWithEmailAndPassword(
            email: cleanEmail,
            password: temporaryPassword,
          );

      final User? studentUser = credential.user;

      if (studentUser == null) {
        throw Exception('Firebase did not return the student account.');
      }

      // Send Firebase's normal verification email.
      // NO Cloud Function is used.
      await studentUser.sendEmailVerification();

      return {'uid': studentUser.uid, 'temporaryPassword': temporaryPassword};
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          throw Exception('An account already exists with this email.');

        case 'invalid-email':
          throw Exception('The student email address is invalid.');

        case 'weak-password':
          throw Exception('The generated temporary password was rejected.');

        case 'operation-not-allowed':
          throw Exception(
            'Email/Password Authentication is not enabled in Firebase.',
          );

        case 'network-request-failed':
          throw Exception('Network error. Check your internet connection.');

        case 'too-many-requests':
          throw Exception('Too many requests. Please wait and try again.');

        default:
          throw Exception(e.message ?? 'Unable to create the student account.');
      }
    } finally {
      try {
        await secondaryAuth?.signOut();
      } catch (_) {}

      try {
        await secondaryApp?.delete();
      } catch (_) {}
    }
  }

  // ============================================================
  // SEND VERIFICATION MAIL
  // ============================================================
  //
  // NO Cloud Function.
  //
  // A secondary Firebase Auth instance is used so the Admin remains
  // signed in. The student Firebase Auth account is loaded by email
  // and a verification email is sent directly with Firebase Auth.
  //
  // IMPORTANT:
  // This requires the Firebase Auth SDK to be able to sign in to the
  // student's account. Since the Admin does not have the student's
  // password, the direct resend action cannot authenticate the
  // student's existing account using email alone.
  //
  // Therefore this method safely reports that limitation instead of
  // pretending to send an email.
  // ============================================================

  Future<void> _sendVerificationMail(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final String email = data['email']?.toString().trim() ?? '';

    final bool emailVerified = data['email_verified'] == true;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student email address is missing.')),
      );
      return;
    }

    if (emailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This student email is already verified.'),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: cardColor,
          title: const Text(
            'Send Verification Mail',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'The student is not verified yet.\n\n$email\n\n'
            'Firebase Auth does not allow the Admin client to resend '
            'the verification email for another existing account without '
            'authenticating as that student.',
            style: const TextStyle(color: textSecondary, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK', style: TextStyle(color: primaryColor)),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // GENERATE TEMPORARY PASSWORD
  // ============================================================

  String _generateTemporaryPassword() {
    const String characters =
        'ABCDEFGHJKLMNPQRSTUVWXYZ'
        'abcdefghijkmnopqrstuvwxyz'
        '23456789';

    final Random random = Random.secure();

    return List.generate(
      12,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }

  // ============================================================
  // SHOW TEMPORARY PASSWORD
  // ============================================================

  Future<void> _showTemporaryPasswordDialog(
    BuildContext context, {
    required String studentName,
    required String email,
    required String studentId,
    required String temporaryPassword,
  }) async {
    bool copied = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: cardColor,

              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: successColor, size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Student Created',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        studentName.isEmpty ? 'Student' : studentName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(email, style: const TextStyle(color: textSecondary)),

                      const SizedBox(height: 6),

                      Text(
                        'Student ID: $studentId',
                        style: const TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 24),

                      const Text(
                        'Temporary Password',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                temporaryPassword,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),

                            IconButton(
                              tooltip: 'Copy password',
                              icon: Icon(
                                copied ? Icons.check : Icons.content_copy,
                                color: copied ? successColor : primaryColor,
                              ),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: temporaryPassword),
                                );

                                setDialogState(() {
                                  copied = true;
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: warningColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: warningColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: warningColor,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Give this temporary password to the student. '
                                'The student must change it during the first login.',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'A verification email has been sent to the student.',
                        style: TextStyle(color: textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // GENERATE STUDENT ID
  // ============================================================
  String _generateStudentId() {
    final int year = DateTime.now().year;
    final Random random = Random();

    final int number = 100000 + random.nextInt(900000);

    return 'SZYD-STD-$year$number';
  }

  // ============================================================
  // STUDENT DETAILS
  // ============================================================

  void _showStudentDetailsModal(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final String firstName = (data['first_name'] ?? data['firstName'] ?? '')
        .toString()
        .trim();

    final String lastName = (data['last_name'] ?? data['lastName'] ?? '')
        .toString()
        .trim();

    final String profilePhoto =
        (data['profile_photo'] ?? data['profilePhoto'] ?? '').toString();

    final String fullName =
        (data['full_name'] ?? data['fullName'] ?? '$firstName $lastName')
            .toString()
            .trim();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: cardColor,
          title: Text(
            fullName.isEmpty ? 'Student Details' : fullName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (profilePhoto.isNotEmpty)
                    ClipOval(
                      child: Image.network(
                        profilePhoto,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const CircleAvatar(
                            radius: 50,
                            backgroundColor: primaryColor,
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 45,
                            ),
                          );
                        },
                      ),
                    )
                  else
                    const CircleAvatar(
                      radius: 50,
                      backgroundColor: primaryColor,
                      child: Icon(Icons.person, color: Colors.white, size: 45),
                    ),

                  const SizedBox(height: 20),

                  _detailRow('UID', data['uid']?.toString() ?? 'N/A'),

                  _detailRow(
                    'Student ID',
                    data['studentId']?.toString() ?? 'N/A',
                  ),

                  _detailRow('Email', data['email']?.toString() ?? 'N/A'),

                  _detailRow(
                    'Phone',
                    data['phone_number']?.toString() ??
                        data['phone']?.toString() ??
                        'N/A',
                  ),

                  _detailRow(
                    'Course',
                    data['preferred_instrument']?.toString() ??
                        data['course']?.toString() ??
                        'N/A',
                  ),

                  _detailRow('Gender', data['gender']?.toString() ?? 'N/A'),

                  _detailRow('Grade', data['grade']?.toString() ?? 'N/A'),

                  _detailRow(
                    'Monthly Fee',
                    data['monthlyFee']?.toString() ?? 'N/A',
                  ),

                  _detailRow(
                    'Fee Status',
                    data['feeStatus']?.toString() ?? 'Pending',
                  ),

                  _detailRow(
                    'Account Status',
                    data['is_active'] == true ||
                            data['accountStatus'] == 'Active'
                        ? 'Active'
                        : 'Inactive',
                  ),

                  _detailRow(
                    'Email Verified',
                    data['email_verified'] == true ? 'Yes' : 'No',
                  ),

                  _detailRow(
                    'Must Change Password',
                    data['must_change_password'] == true ? 'Yes' : 'No',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Close', style: TextStyle(color: primaryColor)),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // DETAIL ROW
  // ============================================================

  Widget _detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          SizedBox(
            width: 120,

            child: Text(
              '$label:',

              style: const TextStyle(
                color: textSecondary,

                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          Expanded(
            child: Text(
              value ?? 'N/A',

              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TOGGLE ACCOUNT STATUS
  // ============================================================

  void _confirmToggleAccountStatus(
    BuildContext context,
    String docId,
    String currentStatus,
  ) {
    final String newStatus = currentStatus == 'Active' ? 'Inactive' : 'Active';

    showDialog(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: cardColor,

          title: Text(
            '$newStatus Student',

            style: const TextStyle(color: Colors.white),
          ),

          content: Text(
            'Are you sure you want to change this student\'s account status to $newStatus?',

            style: const TextStyle(color: textSecondary),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },

              child: const Text(
                'Cancel',

                style: TextStyle(color: textSecondary),
              ),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: newStatus == 'Active'
                    ? successColor
                    : errorColor,
              ),

              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(docId)
                    .update({
                      'accountStatus': newStatus,
                      'is_active': newStatus == 'Active',
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },

              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // DELETE STUDENT
  // ============================================================

  Future<void> _showDeleteAccountDialog(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final String studentName =
        '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();

    final String studentId = data['studentId']?.toString().trim() ?? '';

    final bool? confirmed = await showDialog<bool>(
      context: context,

      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: cardColor,

          title: const Text(
            'Delete Account?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),

          content: Text(
            'Are you sure you want to delete '
            '${studentName.isEmpty ? 'this student' : studentName}\'s Firestore record?\n\n'
            'The student document and attendance records for this student '
            'will be deleted. The Firebase Authentication account remains '
            'and should be deactivated instead if login access must be blocked.\n\n'
            'This action cannot be undone.',

            style: const TextStyle(color: textSecondary),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },

              child: const Text(
                'Cancel',
                style: TextStyle(color: textSecondary),
              ),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: errorColor,
                foregroundColor: Colors.white,
              ),

              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },

              child: const Text('Delete Account'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    // Show a separate progress dialog so the admin cannot accidentally
    // trigger another delete while Firestore is removing the records.
    if (!context.mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (progressContext) {
        return const AlertDialog(
          backgroundColor: cardColor,
          content: Row(
            children: [
              CircularProgressIndicator(color: primaryColor),
              SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Deleting student and attendance records...',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      // ==========================================================
      // 1. FIND ALL ATTENDANCE RECORDS FOR THIS STUDENT
      // ==========================================================
      //
      // Your attendance documents contain both:
      //   studentUid
      //   studentId
      //
      // We check both fields so older and newer attendance records
      // are removed as well.
      //
      // docId is the Firestore document ID from the `user` collection,
      // which is also stored as `studentUid` in your attendance data.
      final Set<String> attendanceDocumentIds = <String>{};
      final List<DocumentReference<Map<String, dynamic>>> attendanceReferences =
          [];

      if (docId.trim().isNotEmpty) {
        final QuerySnapshot<Map<String, dynamic>> byStudentUid = await firestore
            .collection('attendance')
            .where('studentUid', isEqualTo: docId)
            .get();

        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in byStudentUid.docs) {
          if (attendanceDocumentIds.add(doc.id)) {
            attendanceReferences.add(doc.reference);
          }
        }
      }

      if (studentId.isNotEmpty) {
        final QuerySnapshot<Map<String, dynamic>> byStudentId = await firestore
            .collection('attendance')
            .where('studentId', isEqualTo: studentId)
            .get();

        for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
            in byStudentId.docs) {
          if (attendanceDocumentIds.add(doc.id)) {
            attendanceReferences.add(doc.reference);
          }
        }
      }

      // ==========================================================
      // 2. DELETE ATTENDANCE RECORDS
      // ==========================================================
      //
      // Firestore batches have a write limit. Delete in groups of
      // 450 so the code remains safe if a student has many records.
      const int batchLimit = 450;

      for (
        int start = 0;
        start < attendanceReferences.length;
        start += batchLimit
      ) {
        final int end = min(start + batchLimit, attendanceReferences.length);

        final WriteBatch batch = firestore.batch();

        for (final DocumentReference<Map<String, dynamic>> reference
            in attendanceReferences.sublist(start, end)) {
          batch.delete(reference);
        }

        await batch.commit();
      }

      // ==========================================================
      // 3. DELETE THE STUDENT FROM USER COLLECTION
      // ==========================================================
      await firestore.collection('users').doc(docId).delete();

      // ==========================================================
      // 4. CLOSE PROGRESS DIALOG
      // ==========================================================
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // ==========================================================
      // 5. SUCCESS MESSAGE
      // ==========================================================
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            attendanceReferences.isEmpty
                ? 'Student record deleted successfully.'
                : 'Student record and ${attendanceReferences.length} attendance record(s) deleted successfully.',
          ),
        ),
      );
    } catch (e) {
      // Close progress dialog if it is still open.
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete student and attendance records: $e'),
        ),
      );
    }
  }
}
