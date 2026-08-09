import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
// Reusing theme constants & colors

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
    return "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
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
          "Attendance Management",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: "Refresh Data",
            onPressed: () => setState(() {}),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('user').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                "Unable to load attendance records.",
                style: TextStyle(color: errorColor),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          int totalStudents = docs.length;

          // Compute summary stats based on live todayAttendance / status
          int presentCount = 0;
          int absentCount = 0;
          int pendingCount = 0;

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = (data['todayAttendance'] ?? 'Pending').toString();
            if (status == 'Present') {
              presentCount++;
            } else if (status == 'Absent') {
              absentCount++;
            } else {
              pendingCount++;
            }
          }

          double attendancePercentage = totalStudents > 0
              ? (presentCount / totalStudents) * 100
              : 0.0;

          // Extract courses for dynamic filtering
          Set<String> coursesSet = {'All'};
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final course = data['course']?.toString() ?? '';
            if (course.isNotEmpty) {
              coursesSet.add(course);
            }
          }
          List<String> availableCourses = coursesSet.toList();

          // Filter students locally for instant search and multi-filtering
          final filteredDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final firstName = (data['firstName'] ?? '')
                .toString()
                .toLowerCase();
            final lastName = (data['lastName'] ?? '').toString().toLowerCase();
            final fullName = '$firstName $lastName';
            final studentId = (data['studentId'] ?? '')
                .toString()
                .toLowerCase();
            final email = (data['email'] ?? '').toString().toLowerCase();
            final phone = (data['phone'] ?? '').toString().toLowerCase();
            final course = (data['course'] ?? '').toString();
            final status = (data['todayAttendance'] ?? 'Pending').toString();

            bool matchesSearch =
                _searchQuery.isEmpty ||
                fullName.contains(_searchQuery) ||
                studentId.contains(_searchQuery) ||
                email.contains(_searchQuery) ||
                phone.contains(_searchQuery);

            bool matchesStatus =
                _selectedStatusFilter == 'All' ||
                status == _selectedStatusFilter;
            bool matchesCourse =
                _selectedCourseFilter == 'All' ||
                course == _selectedCourseFilter;

            return matchesSearch && matchesStatus && matchesCourse;
          }).toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              bool isDesktop = constraints.maxWidth > 900;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Subtitle & Date Selector Toolbar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Manage and monitor daily student attendance.",
                          style: TextStyle(color: textSecondary, fontSize: 14),
                        ),
                        _buildDateSelector(),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Summary Cards Grid
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
                          "Total Students",
                          totalStudents.toString(),
                          primaryColor,
                          Icons.people,
                        ),
                        _buildStatCard(
                          "Present",
                          presentCount.toString(),
                          successColor,
                          Icons.check_circle,
                        ),
                        _buildStatCard(
                          "Absent",
                          absentCount.toString(),
                          errorColor,
                          Icons.cancel,
                        ),
                        _buildStatCard(
                          "Pending",
                          pendingCount.toString(),
                          warningColor,
                          Icons.pending,
                        ),
                        _buildStatCard(
                          "Attendance",
                          "${attendancePercentage.toStringAsFixed(1)}%",
                          primaryColor,
                          Icons.analytics,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Search and Filters
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: isDesktop ? 300 : double.infinity,
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.white),
                            onChanged: (val) => setState(
                              () => _searchQuery = val.trim().toLowerCase(),
                            ),
                            decoration: InputDecoration(
                              hintText: "Search student name, ID...",
                              hintStyle: const TextStyle(color: textSecondary),
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
                            ),
                          ),
                        ),
                        _buildDropdownFilter(
                          "Status",
                          _selectedStatusFilter,
                          ['All', 'Present', 'Absent', 'Pending'],
                          (val) => setState(() => _selectedStatusFilter = val!),
                        ),
                        _buildDropdownFilter(
                          "Course",
                          _selectedCourseFilter,
                          availableCourses,
                          (val) => setState(() => _selectedCourseFilter = val!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Attendance Table / List Container
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: filteredDocs.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(40.0),
                              child: Center(
                                child: Text(
                                  "No students match your search.",
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
                                final docId = doc.id;
                                final firstName = data['firstName'] ?? '';
                                final lastName = data['lastName'] ?? '';
                                final studentId = data['studentId'] ?? 'N/A';
                                final course = data['course'] ?? 'General';
                                final status =
                                    data['todayAttendance'] ?? 'Pending';
                                final presentDays = data['presentDays'] ?? 0;
                                final absentDays = data['absentDays'] ?? 0;
                                final profilePhoto = data['profilePhoto'] ?? '';

                                Color statusColor = status == 'Present'
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
                                    "$firstName $lastName",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "ID: $studentId • Course: $course • Present: $presentDays | Absent: $absentDays",
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
                                        onSelected: (newStatus) =>
                                            _updateAttendanceStatus(
                                              docId,
                                              data,
                                              newStatus,
                                            ),
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'Present',
                                            child: Text(
                                              "Mark Present",
                                              style: TextStyle(
                                                color: successColor,
                                              ),
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'Absent',
                                            child: Text(
                                              "Mark Absent",
                                              style: TextStyle(
                                                color: errorColor,
                                              ),
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'Pending',
                                            child: Text(
                                              "Mark Pending",
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
            onPressed: () => setState(() {
              _selectedDate = _selectedDate.subtract(const Duration(days: 1));
            }),
          ),
          InkWell(
            onTap: () async {
              DateTime? picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2025, 1, 1),
                lastDate: DateTime(2030, 12, 31),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
              }
            },
            child: Text(
              "${_selectedDate.day} ${_getMonthName(_selectedDate.month)}, ${_selectedDate.year}",
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
            onPressed: () => setState(() {
              _selectedDate = _selectedDate.add(const Duration(days: 1));
            }),
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
                    DropdownMenuItem(value: item, child: Text("$label: $item")),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> _updateAttendanceStatus(
    String docId,
    Map<String, dynamic> data,
    String newStatus,
  ) async {
    final String oldStatus = data['todayAttendance'] ?? 'Pending';
    if (oldStatus == newStatus) return; // No change needed

    int presentDays = data['presentDays'] ?? 0;
    int absentDays = data['absentDays'] ?? 0;

    // Smart counter adjustment preventing duplicate increments
    if (oldStatus == 'Present') {
      presentDays = (presentDays > 0) ? presentDays - 1 : 0;
    }
    if (oldStatus == 'Absent') {
      absentDays = (absentDays > 0) ? absentDays - 1 : 0;
    }

    if (newStatus == 'Present') presentDays++;
    if (newStatus == 'Absent') absentDays++;

    // Batch update user document and historical attendance collection
    final batch = FirebaseFirestore.instance.batch();

    final userRef = FirebaseFirestore.instance.collection('user').doc(docId);
    batch.update(userRef, {
      'todayAttendance': newStatus,
      'presentDays': presentDays,
      'absentDays': absentDays,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final historyRef = FirebaseFirestore.instance
        .collection('attendance')
        .doc('${_formattedDateKey}_$docId');
    batch.set(historyRef, {
      'studentUid': docId,
      'date': _formattedDateKey,
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }
}
