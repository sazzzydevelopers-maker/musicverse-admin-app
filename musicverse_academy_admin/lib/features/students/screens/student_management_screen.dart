import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
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

          // ====================================================
          // STATISTICS
          // ====================================================

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

          // ====================================================
          // COURSES
          // ====================================================

          final Set<String> coursesSet = {'All'};

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;

            final course = data['course'];

            if (course != null && course.toString().trim().isNotEmpty) {
              coursesSet.add(course.toString());
            }
          }

          final List<String> availableCourses = coursesSet.toList();

          // ====================================================
          // FILTER
          // ====================================================

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
                            focusNode: _searchFocusNode,

                            style: const TextStyle(color: Colors.white),

                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value.trim().toLowerCase();
                              });

                              // Keep the search field focused after the
                              // student list rebuilds.
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && !_searchFocusNode.hasFocus) {
                                  _searchFocusNode.requestFocus();
                                }
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

    String? existingImageUrl = existingData?['profilePhoto']?.toString();

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
    ];

    final String? existingCourse = existingData?['course']?.toString().trim();

    String? selectedCourse =
        existingCourse != null && courseOptions.contains(existingCourse)
        ? existingCourse
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
              // ----------------------------------------------
              // VALIDATE ALL REQUIRED FIELDS
              // ----------------------------------------------

              if (!formKey.currentState!.validate()) {
                return;
              }

              setDialogState(() {
                saving = true;
              });

              try {
                // ----------------------------------------------
                // COMMON STUDENT DATA
                // -----------------------------we-----------------

                final Map<String, dynamic> studentData = {
                  'firstName': firstNameController.text.trim(),

                  'lastName': lastNameController.text.trim(),

                  'email': emailController.text.trim(),

                  'phone': phoneController.text.trim(),

                  'course': selectedCourse!,

                  'monthlyFee': double.parse(monthlyFeeController.text.trim()),

                  'updatedAt': FieldValue.serverTimestamp(),
                };

                // ============================================
                // EDIT STUDENT
                // ============================================

                if (isEditing) {
                  final String editingDocId = docId;

                  // --------------------------------------------
                  // UPDATE FIRESTORE FIRST
                  // --------------------------------------------
                  //
                  // Do NOT wait for Firebase Storage here.
                  // Firestore data should be saved immediately and
                  // the dialog should close. The optional photo is
                  // uploaded in the background afterwards.
                  await FirebaseFirestore.instance
                      .collection('user')
                      .doc(editingDocId)
                      .update(studentData);

                  final Uint8List? imageBytesToUpload = selectedImageBytes;

                  if (imageBytesToUpload != null) {
                    // Start the optional photo upload without blocking
                    // the Save button.
                    uploadStudentImage(editingDocId, imageBytesToUpload).then((
                      imageUrl,
                    ) async {
                      if (imageUrl != null && imageUrl.isNotEmpty) {
                        await FirebaseFirestore.instance
                            .collection('user')
                            .doc(editingDocId)
                            .update({
                              'profilePhoto': imageUrl,
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                      }
                    });
                  }
                }
                // ============================================
                // ADD NEW STUDENT
                // ============================================
                else {
                  // The ID displayed in the Add Student form is the ID we
                  // save. If a very rare collision exists in Firestore,
                  // generate a new ID before saving.
                  String newStudentId = studentIdController.text.trim();

                  final CollectionReference<Map<String, dynamic>> users =
                      FirebaseFirestore.instance.collection('user');

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
                    throw Exception(
                      'Unable to generate a unique Student ID. Please try again.',
                    );
                  }

                  studentData['studentId'] = newStudentId;

                  studentData['createdAt'] = FieldValue.serverTimestamp();

                  studentData['accountStatus'] = 'Active';

                  studentData['feeStatus'] = 'Pending';

                  studentData['presentDays'] = 0;

                  studentData['absentDays'] = 0;

                  studentData['todayAttendance'] = 'Pending';

                  studentData['practiceProgress'] = 0;

                  // --------------------------------------------
                  // PHOTO IS OPTIONAL
                  // --------------------------------------------

                  studentData['profilePhoto'] = '';

                  // --------------------------------------------
                  // CREATE FIRESTORE DOCUMENT
                  // --------------------------------------------

                  final DocumentReference newStudentRef =
                      await FirebaseFirestore.instance
                          .collection('user')
                          .add(studentData);

                  // --------------------------------------------
                  // OPTIONAL PHOTO UPLOAD
                  // --------------------------------------------
                  //
                  // IMPORTANT:
                  // Do NOT await Firebase Storage here.
                  //
                  // Firestore has already created the student.
                  // The Save button must finish immediately instead
                  // of staying on a loading spinner while Storage
                  // uploads the optional image.
                  final Uint8List? imageBytesToUpload = selectedImageBytes;

                  if (imageBytesToUpload != null) {
                    uploadStudentImage(
                      newStudentRef.id,
                      imageBytesToUpload,
                    ).then((imageUrl) async {
                      if (imageUrl != null && imageUrl.isNotEmpty) {
                        await newStudentRef.update({
                          'profilePhoto': imageUrl,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                      }
                    });
                  }
                }

                // ============================================
                // SUCCESS
                // ============================================

                if (!dialogContext.mounted) {
                  return;
                }

                // IMPORTANT:
                //
                // This closes ONLY the
                // Add/Edit dialog.
                //
                // It does NOT go to
                // Dashboard.
                //
                Navigator.of(dialogContext).pop();

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
  // GENERATE STUDENT ID
  // ============================================================

  String _generateStudentId() {
    final Random random = Random();

    // Eight random digits: 10000000 - 99999999.
    // Example: SZYD-STD-483721
    final int number = 10000000 + random.nextInt(90000000);

    return 'SZYD-STD-$number';
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

      builder: (dialogContext) {
        return AlertDialog(
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
                  // ============================================
                  // PHOTO
                  // ============================================
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

                  _detailRow('Student ID', data['studentId']?.toString()),

                  _detailRow('Email', data['email']?.toString()),

                  _detailRow('Phone', data['phone']?.toString()),

                  _detailRow('Course', data['course']?.toString()),

                  _detailRow('Gender', data['gender']?.toString()),

                  _detailRow('Date of Birth', data['dateOfBirth']?.toString()),

                  _detailRow('Address', data['address']?.toString()),

                  _detailRow('Monthly Fee', data['monthlyFee']?.toString()),

                  _detailRow('Fee Status', data['feeStatus']?.toString()),

                  _detailRow(
                    'Account Status',
                    data['accountStatus']?.toString(),
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
                    .collection('user')
                    .doc(docId)
                    .update({
                      'accountStatus': newStatus,

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
            'Are you sure you want to permanently delete '
            '${studentName.isEmpty ? 'this student' : studentName}\'s account?\n\n'
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
