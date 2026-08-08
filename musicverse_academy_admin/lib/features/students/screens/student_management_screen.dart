import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
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
                'Unable to load students.',
                style: TextStyle(color: errorColor),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          // ======================================================
          // STATISTICS
          // ======================================================

          final int totalStudents = docs.length;

          final int activeStudents = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;

            return data['accountStatus'] == 'Active';
          }).length;

          final int inactiveStudents = totalStudents - activeStudents;

          final int paidStudents = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;

            return data['feeStatus'] == 'Paid';
          }).length;

          final int pendingFees = totalStudents - paidStudents;

          // ======================================================
          // COURSES
          // ======================================================

          final Set<String> coursesSet = {'All'};

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;

            final course = data['course'];

            if (course != null && course.toString().trim().isNotEmpty) {
              coursesSet.add(course.toString());
            }
          }

          final List<String> availableCourses = coursesSet.toList();

          // ======================================================
          // FILTER
          // ======================================================

          final filteredDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;

            final firstName = (data['firstName'] ?? '')
                .toString()
                .toLowerCase();

            final lastName = (data['lastName'] ?? '').toString().toLowerCase();

            final studentId = (data['studentId'] ?? '')
                .toString()
                .toLowerCase();

            final email = (data['email'] ?? '').toString().toLowerCase();

            final phone = (data['phone'] ?? '').toString().toLowerCase();

            final fullName = '$firstName $lastName';

            final accountStatus = data['accountStatus'] ?? 'Inactive';

            final feeStatus = data['feeStatus'] ?? 'Pending';

            final course = data['course'] ?? '';

            final bool matchesSearch =
                _searchQuery.isEmpty ||
                fullName.contains(_searchQuery) ||
                studentId.contains(_searchQuery) ||
                email.contains(_searchQuery) ||
                phone.contains(_searchQuery);

            final bool matchesAccount =
                _selectedAccountStatus == 'All' ||
                accountStatus == _selectedAccountStatus;

            final bool matchesFee =
                _selectedFeeStatus == 'All' || feeStatus == _selectedFeeStatus;

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

                            style: const TextStyle(color: Colors.white),

                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value.trim().toLowerCase();
                              });
                            },

                            decoration: InputDecoration(
                              hintText: 'Search students...',

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
                        borderRadius: BorderRadius.circular(12),
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

                              itemCount: filteredDocs.length,

                              separatorBuilder: (context, index) {
                                return const Divider(
                                  color: Colors.white12,
                                  height: 1,
                                );
                              },

                              itemBuilder: (context, index) {
                                final doc = filteredDocs[index];

                                final data = doc.data() as Map<String, dynamic>;

                                final String docId = doc.id;

                                final String firstName =
                                    data['firstName']?.toString() ?? '';

                                final String lastName =
                                    data['lastName']?.toString() ?? '';

                                final String studentId =
                                    data['studentId']?.toString() ?? 'N/A';

                                final String course =
                                    data['course']?.toString() ?? 'General';

                                final String phone =
                                    data['phone']?.toString() ?? 'N/A';

                                final String feeStatus =
                                    data['feeStatus']?.toString() ?? 'Pending';

                                final String accountStatus =
                                    data['accountStatus']?.toString() ??
                                    'Inactive';

                                final String profilePhoto =
                                    data['profilePhoto']?.toString() ?? '';

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),

                                  // ==================================================
                                  // PROFILE PHOTO
                                  // ==================================================
                                  leading: _buildProfileAvatar(
                                    profilePhoto,
                                    firstName,
                                    lastName,
                                  ),

                                  title: Text(
                                    '$firstName $lastName',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  subtitle: Text(
                                    'ID: $studentId • Course: $course • Phone: $phone',
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
                                          }

                                          if (value == 'edit') {
                                            _showAddOrEditStudentDialog(
                                              context,
                                              docId: docId,
                                              existingData: data,
                                            );
                                          }

                                          if (value == 'toggle') {
                                            _confirmToggleAccountStatus(
                                              context,
                                              docId,
                                              accountStatus,
                                            );
                                          }

                                          if (value == 'delete') {
                                            _showDeleteAccountDialog(
                                              context,
                                              docId,
                                              data,
                                            );
                                          }
                                        },

                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'view',
                                            child: Text(
                                              'View Details',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),

                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Text(
                                              'Edit Student',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),

                                          PopupMenuItem(
                                            value: 'toggle',
                                            child: Text(
                                              accountStatus == 'Active'
                                                  ? 'Deactivate'
                                                  : 'Activate',
                                              style: TextStyle(
                                                color: accountStatus == 'Active'
                                                    ? errorColor
                                                    : successColor,
                                              ),
                                            ),
                                          ),

                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text(
                                              'Delete Account',
                                              style: TextStyle(
                                                color: errorColor,
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

        onBackgroundImageError: (exception, stackTrace) {},
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

    return '$first$last'.isEmpty ? 'S' : '$first$last';
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
  // ADD / EDIT STUDENT
  // ============================================================

  void _showAddOrEditStudentDialog(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? existingData,
  }) {
    final bool isEditing = docId != null;

    final firstNameController = TextEditingController(
      text: existingData?['firstName']?.toString() ?? '',
    );

    final lastNameController = TextEditingController(
      text: existingData?['lastName']?.toString() ?? '',
    );

    final emailController = TextEditingController(
      text: existingData?['email']?.toString() ?? '',
    );

    final phoneController = TextEditingController(
      text: existingData?['phone']?.toString() ?? '',
    );

    final courseController = TextEditingController(
      text: existingData?['course']?.toString() ?? '',
    );

    final monthlyFeeController = TextEditingController(
      text: existingData?['monthlyFee']?.toString() ?? '1000',
    );

    final studentIdController = TextEditingController(
      text:
          existingData?['studentId']?.toString() ??
          'STU-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
    );

    // ==========================================================
    // IMPORTANT:
    // These variables belong to THIS dialog.
    // StatefulBuilder will rebuild the photo preview.
    // ==========================================================

    XFile? selectedImage;

    Uint8List? selectedImageBytes;

    String? existingImageUrl = existingData?['profilePhoto']?.toString();

    bool uploadingImage = false;

    showDialog(
      context: context,

      barrierDismissible: false,

      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // ==================================================
            // PICK IMAGE
            // ==================================================

            Future<void> pickImage() async {
              try {
                final ImagePicker picker = ImagePicker();

                final XFile? image = await picker.pickImage(
                  source: ImageSource.gallery,

                  imageQuality: 80,
                );

                if (image == null) {
                  return;
                }

                final Uint8List bytes = await image.readAsBytes();

                setDialogState(() {
                  selectedImage = image;

                  selectedImageBytes = bytes;

                  // Remove old URL from
                  // preview because a new
                  // image was selected.
                  existingImageUrl = null;
                });
              } catch (e) {
                if (!dialogContext.mounted) {
                  return;
                }

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Unable to select image: $e')),
                );
              }
            }

            // ==================================================
            // UPLOAD IMAGE
            // ==================================================

            Future<String?> uploadStudentImage(String documentId) async {
              if (selectedImageBytes == null) {
                return existingData?['profilePhoto'];
              }

              try {
                setDialogState(() {
                  uploadingImage = true;
                });

                final String fileName =
                    '${DateTime.now().millisecondsSinceEpoch}.jpg';

                final Reference storageRef = FirebaseStorage.instance
                    .ref()
                    .child('student_profiles')
                    .child(documentId)
                    .child(fileName);

                await storageRef.putData(
                  selectedImageBytes!,
                  SettableMetadata(contentType: 'image/jpeg'),
                );

                final String downloadUrl = await storageRef.getDownloadURL();

                return downloadUrl;
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Image upload failed: $e')),
                  );
                }

                return null;
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    uploadingImage = false;
                  });
                }
              }
            }

            // ==================================================
            // SAVE STUDENT
            // ==================================================

            Future<void> saveStudent() async {
              if (firstNameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Please enter first name.')),
                );

                return;
              }

              try {
                setDialogState(() {
                  uploadingImage = true;
                });

                final Map<String, dynamic> studentData = {
                  'firstName': firstNameController.text.trim(),

                  'lastName': lastNameController.text.trim(),

                  'studentId': studentIdController.text.trim(),

                  'email': emailController.text.trim(),

                  'phone': phoneController.text.trim(),

                  'course': courseController.text.trim(),

                  'monthlyFee':
                      double.tryParse(monthlyFeeController.text.trim()) ??
                      1000.0,

                  'feeStatus': existingData?['feeStatus'] ?? 'Pending',

                  'accountStatus': existingData?['accountStatus'] ?? 'Active',

                  'updatedAt': FieldValue.serverTimestamp(),
                };

                // ==================================================
                // EDIT EXISTING STUDENT
                // ==================================================

                if (isEditing) {
                  String? imageUrl;

                  if (selectedImageBytes != null) {
                    imageUrl = await uploadStudentImage(docId!);

                    if (imageUrl != null) {
                      studentData['profilePhoto'] = imageUrl;
                    }
                  }

                  await FirebaseFirestore.instance
                      .collection('user')
                      .doc(docId)
                      .update(studentData);
                }
                // ==================================================
                // ADD NEW STUDENT
                // ==================================================
                else {
                  studentData['createdAt'] = FieldValue.serverTimestamp();

                  studentData['presentDays'] = 0;

                  studentData['absentDays'] = 0;

                  studentData['todayAttendance'] = 'Pending';

                  studentData['practiceProgress'] = 0;

                  studentData['profilePhoto'] = '';

                  studentData['gender'] = 'Not Specified';

                  studentData['dateOfBirth'] = '2010-01-01';

                  studentData['address'] = 'Hyderabad';

                  // Create Firestore document first.
                  final DocumentReference newStudentRef =
                      await FirebaseFirestore.instance
                          .collection('user')
                          .add(studentData);

                  // Upload image using the
                  // newly created document ID.
                  if (selectedImageBytes != null) {
                    final String? imageUrl = await uploadStudentImage(
                      newStudentRef.id,
                    );

                    if (imageUrl != null) {
                      await newStudentRef.update({
                        'profilePhoto': imageUrl,
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                    }
                  }
                }

                if (!dialogContext.mounted) {
                  return;
                }

                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isEditing
                          ? 'Student updated successfully.'
                          : 'Student added successfully.',
                    ),
                  ),
                );
              } catch (e) {
                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  uploadingImage = false;
                });

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Failed to save student: $e')),
                );
              }
            }

            // ==================================================
            // PHOTO PREVIEW
            // ==================================================

            Widget photoWidget;

            if (selectedImageBytes != null) {
              // NEWLY SELECTED PHOTO
              photoWidget = ClipOval(
                child: Image.memory(
                  selectedImageBytes!,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              );
            } else if (existingImageUrl != null &&
                existingImageUrl!.isNotEmpty) {
              // EXISTING FIREBASE PHOTO
              photoWidget = ClipOval(
                child: Image.network(
                  existingImageUrl!,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,

                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryColor,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 42,
                      ),
                    );
                  },
                ),
              );
            } else {
              // NO PHOTO
              photoWidget = Container(
                width: 96,
                height: 96,

                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor,
                ),

                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 38,
                ),
              );
            }

            // ==================================================
            // DIALOG UI
            // ==================================================

            return AlertDialog(
              backgroundColor: cardColor,

              title: Text(
                isEditing ? 'Edit Student' : 'Add New Student',

                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),

              content: SizedBox(
                width: 450,

                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,

                    children: [
                      // ==========================================
                      // STUDENT PHOTO
                      // ==========================================
                      GestureDetector(
                        onTap: uploadingImage ? null : pickImage,

                        child: photoWidget,
                      ),

                      const SizedBox(height: 10),

                      TextButton.icon(
                        onPressed: uploadingImage ? null : pickImage,

                        icon: const Icon(
                          Icons.photo_library,
                          color: primaryColor,
                        ),

                        label: Text(
                          selectedImageBytes != null
                              ? 'Change Photo'
                              : 'Select Photo',

                          style: const TextStyle(color: Colors.white),
                        ),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'Student Photo',
                        style: TextStyle(color: textSecondary, fontSize: 14),
                      ),

                      const SizedBox(height: 20),

                      // ==========================================
                      // FORM
                      // ==========================================
                      _buildTextField('First Name', firstNameController),

                      const SizedBox(height: 12),

                      _buildTextField('Last Name', lastNameController),

                      const SizedBox(height: 12),

                      _buildTextField('Student ID', studentIdController),

                      const SizedBox(height: 12),

                      _buildTextField('Email', emailController),

                      const SizedBox(height: 12),

                      _buildTextField('Phone', phoneController),

                      const SizedBox(height: 12),

                      _buildTextField('Course (e.g. Piano)', courseController),

                      const SizedBox(height: 12),

                      _buildTextField(
                        'Monthly Fee',
                        monthlyFeeController,
                        isNumber: true,
                      ),
                    ],
                  ),
                ),
              ),

              actions: [
                TextButton(
                  onPressed: uploadingImage
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                        },

                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: textSecondary),
                  ),
                ),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                  ),

                  onPressed: uploadingImage ? null : saveStudent,

                  child: uploadingImage
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
  // TEXT FIELD
  // ============================================================

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

  // ============================================================
  // STUDENT DETAILS
  // ============================================================

  void _showStudentDetailsModal(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final String profilePhoto = data['profilePhoto']?.toString() ?? '';

    showDialog(
      context: context,

      builder: (context) => AlertDialog(
        backgroundColor: cardColor,

        title: Text(
          '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),

        content: SizedBox(
          width: 400,

          child: SingleChildScrollView(
            child: Column(
              children: [
                // PHOTO
                if (profilePhoto.isNotEmpty)
                  ClipOval(
                    child: Image.network(
                      profilePhoto,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: primaryColor,
                    child: Icon(Icons.person, color: Colors.white, size: 45),
                  ),

                const SizedBox(height: 20),

                _detailRow('Student ID', data['studentId']?.toString()),

                _detailRow('Email', data['email']?.toString()),

                _detailRow('Phone', data['phone']?.toString()),

                _detailRow('Course', data['course']?.toString()),

                _detailRow('Gender', data['gender']?.toString()),

                _detailRow('Date of Birth', data['dateOfBirth']?.toString()),

                _detailRow('Address', data['address']?.toString()),

                _detailRow('Monthly Fee', data['monthlyFee']?.toString()),

                _detailRow('Fee Status', data['feeStatus']?.toString()),

                _detailRow('Account Status', data['accountStatus']?.toString()),
              ],
            ),
          ),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),

            child: const Text('Close', style: TextStyle(color: primaryColor)),
          ),
        ],
      ),
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

      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),

            child: const Text('Cancel', style: TextStyle(color: textSecondary)),
          ),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus == 'Active'
                  ? successColor
                  : errorColor,
            ),

            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('user')
                  .doc(docId)
                  .update({
                    'accountStatus': newStatus,

                    'updatedAt': FieldValue.serverTimestamp(),
                  });

              if (context.mounted) {
                Navigator.pop(context);
              }
            },

            child: const Text('Confirm'),
          ),
        ],
      ),
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

    final bool? confirmed = await showDialog<bool>(
      context: context,

      builder: (dialogContext) => AlertDialog(
        backgroundColor: cardColor,

        title: const Text(
          'Delete Account?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),

        content: Text(
          'Are you sure you want to permanently delete '
          '${studentName.isEmpty ? 'this student' : studentName}\'s account?\n\n'
          'This action cannot be undone.',

          style: const TextStyle(color: textSecondary),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),

            child: const Text('Cancel', style: TextStyle(color: textSecondary)),
          ),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: errorColor,
              foregroundColor: Colors.white,
            ),

            onPressed: () => Navigator.pop(dialogContext, true),

            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('user').doc(docId).delete();

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student account deleted successfully.')),
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete account: $e')));
    }
  }
}
