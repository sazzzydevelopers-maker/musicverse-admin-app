import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
// Reusing App Colors/Theme constants if needed

class StudentManagementScreen extends StatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedAccountStatus = 'All';
  String _selectedFeeStatus = 'All';
  String _selectedCourse = 'All';

  // Theme Colors matching your MusicVerse Academy design
  static const Color bgColor = Color(0xFF0D1020);
  static const Color cardColor = Color(0xFF171C35);
  static const Color primaryColor = Color(0xFF7C4DFF);
  static const Color secondaryColor = Color(0xFF9D6BFF);
  static const Color successColor = Color(0xFF00E676);
  static const Color errorColor = Color(0xFFFF5252);
  static const Color warningColor = Color(0xFFFFC107);
  static const Color textSecondary = Color(0xFFB0B5D3);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
          "Student Management",
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
            label: const Text("Add Student"),
            onPressed: () => _showAddOrEditStudentDialog(context),
          ),
          const SizedBox(width: 16),
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
                "Unable to load students.",
                style: TextStyle(color: errorColor),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          // Calculate Statistics dynamically
          int totalStudents = docs.length;
          int activeStudents = docs
              .where(
                (d) =>
                    (d.data() as Map<String, dynamic>)['accountStatus'] ==
                    'Active',
              )
              .length;
          int inactiveStudents = totalStudents - activeStudents;
          int paidStudents = docs
              .where(
                (d) =>
                    (d.data() as Map<String, dynamic>)['feeStatus'] == 'Paid',
              )
              .length;
          int pendingFees = totalStudents - paidStudents;

          // Extract dynamic courses for filter dropdown
          Set<String> coursesSet = {'All'};
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['course'] != null &&
                data['course'].toString().isNotEmpty) {
              coursesSet.add(data['course'].toString());
            }
          }
          List<String> availableCourses = coursesSet.toList();

          // Filter documents locally for fast responsive search & filtering
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

            final accountStatus = data['accountStatus'] ?? 'Inactive';
            final feeStatus = data['feeStatus'] ?? 'Pending';
            final course = data['course'] ?? '';

            // Search query match
            bool matchesSearch =
                _searchQuery.isEmpty ||
                fullName.contains(_searchQuery) ||
                studentId.contains(_searchQuery) ||
                email.contains(_searchQuery) ||
                phone.contains(_searchQuery);

            // Filters match
            bool matchesAccount =
                _selectedAccountStatus == 'All' ||
                accountStatus == _selectedAccountStatus;
            bool matchesFee =
                _selectedFeeStatus == 'All' || feeStatus == _selectedFeeStatus;
            bool matchesCourse =
                _selectedCourse == 'All' || course == _selectedCourse;

            return matchesSearch &&
                matchesAccount &&
                matchesFee &&
                matchesCourse;
          }).toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              bool isDesktop = constraints.maxWidth > 900;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Subtitle
                    const Text(
                      "Manage and monitor all MusicVerse Academy students.",
                      style: TextStyle(color: textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 20),

                    // Statistics Cards Grid
                    GridView.count(
                      crossAxisCount: constraints.maxWidth > 1200
                          ? 5
                          : (constraints.maxWidth > 700 ? 3 : 2),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.6,
                      children: [
                        _buildStatCard(
                          "Total Students",
                          totalStudents.toString(),
                          primaryColor,
                          Icons.people,
                        ),
                        _buildStatCard(
                          "Active Students",
                          activeStudents.toString(),
                          successColor,
                          Icons.check_circle,
                        ),
                        _buildStatCard(
                          "Inactive Students",
                          inactiveStudents.toString(),
                          errorColor,
                          Icons.cancel,
                        ),
                        _buildStatCard(
                          "Paid Students",
                          paidStudents.toString(),
                          secondaryColor,
                          Icons.payment,
                        ),
                        _buildStatCard(
                          "Pending Fees",
                          pendingFees.toString(),
                          warningColor,
                          Icons.pending,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Search and Filter Toolbar
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
                              hintText: "Search students...",
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
                          "Account",
                          _selectedAccountStatus,
                          ['All', 'Active', 'Inactive'],
                          (val) =>
                              setState(() => _selectedAccountStatus = val!),
                        ),
                        _buildDropdownFilter(
                          "Fee",
                          _selectedFeeStatus,
                          ['All', 'Paid', 'Pending'],
                          (val) => setState(() => _selectedFeeStatus = val!),
                        ),
                        _buildDropdownFilter(
                          "Course",
                          _selectedCourse,
                          availableCourses,
                          (val) => setState(() => _selectedCourse = val!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Students Table / List Container
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
                                  "No students found",
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
                                final phone = data['phone'] ?? 'N/A';
                                final feeStatus =
                                    data['feeStatus'] ?? 'Pending';
                                final accountStatus =
                                    data['accountStatus'] ?? 'Inactive';
                                final profilePhoto = data['profilePhoto'] ?? '';

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
                                    "ID: $studentId • Course: $course • Phone: $phone",
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
                                          feeStatus,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: feeStatus == 'Paid'
                                            ? successColor.withValues(
                                                alpha: 0.2,
                                              )
                                            : errorColor.withValues(alpha: 0.2),
                                      ),
                                      const SizedBox(width: 8),
                                      Chip(
                                        label: Text(
                                          accountStatus,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor:
                                            accountStatus == 'Active'
                                            ? primaryColor.withValues(
                                                alpha: 0.2,
                                              )
                                            : Colors.grey.withValues(
                                                alpha: 0.2,
                                              ),
                                      ),
                                      const SizedBox(width: 8),
                                      PopupMenuButton<String>(
                                        icon: const Icon(
                                          Icons.more_vert,
                                          color: textSecondary,
                                        ),
                                        color: cardColor,
                                        onSelected: (value) {
                                          if (value == 'view') {
                                            _showStudentDetailsModal(
                                              context,
                                              data,
                                            );
                                          } else if (value == 'edit') {
                                            _showAddOrEditStudentDialog(
                                              context,
                                              docId: docId,
                                              existingData: data,
                                            );
                                          } else if (value == 'toggle') {
                                            _confirmToggleAccountStatus(
                                              context,
                                              docId,
                                              accountStatus,
                                            );
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'view',
                                            child: Text(
                                              "View Details",
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Text(
                                              "Edit Student",
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'toggle',
                                            child: Text(
                                              accountStatus == 'Active'
                                                  ? "Deactivate"
                                                  : "Activate",
                                              style: TextStyle(
                                                color: accountStatus == 'Active'
                                                    ? errorColor
                                                    : successColor,
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

  void _showStudentDetailsModal(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: Text(
          "${data['firstName']} ${data['lastName']}",
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow("Student ID", data['studentId']),
                _detailRow("Email", data['email']),
                _detailRow("Phone", data['phone']),
                _detailRow("Course", data['course']),
                _detailRow("Gender", data['gender']),
                _detailRow("Date of Birth", data['dateOfBirth']),
                _detailRow("Address", data['address']),
                _detailRow("Monthly Fee", data['monthlyFee']?.toString()),
                _detailRow("Fee Status", data['feeStatus']),
                _detailRow("Account Status", data['accountStatus']),
                _detailRow("Present Days", data['presentDays']?.toString()),
                _detailRow("Absent Days", data['absentDays']?.toString()),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Close", style: TextStyle(color: primaryColor)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              "$label:",
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

  void _confirmToggleAccountStatus(
    BuildContext context,
    String docId,
    String currentStatus,
  ) {
    String newStatus = currentStatus == 'Active' ? 'Inactive' : 'Active';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: Text(
          "$newStatus Student",
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          "Are you sure you want to change this student's account status to $newStatus?",
          style: const TextStyle(color: textSecondary),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel", style: TextStyle(color: textSecondary)),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'Active'
                  ? successColor
                  : errorColor,
            ),
            child: const Text("Confirm"),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('user')
                  .doc(docId)
                  .update({
                    'accountStatus': newStatus,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showAddOrEditStudentDialog(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? existingData,
  }) {
    final bool isEditing = docId != null;
    final firstNameController = TextEditingController(
      text: existingData?['firstName'] ?? '',
    );
    final lastNameController = TextEditingController(
      text: existingData?['lastName'] ?? '',
    );
    final emailController = TextEditingController(
      text: existingData?['email'] ?? '',
    );
    final phoneController = TextEditingController(
      text: existingData?['phone'] ?? '',
    );
    final courseController = TextEditingController(
      text: existingData?['course'] ?? '',
    );
    final monthlyFeeController = TextEditingController(
      text: existingData?['monthlyFee']?.toString() ?? '1000',
    );
    final studentIdController = TextEditingController(
      text:
          existingData?['studentId'] ??
          'STU-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: Text(
          isEditing ? "Edit Student" : "Add New Student",
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField("First Name", firstNameController),
                const SizedBox(height: 12),
                _buildTextField("Last Name", lastNameController),
                const SizedBox(height: 12),
                _buildTextField("Student ID", studentIdController),
                const SizedBox(height: 12),
                _buildTextField("Email", emailController),
                const SizedBox(height: 12),
                _buildTextField("Phone", phoneController),
                const SizedBox(height: 12),
                _buildTextField(
                  "Course (e.g. Advanced Piano)",
                  courseController,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  "Monthly Fee",
                  monthlyFeeController,
                  isNumber: true,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel", style: TextStyle(color: textSecondary)),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            child: Text(isEditing ? "Update" : "Save"),
            onPressed: () async {
              final Map<String, dynamic> studentData = {
                'firstName': firstNameController.text.trim(),
                'lastName': lastNameController.text.trim(),
                'studentId': studentIdController.text.trim(),
                'email': emailController.text.trim(),
                'phone': phoneController.text.trim(),
                'course': courseController.text.trim(),
                'monthlyFee':
                    double.tryParse(monthlyFeeController.text.trim()) ?? 1000.0,
                'feeStatus': existingData?['feeStatus'] ?? 'Pending',
                'accountStatus': existingData?['accountStatus'] ?? 'Active',
                'updatedAt': FieldValue.serverTimestamp(),
              };

              if (!isEditing) {
                studentData['createdAt'] = FieldValue.serverTimestamp();
                studentData['presentDays'] = 0;
                studentData['absentDays'] = 0;
                studentData['todayAttendance'] = 'Pending';
                studentData['practiceProgress'] = 0;
                studentData['profilePhoto'] = '';
                studentData['gender'] = 'Not Specified';
                studentData['dateOfBirth'] = '2010-01-01';
                studentData['address'] = 'Hyderabad';

                await FirebaseFirestore.instance
                    .collection('user')
                    .add(studentData);
              } else {
                await FirebaseFirestore.instance
                    .collection('user')
                    .doc(docId)
                    .update(studentData);
              }

              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: textSecondary),
        filled: true,
        fillColor: bgColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
