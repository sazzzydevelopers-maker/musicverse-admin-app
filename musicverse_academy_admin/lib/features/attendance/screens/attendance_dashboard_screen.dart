import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

class AttendanceDashboardScreen extends StatefulWidget {
  const AttendanceDashboardScreen({super.key});

  @override
  State<AttendanceDashboardScreen> createState() =>
      _AttendanceDashboardScreenState();
}

class _AttendanceDashboardScreenState extends State<AttendanceDashboardScreen> {
  DateTime _selectedDate = DateTime.now();

  final TextEditingController _searchController = TextEditingController();

  // ============================================================
  // SEARCH ONLY
  // ============================================================

  final FocusNode _searchFocusNode = FocusNode();

  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');

  String _selectedStatusFilter = 'All';
  String _selectedCourseFilter = 'All';

  // Theme Colors matching your project palette
  static const Color bgColor = Color(0xFF0D1020);
  static const Color cardColor = Color(0xFF171C35);
  static const Color primaryColor = Color(0xFF7C4DFF);
  static const Color successColor = Color(0xFF00E676);
  static const Color errorColor = Color(0xFFFF5252);
  static const Color warningColor = Color(0xFFFFC107);
  static const Color textSecondary = Color(0xFFB0B5D3);

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchQueryNotifier.dispose();
    super.dispose();
  }

  String get _formattedDateKey {
    return '${_selectedDate.year}-'
        '${_selectedDate.month.toString().padLeft(2, '0')}-'
        '${_selectedDate.day.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // STUDENT ACCOUNT STATUS
  //
  // Reads account status from USER collection.
  //
  // Main field:
  // is_active
  //
  // Also supports:
  // isActive
  // active
  // accountStatus
  // status
  //
  // If no account status field exists,
  // existing behavior remains Active.
  // ============================================================

  bool _isStudentActive(Map<String, dynamic> data) {
    final dynamic isActive = data['is_active'];

    if (isActive is bool) {
      return isActive;
    }

    final dynamic isActiveCamel = data['isActive'];

    if (isActiveCamel is bool) {
      return isActiveCamel;
    }

    final dynamic active = data['active'];

    if (active is bool) {
      return active;
    }

    final String accountStatus = (data['accountStatus'] ?? data['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (accountStatus == 'inactive') {
      return false;
    }

    if (accountStatus == 'active') {
      return true;
    }

    return true;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,

      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/dashboard'),
        ),

        title: const Text(
          'Attendance Management',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Data',
            onPressed: () => setState(() {}),
          ),
          const SizedBox(width: 8),
        ],
      ),

      // ============================================================
      // FIRST: READ ALL STUDENTS FROM USER COLLECTION
      // ============================================================
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),

        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }

          if (userSnapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load students.',
                style: TextStyle(color: errorColor),
              ),
            );
          }

          final userDocs = userSnapshot.data?.docs ?? [];

          // ============================================================
          // SECOND: READ ATTENDANCE COLLECTION
          // ============================================================

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('attendance')
                .snapshots(),

            builder: (context, attendanceSnapshot) {
              if (attendanceSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: primaryColor),
                );
              }

              if (attendanceSnapshot.hasError) {
                return const Center(
                  child: Text(
                    'Unable to load attendance records.',
                    style: TextStyle(color: errorColor),
                  ),
                );
              }

              final attendanceDocs = attendanceSnapshot.data?.docs ?? [];

              // ========================================================
              // CREATE ATTENDANCE LOOKUP
              // ========================================================

              final Map<String, QueryDocumentSnapshot> attendanceByStudentId =
                  {};

              for (final attendanceDoc in attendanceDocs) {
                final data = attendanceDoc.data() as Map<String, dynamic>;

                final String studentId = (data['studentId'] ?? '')
                    .toString()
                    .trim();

                if (studentId.isNotEmpty) {
                  attendanceByStudentId[studentId] = attendanceDoc;
                }
              }

              // ========================================================
              // MERGE USER + ATTENDANCE
              // ========================================================

              final List<Map<String, dynamic>> mergedStudents = [];

              for (final userDoc in userDocs) {
                final userData = userDoc.data() as Map<String, dynamic>;

                final String studentId = (userData['studentId'] ?? '')
                    .toString()
                    .trim();

                QueryDocumentSnapshot? attendanceDoc;

                if (studentId.isNotEmpty) {
                  attendanceDoc = attendanceByStudentId[studentId];
                }

                final Map<String, dynamic> mergedData =
                    Map<String, dynamic>.from(userData);

                // --------------------------------------------------------
                // USER DOCUMENT ID
                // --------------------------------------------------------

                mergedData['_userDocId'] = userDoc.id;

                // --------------------------------------------------------
                // ATTENDANCE DOCUMENT
                // --------------------------------------------------------

                if (attendanceDoc != null) {
                  final attendanceData =
                      attendanceDoc.data() as Map<String, dynamic>;

                  mergedData.addAll(attendanceData);

                  mergedData['_attendanceDocId'] = attendanceDoc.id;

                  mergedData['_hasAttendanceDocument'] = true;
                } else {
                  mergedData['_attendanceDocId'] = userDoc.id;

                  mergedData['_hasAttendanceDocument'] = false;

                  mergedData['presentDays'] = 0;

                  mergedData['absentDays'] = 0;

                  mergedData['totalDays'] = 0;

                  mergedData['attendancePercentage'] = 0.0;

                  mergedData['attendanceHistory'] = <String, dynamic>{};
                }

                // --------------------------------------------------------
                // ALWAYS USE LATEST STUDENT INFORMATION
                // --------------------------------------------------------

                mergedData['studentId'] =
                    userData['studentId'] ?? mergedData['studentId'] ?? '';

                mergedData['firstName'] =
                    userData['firstName'] ?? mergedData['firstName'] ?? '';

                mergedData['lastName'] =
                    userData['lastName'] ?? mergedData['lastName'] ?? '';

                mergedData['course'] =
                    userData['course'] ?? mergedData['course'] ?? '';

                mergedData['phone'] =
                    userData['phone'] ?? mergedData['phone'] ?? '';

                mergedData['email'] =
                    userData['email'] ?? mergedData['email'] ?? '';

                mergedData['profilePhoto'] =
                    userData['profilePhoto'] ??
                    mergedData['profilePhoto'] ??
                    '';

                // --------------------------------------------------------
                // KEEP USER ACCOUNT STATUS FROM USER DOCUMENT
                // --------------------------------------------------------

                if (userData.containsKey('is_active')) {
                  mergedData['is_active'] = userData['is_active'];
                }

                if (userData.containsKey('isActive')) {
                  mergedData['isActive'] = userData['isActive'];
                }

                if (userData.containsKey('active')) {
                  mergedData['active'] = userData['active'];
                }

                if (userData.containsKey('accountStatus')) {
                  mergedData['accountStatus'] = userData['accountStatus'];
                }

                if (userData.containsKey('status')) {
                  mergedData['status'] = userData['status'];
                }

                if ((mergedData['studentName'] ?? '')
                    .toString()
                    .trim()
                    .isEmpty) {
                  mergedData['studentName'] =
                      '${mergedData['firstName'] ?? ''} '
                              '${mergedData['lastName'] ?? ''}'
                          .trim();
                }

                mergedStudents.add(mergedData);
              }

              // ============================================================
              // STATISTICS
              // ============================================================

              final int totalStudents = mergedStudents.length;

              int presentCount = 0;
              int absentCount = 0;
              int pendingCount = 0;

              final List<String> availableCourseList = [];

              for (final data in mergedStudents) {
                final String status = _statusForSelectedDate(data);

                if (status == 'Present') {
                  presentCount++;
                } else if (status == 'Absent') {
                  absentCount++;
                } else {
                  pendingCount++;
                }

                final String course = (data['course'] ?? '').toString().trim();

                if (course.isNotEmpty &&
                    !availableCourseList.contains(course)) {
                  availableCourseList.add(course);
                }
              }

              availableCourseList.sort(
                (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
              );

              // ============================================================
              // COURSE LIST
              // ============================================================

              final List<String> availableCourses = [
                'All',
                'Piano',
                'Violin',
                'Guitar',
                'Drums',
                'Vocal',
                'Flute',
              ];

              final double attendancePercentage = totalStudents > 0
                  ? (presentCount / totalStudents) * 100
                  : 0.0;

              return LayoutBuilder(
                builder: (context, constraints) {
                  final bool isDesktop = constraints.maxWidth > 900;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        // ==================================================
                        // HEADER
                        // ==================================================
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            const SizedBox(
                              width: 360,
                              child: Text(
                                'Manage and monitor daily student attendance.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            _buildDateSelector(),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // ==================================================
                        // SUMMARY CARDS
                        // ==================================================
                        GridView.count(
                          crossAxisCount: constraints.maxWidth > 1200
                              ? 5
                              : (constraints.maxWidth > 700 ? 3 : 2),

                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,

                          shrinkWrap: true,

                          physics: const NeverScrollableScrollPhysics(),

                          childAspectRatio: 1.5,

                          children: [
                            _buildStatCard(
                              'Total Students',
                              totalStudents.toString(),
                              primaryColor,
                              Icons.people,
                            ),

                            _buildStatCard(
                              'Present',
                              presentCount.toString(),
                              successColor,
                              Icons.check_circle,
                            ),

                            _buildStatCard(
                              'Absent',
                              absentCount.toString(),
                              errorColor,
                              Icons.cancel,
                            ),

                            _buildStatCard(
                              'Pending',
                              pendingCount.toString(),
                              warningColor,
                              Icons.pending,
                            ),

                            _buildStatCard(
                              'Attendance',
                              '${attendancePercentage.toStringAsFixed(1)}%',
                              primaryColor,
                              Icons.analytics,
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
                              width: isDesktop
                                  ? 360
                                  : constraints.maxWidth - 48,

                              child: TextField(
                                controller: _searchController,

                                focusNode: _searchFocusNode,

                                style: const TextStyle(color: Colors.white),

                                onChanged: (value) {
                                  _searchQueryNotifier.value = value
                                      .trim()
                                      .toLowerCase();
                                },

                                decoration: InputDecoration(
                                  hintText: 'Search student name, ID...',

                                  hintStyle: const TextStyle(
                                    color: textSecondary,
                                  ),

                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: textSecondary,
                                  ),

                                  suffixIcon: ValueListenableBuilder<String>(
                                    valueListenable: _searchQueryNotifier,

                                    builder: (context, searchQuery, child) {
                                      if (searchQuery.isEmpty) {
                                        return const SizedBox.shrink();
                                      }

                                      return IconButton(
                                        icon: const Icon(
                                          Icons.clear,
                                          color: textSecondary,
                                        ),

                                        onPressed: () {
                                          _searchController.clear();

                                          _searchQueryNotifier.value = '';

                                          _searchFocusNode.requestFocus();
                                        },
                                      );
                                    },
                                  ),

                                  filled: true,

                                  fillColor: cardColor,

                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),

                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),

                            _buildDropdownFilter(
                              'Status',
                              _selectedStatusFilter,
                              const ['All', 'Present', 'Absent', 'Pending'],
                              (value) {
                                setState(() {
                                  _selectedStatusFilter = value ?? 'All';
                                });
                              },
                            ),

                            _buildDropdownFilter(
                              'Course',
                              _selectedCourseFilter,
                              availableCourses,
                              (value) {
                                setState(() {
                                  _selectedCourseFilter = value ?? 'All';
                                });
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // ==================================================
                        // STUDENT LIST
                        // ==================================================
                        ValueListenableBuilder<String>(
                          valueListenable: _searchQueryNotifier,

                          builder: (context, searchQuery, child) {
                            final filteredStudents = mergedStudents.where((
                              data,
                            ) {
                              final String studentName =
                                  (data['studentName'] ?? '')
                                      .toString()
                                      .toLowerCase();

                              final String firstName = (data['firstName'] ?? '')
                                  .toString()
                                  .toLowerCase();

                              final String lastName = (data['lastName'] ?? '')
                                  .toString()
                                  .toLowerCase();

                              final String studentId = (data['studentId'] ?? '')
                                  .toString()
                                  .toLowerCase();

                              final String email = (data['email'] ?? '')
                                  .toString()
                                  .toLowerCase();

                              final String phone =
                                  (data['phone'] ?? data['phoneNumber'] ?? '')
                                      .toString()
                                      .toLowerCase();

                              final String course = (data['course'] ?? '')
                                  .toString();

                              final String status = _statusForSelectedDate(
                                data,
                              );

                              final String fullName = '$firstName $lastName'
                                  .trim();

                              final bool matchesSearch =
                                  searchQuery.isEmpty ||
                                  studentName.contains(searchQuery) ||
                                  fullName.contains(searchQuery) ||
                                  studentId.contains(searchQuery) ||
                                  email.contains(searchQuery) ||
                                  phone.contains(searchQuery) ||
                                  course.toLowerCase().contains(searchQuery);

                              final bool matchesStatus =
                                  _selectedStatusFilter == 'All' ||
                                  status == _selectedStatusFilter;

                              final bool matchesCourse =
                                  _selectedCourseFilter == 'All' ||
                                  course.toLowerCase() ==
                                      _selectedCourseFilter.toLowerCase();

                              return matchesSearch &&
                                  matchesStatus &&
                                  matchesCourse;
                            }).toList();

                            // ==================================================
                            // STUDENT LIST UI
                            // ==================================================

                            return Container(
                              width: double.infinity,

                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),

                              child: filteredStudents.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.all(40),

                                      child: Center(
                                        child: Text(
                                          'No students match your search.',
                                          style: TextStyle(
                                            color: textSecondary,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,

                                      physics:
                                          const NeverScrollableScrollPhysics(),

                                      itemCount: filteredStudents.length,

                                      itemBuilder: (context, index) {
                                        final data = filteredStudents[index];

                                        final String studentName =
                                            _getStudentName(data);

                                        final String studentId =
                                            (data['studentId'] ?? 'N/A')
                                                .toString();

                                        final String course =
                                            (data['course'] ?? 'General')
                                                .toString();

                                        final String status =
                                            _statusForSelectedDate(data);

                                        // ==================================================
                                        // ACTIVE / INACTIVE
                                        // ==================================================

                                        final bool isStudentActive =
                                            _isStudentActive(data);

                                        final String accountStatus =
                                            isStudentActive
                                            ? 'Active'
                                            : 'Inactive';

                                        final int presentDays = _toInt(
                                          data['presentDays'],
                                        );

                                        final int absentDays = _toInt(
                                          data['absentDays'],
                                        );

                                        final String profilePhoto =
                                            (data['profilePhoto'] ?? '')
                                                .toString();

                                        final Color statusColor =
                                            status == 'Present'
                                            ? successColor
                                            : (status == 'Absent'
                                                  ? errorColor
                                                  : warningColor);

                                        final bool isWideStudentRow =
                                            constraints.maxWidth >= 900;

                                        final String phone =
                                            (data['phone'] ??
                                                    data['phoneNumber'] ??
                                                    'N/A')
                                                .toString();

                                        final String email =
                                            (data['email'] ?? '').toString();

                                        final double percentage =
                                            _calculatePercentage(
                                              presentDays,
                                              _toInt(data['totalDays']),
                                            );

                                        return _buildResponsiveStudentCard(
                                          data: data,
                                          studentName: studentName,
                                          studentId: studentId,
                                          course: course,
                                          phone: phone,
                                          email: email,
                                          status: status,
                                          accountStatus: accountStatus,
                                          isStudentActive: isStudentActive,
                                          profilePhoto: profilePhoto,
                                          statusColor: statusColor,
                                          presentDays: presentDays,
                                          absentDays: absentDays,
                                          percentage: percentage,
                                          isWide: isWideStudentRow,
                                        );
                                      },
                                    ),
                            );
                          },
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
  //
  // Existing attendance/database logic is unchanged.
  // Only the presentation changes:
  // large screens = horizontal row
  // small screens = stacked card
  // ============================================================

  Widget _buildResponsiveStudentCard({
    required Map<String, dynamic> data,
    required String studentName,
    required String studentId,
    required String course,
    required String phone,
    required String email,
    required String status,
    required String accountStatus,
    required bool isStudentActive,
    required String profilePhoto,
    required Color statusColor,
    required int presentDays,
    required int absentDays,
    required double percentage,
    required bool isWide,
  }) {
    final String selectedDateLabel =
        '${_selectedDate.day} ${_getMonthName(_selectedDate.month)} '
        '${_selectedDate.year}';

    final IconData attendanceIcon = status == 'Present'
        ? Icons.check_circle_rounded
        : status == 'Absent'
        ? Icons.cancel_rounded
        : Icons.pending_rounded;

    final Widget avatar = profilePhoto.isNotEmpty
        ? CircleAvatar(radius: 30, backgroundImage: NetworkImage(profilePhoto))
        : const CircleAvatar(
            radius: 30,
            backgroundColor: primaryColor,
            child: Icon(Icons.person_rounded, color: Colors.white, size: 31),
          );

    final Widget header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        avatar,
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                studentName.isEmpty ? 'Unnamed Student' : studentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                studentId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: isStudentActive
              ? 'Change attendance'
              : 'Inactive student - attendance locked',
          icon: Icon(
            isStudentActive ? Icons.more_vert_rounded : Icons.lock_rounded,
            color: isStudentActive ? textSecondary : errorColor,
            size: 25,
          ),
          onPressed: isStudentActive
              ? () {
                  _showAttendanceChangeDialog(data, status);
                }
              : null,
        ),
      ],
    );

    final Widget details = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildMiniInfoChip(
          Icons.music_note_rounded,
          course.isEmpty ? 'Course not set' : course,
          primaryColor,
        ),
        _buildMiniInfoChip(
          Icons.phone_rounded,
          phone.isEmpty ? 'Phone not set' : phone,
          textSecondary,
        ),
        if (email.trim().isNotEmpty)
          _buildMiniInfoChip(Icons.email_outlined, email, textSecondary),
      ],
    );

    final Widget dateChip = _buildMiniInfoChip(
      Icons.calendar_month_rounded,
      selectedDateLabel,
      primaryColor,
    );

    final Widget attendanceBanner = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(attendanceIcon, color: statusColor, size: 21),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Attendance: $status',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: statusColor,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (isStudentActive)
            TextButton(
              onPressed: () {
                _showAttendanceChangeDialog(data, status);
              },
              style: TextButton.styleFrom(
                foregroundColor: statusColor,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Edit',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          else
            const Text(
              'Locked',
              style: TextStyle(
                color: errorColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );

    final Widget accountBadge = _buildStatusBadge(
      accountStatus,
      isStudentActive ? successColor : errorColor,
      isStudentActive ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
    );

    final Widget statistics = Row(
      children: [
        Expanded(
          child: _buildAttendanceMetric(
            'Present',
            presentDays.toString(),
            successColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildAttendanceMetric(
            'Absent',
            absentDays.toString(),
            errorColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildAttendanceMetric(
            'Percentage',
            '${percentage.toStringAsFixed(1)}%',
            primaryColor,
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 15),
          details,
          const SizedBox(height: 10),
          dateChip,
          const SizedBox(height: 14),
          attendanceBanner,
          const SizedBox(height: 12),
          if (isWide)
            Row(
              children: [
                Expanded(child: statistics),
                const SizedBox(width: 12),
                accountBadge,
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [statistics, const SizedBox(height: 10), accountBadge],
            ),
        ],
      ),
    );
  }

  Widget _buildAttendanceMetric(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
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

  // ============================================================
  // ATTENDANCE STATUS FOR SELECTED DATE
  // ============================================================

  String _statusForSelectedDate(Map<String, dynamic> data) {
    final dynamic historyData = data['attendanceHistory'];

    if (historyData is Map) {
      final dynamic value = historyData[_formattedDateKey];

      if (value != null) {
        final String status = value.toString().toLowerCase();

        if (status == 'present') {
          return 'Present';
        }

        if (status == 'absent') {
          return 'Absent';
        }
      }
    }

    return 'Pending';
  }

  // ============================================================
  // GET STUDENT NAME
  // ============================================================

  String _getStudentName(Map<String, dynamic> data) {
    final String studentName = (data['studentName'] ?? '').toString().trim();

    if (studentName.isNotEmpty) {
      return studentName;
    }

    final String firstName = (data['firstName'] ?? '').toString().trim();

    final String lastName = (data['lastName'] ?? '').toString().trim();

    return '$firstName $lastName'.trim();
  }

  // ============================================================
  // NUMBER CONVERSION
  // ============================================================

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // ============================================================
  // CALCULATE ATTENDANCE %
  // ============================================================

  double _calculatePercentage(int presentDays, int totalDays) {
    if (totalDays <= 0) {
      return 0.0;
    }

    return (presentDays / totalDays) * 100;
  }

  // ============================================================
  // DATE SELECTOR
  // ============================================================

  Widget _buildDateSelector() {
    final DateTime today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    final DateTime selectedDateOnly = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    final bool isToday = selectedDateOnly == today;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius: BorderRadius.circular(8),

        border: Border.all(color: primaryColor.withValues(alpha: 0.4)),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          // ========================================================
          // PREVIOUS DAY
          // ========================================================
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 20),

            onPressed: () {
              setState(() {
                _selectedDate = selectedDateOnly.subtract(
                  const Duration(days: 1),
                );
              });
            },
          ),

          // ========================================================
          // DATE
          // ========================================================
          InkWell(
            onTap: () async {
              final DateTime? picked = await showDatePicker(
                context: context,

                initialDate: selectedDateOnly.isAfter(today)
                    ? today
                    : selectedDateOnly,

                firstDate: DateTime(2025, 1, 1),

                lastDate: today,
              );

              if (picked != null) {
                if (picked.isAfter(today)) {
                  return;
                }

                setState(() {
                  _selectedDate = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                  );
                });
              }
            },

            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                '${selectedDateOnly.day} '
                '${_getMonthName(selectedDateOnly.month)}, '
                '${selectedDateOnly.year}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // ========================================================
          // NEXT DAY
          // ========================================================
          IconButton(
            icon: Icon(
              Icons.chevron_right,

              color: isToday ? Colors.white24 : Colors.white,

              size: 20,
            ),

            onPressed: isToday
                ? null
                : () {
                    final DateTime nextDate = selectedDateOnly.add(
                      const Duration(days: 1),
                    );

                    if (nextDate.isAfter(today)) {
                      return;
                    }

                    setState(() {
                      _selectedDate = nextDate;
                    });
                  },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MONTH
  // ============================================================

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return months[month - 1];
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
  // DROPDOWN
  // ============================================================

  Widget _buildDropdownFilter(
    String label,
    String currentVal,
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
          value: items.contains(currentVal) ? currentVal : items.first,

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
  // ATTENDANCE CHANGE POPUP
  // ============================================================

  Future<void> _showAttendanceChangeDialog(
    Map<String, dynamic> data,
    String currentStatus,
  ) async {
    String selectedStatus = currentStatus;

    final String studentName = _getStudentName(data).isEmpty
        ? 'Unnamed Student'
        : _getStudentName(data);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,

      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final Color selectedColor = selectedStatus == 'Present'
                ? successColor
                : selectedStatus == 'Absent'
                ? errorColor
                : warningColor;

            return AlertDialog(
              backgroundColor: cardColor,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),

              title: const Text(
                'Change Attendance',

                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),

              content: Column(
                mainAxisSize: MainAxisSize.min,

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    studentName,

                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    'Current status: $currentStatus',

                    style: const TextStyle(color: textSecondary, fontSize: 12),
                  ),

                  const SizedBox(height: 18),

                  _attendanceDialogOption(
                    'Present',
                    Icons.check_circle_rounded,
                    successColor,
                    selectedStatus == 'Present',
                    () {
                      setDialogState(() {
                        selectedStatus = 'Present';
                      });
                    },
                  ),

                  const SizedBox(height: 8),

                  _attendanceDialogOption(
                    'Absent',
                    Icons.cancel_rounded,
                    errorColor,
                    selectedStatus == 'Absent',
                    () {
                      setDialogState(() {
                        selectedStatus = 'Absent';
                      });
                    },
                  ),

                  const SizedBox(height: 8),

                  _attendanceDialogOption(
                    'Pending',
                    Icons.pending_rounded,
                    warningColor,
                    selectedStatus == 'Pending',
                    () {
                      setDialogState(() {
                        selectedStatus = 'Pending';
                      });
                    },
                  ),
                ],
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
                    backgroundColor: selectedStatus == currentStatus
                        ? Colors.white24
                        : selectedColor,

                    foregroundColor: Colors.white,
                  ),

                  onPressed: selectedStatus == currentStatus
                      ? null
                      : () async {
                          Navigator.of(dialogContext).pop();

                          await _updateAttendanceStatus(data, selectedStatus);
                        },

                  child: Text(
                    selectedStatus == currentStatus
                        ? 'No Change'
                        : 'Update $selectedStatus',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // ATTENDANCE DIALOG OPTION
  // ============================================================

  Widget _attendanceDialogOption(
    String label,
    IconData icon,
    Color color,
    bool selected,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(10),

      child: Container(
        width: double.infinity,

        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),

        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : Colors.white10,

          borderRadius: BorderRadius.circular(10),

          border: Border.all(color: selected ? color : Colors.white12),
        ),

        child: Row(
          children: [
            Icon(icon, color: selected ? color : textSecondary, size: 20),

            const SizedBox(width: 10),

            Expanded(
              child: Text(
                label,

                style: TextStyle(
                  color: selected ? Colors.white : textSecondary,

                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,

              color: selected ? color : textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // UPDATE ATTENDANCE
  // ============================================================

  Future<void> _updateAttendanceStatus(
    Map<String, dynamic> data,
    String newStatus,
  ) async {
    final String dateKey = _formattedDateKey;

    final dynamic historyData = data['attendanceHistory'];

    final Map<String, dynamic> history = historyData is Map
        ? Map<String, dynamic>.from(historyData)
        : <String, dynamic>{};

    final String oldStatus = _statusForSelectedDate(data);

    if (oldStatus == newStatus) {
      return;
    }

    int presentDays = _toInt(data['presentDays']);

    int absentDays = _toInt(data['absentDays']);

    int totalDays = _toInt(data['totalDays']);

    final bool hadPreviousStatus =
        oldStatus == 'Present' || oldStatus == 'Absent';

    // ==========================================================
    // REMOVE OLD STATUS
    // ==========================================================

    if (oldStatus == 'Present') {
      if (presentDays > 0) {
        presentDays--;
      }
    } else if (oldStatus == 'Absent') {
      if (absentDays > 0) {
        absentDays--;
      }
    }

    // ==========================================================
    // APPLY NEW STATUS
    // ==========================================================

    if (newStatus == 'Present') {
      presentDays++;

      if (!hadPreviousStatus) {
        totalDays++;
      }

      history[dateKey] = 'present';
    } else if (newStatus == 'Absent') {
      absentDays++;

      if (!hadPreviousStatus) {
        totalDays++;
      }

      history[dateKey] = 'absent';
    } else {
      history.remove(dateKey);

      if (hadPreviousStatus && totalDays > 0) {
        totalDays--;
      }
    }

    if (totalDays < 0) {
      totalDays = 0;
    }

    final double attendancePercentage = _calculatePercentage(
      presentDays,
      totalDays,
    );

    // ==========================================================
    // ATTENDANCE DOCUMENT ID
    // ==========================================================

    final String attendanceDocId =
        (data['_attendanceDocId'] ?? data['_userDocId']).toString();

    final bool hasAttendanceDocument = data['_hasAttendanceDocument'] == true;

    final String studentName = _getStudentName(data);

    final String studentId = (data['studentId'] ?? '').toString();

    final String course = (data['course'] ?? '').toString();

    final String userDocId = (data['_userDocId'] ?? '').toString();

    final DocumentReference attendanceRef = FirebaseFirestore.instance
        .collection('attendance')
        .doc(attendanceDocId);

    // ==========================================================
    // DATA TO SAVE
    // ==========================================================

    final Map<String, dynamic> attendanceData = {
      'studentName': studentName,

      'studentId': studentId,

      'course': course,

      'studentUid': userDocId,

      'presentDays': presentDays,

      'absentDays': absentDays,

      'totalDays': totalDays,

      'attendancePercentage': attendancePercentage,

      'attendanceHistory': history,

      'updatedAt': FieldValue.serverTimestamp(),
    };

    // ==========================================================
    // CREATE OR UPDATE
    // ==========================================================

    if (hasAttendanceDocument) {
      await attendanceRef.update(attendanceData);
    } else {
      await attendanceRef.set({
        ...attendanceData,

        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (!mounted) {
      return;
    }

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newStatus == 'Pending'
              ? 'Attendance removed for $dateKey.'
              : 'Attendance marked $newStatus for $dateKey.',
        ),

        backgroundColor: newStatus == 'Present'
            ? successColor
            : (newStatus == 'Absent' ? errorColor : warningColor),
      ),
    );
  }
}
