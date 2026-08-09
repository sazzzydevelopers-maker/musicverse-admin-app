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

  String _searchQuery = '';
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
    super.dispose();
  }

  String get _formattedDateKey {
    return '${_selectedDate.year}-'
        '${_selectedDate.month.toString().padLeft(2, '0')}-'
        '${_selectedDate.day.toString().padLeft(2, '0')}';
  }

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
      body: StreamBuilder<QuerySnapshot>(
        // IMPORTANT:
        // Attendance is now stored as ONE document per student.
        stream: FirebaseFirestore.instance.collection('attendance').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load attendance records.',
                style: TextStyle(color: errorColor),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          int totalStudents = docs.length;
          int presentCount = 0;
          int absentCount = 0;
          int pendingCount = 0;

          final List<String> availableCourseList = [];

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;

            final status = _statusForSelectedDate(data);

            if (status == 'Present') {
              presentCount++;
            } else if (status == 'Absent') {
              absentCount++;
            } else {
              pendingCount++;
            }

            final course = (data['course'] ?? '').toString().trim();
            if (course.isNotEmpty && !availableCourseList.contains(course)) {
              availableCourseList.add(course);
            }
          }

          availableCourseList.sort(
            (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
          );

          final List<String> availableCourses = ['All', ...availableCourseList];

          final double attendancePercentage = totalStudents > 0
              ? (presentCount / totalStudents) * 100
              : 0.0;

          final filteredDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;

            final studentName = (data['studentName'] ?? '')
                .toString()
                .toLowerCase();

            final firstName = (data['firstName'] ?? '')
                .toString()
                .toLowerCase();

            final lastName = (data['lastName'] ?? '').toString().toLowerCase();

            final studentId = (data['studentId'] ?? '')
                .toString()
                .toLowerCase();

            final email = (data['email'] ?? '').toString().toLowerCase();

            final phone = (data['phone'] ?? data['phoneNumber'] ?? '')
                .toString()
                .toLowerCase();

            final course = (data['course'] ?? '').toString();

            final status = _statusForSelectedDate(data);

            final fullName = '$firstName $lastName'.trim();

            final matchesSearch =
                _searchQuery.isEmpty ||
                studentName.contains(_searchQuery) ||
                fullName.contains(_searchQuery) ||
                studentId.contains(_searchQuery) ||
                email.contains(_searchQuery) ||
                phone.contains(_searchQuery) ||
                course.toLowerCase().contains(_searchQuery);

            final matchesStatus =
                _selectedStatusFilter == 'All' ||
                status == _selectedStatusFilter;

            final matchesCourse =
                _selectedCourseFilter == 'All' ||
                course == _selectedCourseFilter;

            return matchesSearch && matchesStatus && matchesCourse;
          }).toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final bool isDesktop = constraints.maxWidth > 900;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Manage and monitor daily student attendance.',
                          style: TextStyle(color: textSecondary, fontSize: 14),
                        ),
                        _buildDateSelector(),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // SUMMARY CARDS
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

                    // SEARCH + FILTERS
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: isDesktop ? 300 : double.infinity,
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.white),
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value.trim().toLowerCase();
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Search student name, ID...',
                              hintStyle: const TextStyle(color: textSecondary),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: textSecondary,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                        color: textSecondary,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchQuery = '';
                                        });
                                      },
                                    )
                                  : null,
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

                    // STUDENT LIST
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: filteredDocs.isEmpty
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
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filteredDocs.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                    color: Colors.white12,
                                    height: 1,
                                  ),
                              itemBuilder: (context, index) {
                                final doc = filteredDocs[index];
                                final data = doc.data() as Map<String, dynamic>;

                                final String studentName = _getStudentName(
                                  data,
                                );

                                final String studentId =
                                    (data['studentId'] ?? 'N/A').toString();

                                final String course =
                                    (data['course'] ?? 'General').toString();

                                final String status = _statusForSelectedDate(
                                  data,
                                );

                                final int presentDays = _toInt(
                                  data['presentDays'],
                                );

                                final int absentDays = _toInt(
                                  data['absentDays'],
                                );

                                final String profilePhoto =
                                    (data['profilePhoto'] ?? '').toString();

                                final Color statusColor = status == 'Present'
                                    ? successColor
                                    : (status == 'Absent'
                                          ? errorColor
                                          : warningColor);

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: profilePhoto.isNotEmpty
                                      ? CircleAvatar(
                                          backgroundImage: NetworkImage(
                                            profilePhoto,
                                          ),
                                        )
                                      : const CircleAvatar(
                                          backgroundColor: primaryColor,
                                          child: Icon(
                                            Icons.person,
                                            color: Colors.white,
                                          ),
                                        ),
                                  title: Text(
                                    studentName.isEmpty
                                        ? 'Unnamed Student'
                                        : studentName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'ID: $studentId • Course: $course • '
                                    'Present: $presentDays | '
                                    'Absent: $absentDays',
                                    style: const TextStyle(
                                      color: textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Chip(
                                        label: Text(
                                          status,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: statusColor.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      PopupMenuButton<String>(
                                        icon: const Icon(
                                          Icons.edit_calendar,
                                          color: textSecondary,
                                        ),
                                        color: cardColor,
                                        onSelected: (newStatus) {
                                          _updateAttendanceStatus(
                                            doc.id,
                                            data,
                                            newStatus,
                                          );
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'Present',
                                            child: Text(
                                              'Mark Present',
                                              style: TextStyle(
                                                color: successColor,
                                              ),
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'Absent',
                                            child: Text(
                                              'Mark Absent',
                                              style: TextStyle(
                                                color: errorColor,
                                              ),
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'Pending',
                                            child: Text(
                                              'Mark Pending',
                                              style: TextStyle(
                                                color: warningColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ATTENDANCE HELPERS
  // ---------------------------------------------------------------------------

  String _statusForSelectedDate(Map<String, dynamic> data) {
    final history = data['attendanceHistory'];

    if (history is Map) {
      final value = history[_formattedDateKey];

      if (value != null) {
        final status = value.toString().toLowerCase();

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

  String _getStudentName(Map<String, dynamic> data) {
    final studentName = (data['studentName'] ?? '').toString().trim();

    if (studentName.isNotEmpty) {
      return studentName;
    }

    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();

    return '$firstName $lastName'.trim();
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _calculatePercentage(int presentDays, int totalDays) {
    if (totalDays <= 0) {
      return 0.0;
    }

    return (presentDays / totalDays) * 100;
  }

  // ---------------------------------------------------------------------------
  // DATE SELECTOR
  // ---------------------------------------------------------------------------

  Widget _buildDateSelector() {
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
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 20),
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
            },
          ),
          InkWell(
            onTap: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2025, 1, 1),
                lastDate: DateTime(2030, 12, 31),
              );

              if (picked != null) {
                setState(() {
                  _selectedDate = picked;
                });
              }
            },
            child: Text(
              '${_selectedDate.day} '
              '${_getMonthName(_selectedDate.month)}, '
              '${_selectedDate.year}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.chevron_right,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.add(const Duration(days: 1));
              });
            },
          ),
        ],
      ),
    );
  }

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

  // ---------------------------------------------------------------------------
  // STAT CARD
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // DROPDOWN
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // UPDATE ONE STUDENT'S ATTENDANCE
  //
  // IMPORTANT:
  // There is ONE attendance document per student.
  //
  // Example:
  // attendance/studentUid_001
  //
  // attendanceHistory:
  // 2026-08-05: present
  // 2026-08-06: absent
  // 2026-08-08: present
  //
  // No new Firestore document is created for every day.
  // ---------------------------------------------------------------------------

  Future<void> _updateAttendanceStatus(
    String docId,
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

    // If a date already has a status, changing Present <-> Absent
    // must NOT increase totalDays again.
    final bool hadPreviousStatus =
        oldStatus == 'Present' || oldStatus == 'Absent';

    // Remove the previous status from the counters.
    if (oldStatus == 'Present') {
      if (presentDays > 0) {
        presentDays--;
      }
    } else if (oldStatus == 'Absent') {
      if (absentDays > 0) {
        absentDays--;
      }
    }

    // Apply the new status.
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
      // Pending means no attendance has been recorded for this date.
      // Therefore remove the date from attendanceHistory.
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

    final attendanceRef = FirebaseFirestore.instance
        .collection('attendance')
        .doc(docId);

    await attendanceRef.update({
      'presentDays': presentDays,
      'absentDays': absentDays,
      'totalDays': totalDays,
      'attendancePercentage': attendancePercentage,
      'attendanceHistory': history,
      'updatedAt': FieldValue.serverTimestamp(),
    });

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
