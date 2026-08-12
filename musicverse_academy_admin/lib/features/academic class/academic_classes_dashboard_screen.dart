import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AcademicClassesDashboardScreen extends StatefulWidget {
  const AcademicClassesDashboardScreen({super.key});

  @override
  State<AcademicClassesDashboardScreen> createState() =>
      _AcademicClassesDashboardScreenState();
}

class _AcademicClassesDashboardScreenState
    extends State<AcademicClassesDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _classesStream;

  // The calendar owns its month/selected-date state so clicking a date
  // rebuilds only the calendar, not the whole dashboard.
  DateTime? _selectedDate;

  final Color _background = const Color(0xFF0B0F20);
  final Color _card = const Color(0xFF171C35);
  final Color _card2 = const Color(0xFF1D2342);
  final Color _purple = const Color(0xFF7C4DFF);
  final Color _purpleLight = const Color(0xFF9D6BFF);
  final Color _text = Colors.white;
  final Color _secondaryText = const Color(0xFFB0B5D3);
  final Color _green = const Color(0xFF00E676);
  final Color _yellow = const Color(0xFFFFC107);
  final Color _red = const Color(0xFFFF5252);

  CollectionReference<Map<String, dynamic>> get _classesCollection =>
      _firestore.collection('academic_classes');

  @override
  void initState() {
    super.initState();
    // Keep one Firestore stream for the lifetime of this screen.
    // This prevents the loading state from appearing again when the
    // calendar/month/selected-date state changes.
    _classesStream = _classesCollection.snapshots();
  }

  @override
  void dispose() {
    super.dispose();
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _toDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return DateTime.now();
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month - 1];
  }

  String _formatTime(DateTime time) {
    final hour = time.hour == 0
        ? 12
        : time.hour > 12
        ? time.hour - 12
        : time.hour;

    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $suffix';
  }

  String _formatDate(DateTime date) {
    return '${_monthName(date.month)} ${date.day}, ${date.year}';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return _yellow;
      case 'cancelled':
        return _red;
      case 'scheduled':
      default:
        return _green;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      case 'scheduled':
      default:
        return Icons.schedule_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'scheduled':
      default:
        return 'Scheduled';
    }
  }

  Future<void> _refresh() async {
    // The StreamBuilder already listens for Firestore changes.
    // This explicit read simply gives RefreshIndicator a real async action
    // without rebuilding/resetting the whole screen.
    await _classesCollection.get(const GetOptions(source: Source.server));
  }

  Future<void> _openDateDialog(
    DateTime date,
    List<Map<String, dynamic>> classes,
    List<Map<String, dynamic>> allClasses,
  ) async {
    // Monthly totals are calculated from the same Firestore data already
    // loaded by the dashboard. No extra Firestore query is required.
    // Get all currently loaded classes from the calendar stream by using
    // the date-specific list plus the full dashboard data is handled below
    // through the cached snapshot passed into this dialog.
    final monthlyClasses = allClasses.where((data) {
      final classDate = _dateOnly(_toDate(data['date']));
      return classDate.year == date.year && classDate.month == date.month;
    }).toList();

    final monthlyStudentCount = monthlyClasses.fold<int>(0, (total, data) {
      final value = data['studentCount'];
      if (value is num) {
        return total + value.toInt();
      }
      return total;
    });

    final action = await showDialog<_DateDialogAction>(
      context: context,
      builder: (dialogContext) {
        return _DateClassesDialog(
          date: date,
          classes: classes,
          monthlyClassCount: monthlyClasses.length,
          monthlyStudentCount: monthlyStudentCount,
          statusColor: _statusColor,
          statusIcon: _statusIcon,
          statusLabel: _statusLabel,
          formatTime: _formatTime,

          onAdd: () {
            Navigator.of(dialogContext).pop(_DateDialogAction.add());
          },

          onEdit: (data) async {
            Navigator.of(dialogContext).pop(_DateDialogAction.edit(data));
          },

          // DELETE
          onDelete: (data) async {
            // Close the Classes popup immediately.
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }

            // Delete from Firestore in the background.
            _deleteClass(data);
          },

          // STATUS: Scheduled / Completed / Cancelled
          onStatusChange: (data, status) async {
            // Close the Classes popup immediately.
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }

            // Update Firestore in the background.
            _updateStatus(data, status);
          },
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    if (action.type == _DateDialogActionType.add) {
      await _showClassEditor(date: date);
    } else if (action.type == _DateDialogActionType.edit &&
        action.data != null) {
      await _showClassEditor(date: date, existingData: action.data);
    }
  }

  Future<void> _showClassEditor({
    required DateTime date,
    Map<String, dynamic>? existingData,
  }) async {
    final isEditing = existingData != null;

    final classIdController = TextEditingController(
      text: isEditing
          ? (existingData['classId']?.toString() ?? '')
          : 'CLASS-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
    );

    final teacherController = TextEditingController(
      text: isEditing ? (existingData['teacher']?.toString() ?? '') : '',
    );

    final studentCountController = TextEditingController(
      text: isEditing ? (existingData['studentCount']?.toString() ?? '') : '',
    );

    DateTime selectedDate = isEditing
        ? _dateOnly(_toDate(existingData['date']))
        : _dateOnly(date);

    DateTime startTime = isEditing
        ? _toDate(existingData['startTime'])
        : DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            18,
            0,
          );

    DateTime endTime = isEditing
        ? _toDate(existingData['endTime'])
        : DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            19,
            0,
          );

    String selectedStatus = isEditing
        ? (existingData['status']?.toString() ?? 'scheduled')
        : 'scheduled';

    String selectedCourse = isEditing
        ? (existingData['course']?.toString() ?? 'All Courses')
        : 'All Courses';

    if (selectedCourse == 'All') {
      selectedCourse = 'All Courses';
    }

    final result = await showDialog<_ClassEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final width = MediaQuery.of(context).size.width;

            Widget courseButton(String course, IconData icon) {
              final selected = selectedCourse == course;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    setDialogState(() {
                      selectedCourse = course;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? _purple.withValues(alpha: 0.18)
                          : _background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? _purple
                            : _secondaryText.withValues(alpha: 0.10),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          size: 21,
                          color: selected ? _purpleLight : _secondaryText,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            course,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? _text : _secondaryText,
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(
                            Icons.check_circle_rounded,
                            color: _purpleLight,
                            size: 19,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.symmetric(
                horizontal: width < 500 ? 16 : 40,
                vertical: 24,
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _purple.withValues(alpha: 0.35)),
                  boxShadow: [
                    BoxShadow(
                      color: _purple.withValues(alpha: 0.15),
                      blurRadius: 35,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(width < 500 ? 20 : 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _purple.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              isEditing
                                  ? Icons.edit_calendar_rounded
                                  : Icons.add_circle_outline_rounded,
                              color: _purpleLight,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              isEditing
                                  ? 'Edit Academic Class'
                                  : 'Add Academic Class',
                              style: TextStyle(
                                color: _text,
                                fontSize: width < 500 ? 21 : 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              // Close ONLY the class editor dialog.
                              // Do not use rootNavigator here.
                              Navigator.of(
                                dialogContext,
                              ).pop(_ClassEditorResult.cancelled());
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: _secondaryText,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      _fieldLabel('Class ID'),
                      const SizedBox(height: 8),
                      _textField(
                        controller: classIdController,
                        hint: 'CLASS-2026-001',
                        enabled: !isEditing,
                      ),

                      const SizedBox(height: 16),

                      _fieldLabel('Course'),
                      const SizedBox(height: 8),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth < 420 ? 2 : 3;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: courseButton(
                                  'All Courses',
                                  Icons.library_music_rounded,
                                ),
                              ),
                              const SizedBox(height: 12),
                              GridView.count(
                                crossAxisCount: columns,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 2.6,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  courseButton(
                                    'Piano',
                                    Icons.music_note_rounded,
                                  ),
                                  courseButton(
                                    'Guitar',
                                    Icons.music_note_rounded,
                                  ),
                                  courseButton(
                                    'Violin',
                                    Icons.music_note_rounded,
                                  ),
                                  courseButton(
                                    'Flute',
                                    Icons.music_note_rounded,
                                  ),
                                  courseButton('Drums', Icons.album_rounded),
                                  courseButton('Vocal', Icons.mic_rounded),
                                  courseButton(
                                    'Other',
                                    Icons.more_horiz_rounded,
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      _fieldLabel('Date'),
                      const SizedBox(height: 8),

                      _dateButton(
                        date: selectedDate,
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.dark(
                                    primary: _purple,
                                    surface: _card,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );

                          if (picked != null) {
                            setDialogState(() {
                              selectedDate = _dateOnly(picked);

                              startTime = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                startTime.hour,
                                startTime.minute,
                              );

                              endTime = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                endTime.hour,
                                endTime.minute,
                              );
                            });
                          }
                        },
                      ),

                      const SizedBox(height: 16),

                      _fieldLabel('Class Time'),
                      const SizedBox(height: 8),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 420;

                          if (narrow) {
                            return Column(
                              children: [
                                _timeButton(
                                  title: 'Start',
                                  time: startTime,
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: dialogContext,
                                      initialTime: TimeOfDay.fromDateTime(
                                        startTime,
                                      ),
                                    );

                                    if (picked != null) {
                                      setDialogState(() {
                                        startTime = DateTime(
                                          selectedDate.year,
                                          selectedDate.month,
                                          selectedDate.day,
                                          picked.hour,
                                          picked.minute,
                                        );
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(height: 10),
                                _timeButton(
                                  title: 'End',
                                  time: endTime,
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: dialogContext,
                                      initialTime: TimeOfDay.fromDateTime(
                                        endTime,
                                      ),
                                    );

                                    if (picked != null) {
                                      setDialogState(() {
                                        endTime = DateTime(
                                          selectedDate.year,
                                          selectedDate.month,
                                          selectedDate.day,
                                          picked.hour,
                                          picked.minute,
                                        );
                                      });
                                    }
                                  },
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(
                                child: _timeButton(
                                  title: 'Start',
                                  time: startTime,
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: dialogContext,
                                      initialTime: TimeOfDay.fromDateTime(
                                        startTime,
                                      ),
                                    );

                                    if (picked != null) {
                                      setDialogState(() {
                                        startTime = DateTime(
                                          selectedDate.year,
                                          selectedDate.month,
                                          selectedDate.day,
                                          picked.hour,
                                          picked.minute,
                                        );
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _timeButton(
                                  title: 'End',
                                  time: endTime,
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: dialogContext,
                                      initialTime: TimeOfDay.fromDateTime(
                                        endTime,
                                      ),
                                    );

                                    if (picked != null) {
                                      setDialogState(() {
                                        endTime = DateTime(
                                          selectedDate.year,
                                          selectedDate.month,
                                          selectedDate.day,
                                          picked.hour,
                                          picked.minute,
                                        );
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      _fieldLabel('Teacher'),
                      const SizedBox(height: 8),
                      _textField(
                        controller: teacherController,
                        hint: 'Teacher name',
                      ),

                      const SizedBox(height: 16),

                      _fieldLabel('Students'),
                      const SizedBox(height: 8),
                      _textField(
                        controller: studentCountController,
                        hint: 'Number of students',
                        keyboardType: TextInputType.number,
                      ),

                      const SizedBox(height: 16),

                      _fieldLabel('Status'),
                      const SizedBox(height: 8),

                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        dropdownColor: _card2,
                        style: TextStyle(color: _text, fontSize: 16),
                        decoration: _inputDecoration(
                          Icons.circle_rounded,
                          'Status',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'scheduled',
                            child: Text('Scheduled'),
                          ),
                          DropdownMenuItem(
                            value: 'completed',
                            child: Text('Completed'),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text('Cancelled'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedStatus = value;
                            });
                          }
                        },
                      ),

                      const SizedBox(height: 28),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 380) {
                            return Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      Navigator.of(
                                        dialogContext,
                                      ).pop(_ClassEditorResult.cancelled());
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _secondaryText,
                                      side: BorderSide(
                                        color: _secondaryText.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 15,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: _saveButton(
                                    dialogContext,
                                    isEditing,
                                    classIdController,
                                    teacherController,
                                    studentCountController,
                                    selectedDate,
                                    startTime,
                                    endTime,
                                    selectedCourse,
                                    selectedStatus,
                                    existingData,
                                  ),
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.of(
                                      dialogContext,
                                    ).pop(_ClassEditorResult.cancelled());
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _secondaryText,
                                    side: BorderSide(
                                      color: _secondaryText.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _saveButton(
                                  dialogContext,
                                  isEditing,
                                  classIdController,
                                  teacherController,
                                  studentCountController,
                                  selectedDate,
                                  startTime,
                                  endTime,
                                  selectedCourse,
                                  selectedStatus,
                                  existingData,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // The dialog is completely gone at this point. It is now safe to dispose
    // its controllers and update the parent screen.
    classIdController.dispose();
    teacherController.dispose();
    studentCountController.dispose();

    if (!mounted || result == null || !result.saved) {
      return;
    }

    _selectedDate = result.date;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isEditing
              ? 'Class updated successfully.'
              : 'Class added successfully.',
        ),
      ),
    );
  }

  Widget _saveButton(
    BuildContext dialogContext,
    bool isEditing,
    TextEditingController classIdController,
    TextEditingController teacherController,
    TextEditingController studentCountController,
    DateTime selectedDate,
    DateTime startTime,
    DateTime endTime,
    String selectedCourse,
    String selectedStatus,
    Map<String, dynamic>? existingData,
  ) {
    return ElevatedButton(
      onPressed: () async {
        final teacher = teacherController.text.trim();
        final students = int.tryParse(studentCountController.text.trim());

        if (selectedCourse.isEmpty ||
            teacher.isEmpty ||
            students == null ||
            students < 0) {
          if (dialogContext.mounted) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(
                content: Text('Please complete all required fields.'),
              ),
            );
          }
          return;
        }

        if (!endTime.isAfter(startTime)) {
          if (dialogContext.mounted) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(
                content: Text('End time must be after start time.'),
              ),
            );
          }
          return;
        }

        final date = _dateOnly(selectedDate);

        final fixedStartTime = DateTime(
          date.year,
          date.month,
          date.day,
          startTime.hour,
          startTime.minute,
        );

        final fixedEndTime = DateTime(
          date.year,
          date.month,
          date.day,
          endTime.hour,
          endTime.minute,
        );

        try {
          if (isEditing && existingData != null) {
            final documentId = existingData['_documentId']?.toString();

            if (documentId == null || documentId.isEmpty) {
              throw Exception('Document ID not found.');
            }

            await _classesCollection.doc(documentId).update({
              'classId': classIdController.text.trim(),
              'course': selectedCourse,
              'date': Timestamp.fromDate(date),
              'startTime': Timestamp.fromDate(fixedStartTime),
              'endTime': Timestamp.fromDate(fixedEndTime),
              'status': selectedStatus,
              'studentCount': students,
              'teacher': teacher,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            await _classesCollection.add({
              'classId': classIdController.text.trim(),
              'course': selectedCourse,
              'date': Timestamp.fromDate(date),
              'startTime': Timestamp.fromDate(fixedStartTime),
              'endTime': Timestamp.fromDate(fixedEndTime),
              'status': selectedStatus,
              'studentCount': students,
              'teacher': teacher,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          // IMPORTANT:
          // Return the result and let _showClassEditor() handle the
          // snackbar AFTER showDialog() has completely closed.
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop(_ClassEditorResult.saved(date));
          }
        } catch (e) {
          // Only show an error while the dialog is still mounted.
          // Never use this context after Navigator.pop().
          if (dialogContext.mounted) {
            ScaffoldMessenger.of(
              dialogContext,
            ).showSnackBar(SnackBar(content: Text('Failed to save class: $e')));
          }
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        isEditing ? 'Save Changes' : 'Add Class',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _updateStatus(Map<String, dynamic> data, String status) async {
    final documentId = data['_documentId']?.toString();

    if (documentId == null || documentId.isEmpty) {
      return;
    }

    try {
      await _classesCollection.doc(documentId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Firestore snapshots() updates the calendar automatically.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
      }
    }
  }

  Future<void> _deleteClass(Map<String, dynamic> data) async {
    final documentId = data['_documentId']?.toString();

    if (documentId == null || documentId.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _card,
          title: Text(
            'Delete Class?',
            style: TextStyle(color: _text, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'This class will be permanently deleted.',
            style: TextStyle(color: _secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text('Cancel', style: TextStyle(color: _secondaryText)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _classesCollection.doc(documentId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Class deleted successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete class: $e')));
      }
    }
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: _secondaryText,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _inputDecoration(IconData icon, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _secondaryText.withValues(alpha: 0.65)),
      prefixIcon: Icon(icon, color: _purpleLight),
      filled: true,
      fillColor: _background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _secondaryText.withValues(alpha: 0.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _purple, width: 1.4),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    bool enabled = true,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      style: TextStyle(color: _text, fontSize: 16),
      decoration: _inputDecoration(Icons.edit_rounded, hint),
    );
  }

  Widget _dateButton({
    required DateTime date,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.calendar_month_rounded, color: _purpleLight),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(_formatDate(date), overflow: TextOverflow.ellipsis),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _text,
          backgroundColor: _background,
          side: BorderSide(color: _secondaryText.withValues(alpha: 0.10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _timeButton({
    required String title,
    required DateTime time,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: _text,
          backgroundColor: _background,
          side: BorderSide(color: _secondaryText.withValues(alpha: 0.10)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, color: _purpleLight, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: _secondaryText, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(time),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar(List<Map<String, dynamic>> classes, double width) {
    return _AcademicCalendar(
      classes: classes,
      width: width,
      initialSelectedDate: _selectedDate,
      statusColor: _statusColor,
      onDateSelected: (date, dayClasses) {
        // Do not call setState here. The calendar manages its own selected
        // state. The parent only remembers the date for the Add Class button.
        _selectedDate = date;
        _openDateDialog(date, dayClasses, classes);
      },
    );
  }

  Widget _buildHeader(double width) {
    final compact = width < 600;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: width < 500 ? 18 : 28,
        vertical: width < 500 ? 18 : 24,
      ),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _purple.withValues(alpha: 0.13)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerTitle(),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: _addClassButton()),
              ],
            )
          : Row(
              children: [
                Expanded(child: _headerTitle()),
                const SizedBox(width: 20),
                _addClassButton(),
              ],
            ),
    );
  }

  Widget _headerTitle() {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_purple, _purpleLight]),
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(
            Icons.event_available_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Academic Classes',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _text,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your academic class schedule',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _secondaryText, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _addClassButton() {
    return ElevatedButton.icon(
      onPressed: () {
        _showClassEditor(date: _selectedDate ?? DateTime.now());
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add Class'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _classesStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _errorView(snapshot.error.toString());
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: _purple));
            }

            final classes =
                snapshot.data?.docs.map((doc) {
                  final data = doc.data();

                  return {...data, '_documentId': doc.id};
                }).toList() ??
                [];

            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                return RefreshIndicator(
                  color: _purple,
                  backgroundColor: _card,
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _topBar(width)),
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: width < 500
                              ? 16
                              : width < 900
                              ? 24
                              : 40,
                          vertical: 22,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildHeader(width),
                            const SizedBox(height: 18),
                            _buildCalendar(classes, width),
                            const SizedBox(height: 30),
                          ]),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(double width) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: width < 450 ? 16 : 28,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF202542),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Academic Classes',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _text,
                fontSize: width < 500 ? 21 : 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Reload',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _errorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _red.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: _red, size: 50),
              const SizedBox(height: 14),
              Text(
                'Unable to load academic classes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: _secondaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcademicCalendar extends StatefulWidget {
  final List<Map<String, dynamic>> classes;
  final double width;
  final DateTime? initialSelectedDate;
  final Color Function(String status) statusColor;
  final void Function(DateTime date, List<Map<String, dynamic>> dayClasses)
  onDateSelected;

  const _AcademicCalendar({
    required this.classes,
    required this.width,
    required this.initialSelectedDate,
    required this.statusColor,
    required this.onDateSelected,
  });

  @override
  State<_AcademicCalendar> createState() => _AcademicCalendarState();
}

class _AcademicCalendarState extends State<_AcademicCalendar> {
  late DateTime _displayedMonth;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialSelectedDate ?? DateTime.now();

    _selectedDate = DateTime(initial.year, initial.month, initial.day);

    _displayedMonth = DateTime(initial.year, initial.month);
  }

  @override
  void didUpdateWidget(covariant _AcademicCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Do not reset _displayedMonth or _selectedDate when Firestore sends
    // an update. This is the important part that prevents the calendar
    // from jumping/reloading after Add/Edit/Delete.
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _toDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return DateTime.now();
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[month - 1];
  }

  List<DateTime> _calendarDays() {
    final firstDay = DateTime(_displayedMonth.year, _displayedMonth.month, 1);

    final lastDay = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + 1,
      0,
    );

    final daysBeforeMonday = firstDay.weekday - 1;
    final start = firstDay.subtract(Duration(days: daysBeforeMonday));

    final totalCells = ((daysBeforeMonday + lastDay.day) / 7).ceil() * 7;

    return List.generate(
      totalCells,
      (index) => _dateOnly(start.add(Duration(days: index))),
    );
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      );
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      );
    });
  }

  void _goToToday() {
    final now = DateTime.now();

    setState(() {
      _displayedMonth = DateTime(now.year, now.month);
      _selectedDate = _dateOnly(now);
    });
  }

  String _classKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final days = _calendarDays();

    final classesByDate = <String, List<Map<String, dynamic>>>{};

    for (final data in widget.classes) {
      final date = _dateOnly(_toDate(data['date']));
      classesByDate.putIfAbsent(
        _classKey(date),
        () => <Map<String, dynamic>>[],
      );
      classesByDate[_classKey(date)]!.add(data);
    }

    final calendarWidth = widget.width > 900 ? 760.0 : widget.width;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: calendarWidth),
      padding: EdgeInsets.all(widget.width < 500 ? 14 : 22),
      decoration: BoxDecoration(
        color: const Color(0xFF171C35),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFF7C4DFF).withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ============================================================
          // MONTH HEADER
          // ============================================================
          Row(
            children: [
              Container(
                width: widget.width < 500 ? 42 : 46,
                height: widget.width < 500 ? 42 : 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xFF9D6BFF),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  // The year ALWAYS comes from _displayedMonth.
                  // No hard-coded year.
                  '${_monthName(_displayedMonth.month)} '
                  '${_displayedMonth.year}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.width < 500 ? 18 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              IconButton(
                tooltip: 'Previous month',
                onPressed: _previousMonth,
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: Color(0xFFB0B5D3),
                ),
              ),

              IconButton(
                tooltip: 'Current month',
                onPressed: _goToToday,
                icon: const Icon(Icons.today_rounded, color: Color(0xFF9D6BFF)),
              ),

              IconButton(
                tooltip: 'Next month',
                onPressed: _nextMonth,
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFB0B5D3),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ============================================================
          // WEEK DAYS
          // ============================================================
          const Row(
            children: [
              _WeekDay(label: 'MON'),
              _WeekDay(label: 'TUE'),
              _WeekDay(label: 'WED'),
              _WeekDay(label: 'THU'),
              _WeekDay(label: 'FRI'),
              _WeekDay(label: 'SAT'),
              _WeekDay(label: 'SUN'),
            ],
          ),

          const SizedBox(height: 8),

          // ============================================================
          // CALENDAR
          //
          // mainAxisExtent is used instead of childAspectRatio.
          // This gives every cell a predictable height and prevents
          // the "BOTTOM OVERFLOWED BY 2.1 PIXELS" error.
          // ============================================================
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              mainAxisExtent: 58,
            ),
            itemBuilder: (context, index) {
              final date = days[index];

              final dayClasses = classesByDate[_classKey(date)] ?? [];

              final isCurrentMonth =
                  date.month == _displayedMonth.month &&
                  date.year == _displayedMonth.year;

              final isToday = _sameDay(date, DateTime.now());

              final isSelected =
                  _selectedDate != null && _sameDay(date, _selectedDate!);

              return _CalendarDay(
                date: date,
                isCurrentMonth: isCurrentMonth,
                isToday: isToday,
                isSelected: isSelected,
                classes: dayClasses,
                statusColor: widget.statusColor,
                onTap: () {
                  // Only THIS calendar widget rebuilds.
                  setState(() {
                    _selectedDate = date;
                  });

                  widget.onDateSelected(date, dayClasses);
                },
              );
            },
          ),

          const SizedBox(height: 18),

          // ============================================================
          // LEGEND
          // ============================================================
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 18,
            runSpacing: 10,
            children: [
              _calendarLegend(const Color(0xFF00E676), 'Scheduled'),
              _calendarLegend(const Color(0xFFFFC107), 'Completed'),
              _calendarLegend(const Color(0xFFFF5252), 'Cancelled'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calendarLegend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFFB0B5D3),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _WeekDay extends StatelessWidget {
  final String label;

  const _WeekDay({required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8E94B5),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  final DateTime date;
  final bool isCurrentMonth;
  final bool isToday;
  final bool isSelected;
  final List<Map<String, dynamic>> classes;
  final Color Function(String) statusColor;
  final VoidCallback onTap;

  const _CalendarDay({
    required this.date,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isSelected,
    required this.classes,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final uniqueStatuses = <String>{};

    for (final data in classes) {
      uniqueStatuses.add(
        (data['status']?.toString() ?? 'scheduled').toLowerCase(),
      );
    }

    final statusList = uniqueStatuses.toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF7C4DFF).withValues(alpha: 0.20)
                : isToday
                ? const Color(0xFF7C4DFF).withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: isToday
                  ? const Color(0xFF7C4DFF)
                  : isSelected
                  ? const Color(0xFF9D6BFF)
                  : Colors.transparent,
              width: isToday || isSelected ? 1.2 : 0,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                date.day.toString(),
                style: TextStyle(
                  color: isCurrentMonth
                      ? Colors.white
                      : const Color(0xFF555B78),
                  fontSize: 13,
                  fontWeight: isToday || isSelected
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: statusList.take(3).map((status) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor(status),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassEditorResult {
  final bool saved;
  final DateTime date;

  const _ClassEditorResult._({required this.saved, required this.date});

  factory _ClassEditorResult.saved(DateTime date) {
    return _ClassEditorResult._(saved: true, date: date);
  }

  factory _ClassEditorResult.cancelled() {
    return _ClassEditorResult._(saved: false, date: DateTime(2000));
  }
}

enum _DateDialogActionType { add, edit }

class _DateDialogAction {
  final _DateDialogActionType type;
  final Map<String, dynamic>? data;

  const _DateDialogAction._({required this.type, this.data});

  factory _DateDialogAction.add() {
    return const _DateDialogAction._(type: _DateDialogActionType.add);
  }

  factory _DateDialogAction.edit(Map<String, dynamic> data) {
    return _DateDialogAction._(type: _DateDialogActionType.edit, data: data);
  }
}

class _DateClassesDialog extends StatelessWidget {
  final DateTime date;
  final List<Map<String, dynamic>> classes;
  final int monthlyClassCount;
  final int monthlyStudentCount;

  final Color Function(String) statusColor;
  final IconData Function(String) statusIcon;
  final String Function(String) statusLabel;
  final String Function(DateTime) formatTime;

  final VoidCallback onAdd;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final Future<void> Function(Map<String, dynamic>, String) onStatusChange;

  const _DateClassesDialog({
    required this.date,
    required this.classes,
    required this.monthlyClassCount,
    required this.monthlyStudentCount,
    required this.statusColor,
    required this.statusIcon,
    required this.statusLabel,
    required this.formatTime,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 500 ? 14 : 40,
        vertical: 24,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 650, maxHeight: 700),
        decoration: BoxDecoration(
          color: const Color(0xFF171C35),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Classes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_monthNameStatic(date.month)} ${date.day}, ${date.year}',
                          style: const TextStyle(
                            color: Color(0xFFB0B5D3),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onAdd,
                    tooltip: 'Add class',
                    icon: const Icon(
                      Icons.add_circle_rounded,
                      color: Color(0xFF9D6BFF),
                      size: 30,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFFB0B5D3),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0x223A4162), height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDailySummary(),
                    const SizedBox(height: 14),
                    _buildMonthlySummary(),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            "Today's Classes",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          classes.isEmpty
                              ? 'No classes'
                              : '${classes.length} ${classes.length == 1 ? 'class' : 'classes'}',
                          style: const TextStyle(
                            color: Color(0xFFB0B5D3),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (classes.isEmpty)
                      _emptyState()
                    else
                      ...classes.map(
                        (data) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ClassDialogCard(
                            data: data,
                            statusColor: statusColor,
                            statusIcon: statusIcon,
                            statusLabel: statusLabel,
                            formatTime: formatTime,
                            onEdit: () => onEdit(data),
                            onDelete: () => onDelete(data),
                            onStatusChange: (status) =>
                                onStatusChange(data, status),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailySummary() {
    final dailyStudents = classes.fold<int>(0, (total, data) {
      final value = data['studentCount'];
      if (value is num) {
        return total + value.toInt();
      }
      return total;
    });

    return _SummarySection(
      title: 'Selected Date',
      cards: [
        _MiniSummaryCard(
          title: 'Classes',
          value: classes.length.toString(),
          icon: Icons.school_rounded,
          color: const Color(0xFF9D6BFF),
        ),
        _MiniSummaryCard(
          title: 'Students',
          value: dailyStudents.toString(),
          icon: Icons.groups_rounded,
          color: const Color(0xFF00E676),
        ),
      ],
    );
  }

  Widget _buildMonthlySummary() {
    return _SummarySection(
      title: '${_monthNameStatic(date.month)} ${date.year}',
      cards: [
        _MiniSummaryCard(
          title: 'Monthly Classes',
          value: monthlyClassCount.toString(),
          icon: Icons.calendar_month_rounded,
          color: const Color(0xFF9D6BFF),
        ),
        _MiniSummaryCard(
          title: 'Monthly Students',
          value: monthlyStudentCount.toString(),
          icon: Icons.groups_rounded,
          color: const Color(0xFFFFC107),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: Color(0xFF9D6BFF),
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No classes scheduled',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Add a class for this date.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB0B5D3)),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Class'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  final String title;
  final List<Widget> cards;

  const _SummarySection({required this.title, required this.cards});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFB0B5D3),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 9),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 430;

            if (!twoColumns) {
              return Column(
                children: [cards[0], const SizedBox(height: 10), cards[1]],
              );
            }

            return Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 10),
                Expanded(child: cards[1]),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MiniSummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2342),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB0B5D3),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassDialogCard extends StatelessWidget {
  final Map<String, dynamic> data;

  final Color Function(String) statusColor;
  final IconData Function(String) statusIcon;
  final String Function(String) statusLabel;
  final String Function(DateTime) formatTime;

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<void> Function(String) onStatusChange;

  const _ClassDialogCard({
    required this.data,
    required this.statusColor,
    required this.statusIcon,
    required this.statusLabel,
    required this.formatTime,
    required this.onEdit,
    required this.onDelete,
    required this.onStatusChange,
  });

  DateTime _toDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status']?.toString() ?? 'scheduled').toLowerCase();
    final color = statusColor(status);
    final start = _toDate(data['startTime']);
    final end = _toDate(data['endTime']);
    final course = data['course']?.toString() ?? 'Class';
    final teacher = data['teacher']?.toString() ?? 'Not assigned';
    final studentCount = data['studentCount']?.toString() ?? '0';

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2342),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(statusIcon(status), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  course,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                color: const Color(0xFF202642),
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Color(0xFFB0B5D3),
                ),
                onSelected: (value) async {
                  if (value == 'edit') {
                    onEdit();
                    return;
                  }

                  if (value == 'delete') {
                    onDelete();
                    return;
                  }

                  await onStatusChange(value);
                },
                itemBuilder: (context) {
                  return [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                      value: 'scheduled',
                      child: Text('Mark Scheduled'),
                    ),
                    const PopupMenuItem(
                      value: 'completed',
                      child: Text('Mark Completed'),
                    ),
                    const PopupMenuItem(
                      value: 'cancelled',
                      child: Text('Mark Cancelled'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Delete',
                        style: TextStyle(color: Color(0xFFFF5252)),
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.access_time_rounded,
                text: '${formatTime(start)} – ${formatTime(end)}',
              ),
              _InfoChip(
                icon: Icons.groups_rounded,
                text: '$studentCount students',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: Color(0xFFB0B5D3),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  teacher,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB0B5D3),
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel(status),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 5, color: Color(0xFF9D6BFF)),
          const SizedBox(width: 7),
          Icon(icon, size: 15, color: const Color(0xFF9D6BFF)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB0B5D3),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _monthNameStatic(int month) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  return months[month - 1];
}
