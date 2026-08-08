import 'package:flutter/foundation.dart';
import '../models/student_model.dart';
import '../repositories/student_repository.dart';

class StudentProvider extends ChangeNotifier {
  final StudentRepository _studentRepository = StudentRepository();

  List<StudentModel> _students = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedStatusFilter = 'All';

  List<StudentModel> get students {
    var filtered = _students;

    // Filter by status if specified
    if (_selectedStatusFilter != 'All') {
      filtered = filtered
          .where(
            (s) =>
                s.accountStatus.toLowerCase() ==
                _selectedStatusFilter.toLowerCase(),
          )
          .toList();
    }

    // Filter by search query (Name, Email, or Student ID)
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((s) {
        return s.firstName.toLowerCase().contains(query) ||
            s.lastName.toLowerCase().contains(query) ||
            s.email.toLowerCase().contains(query) ||
            s.studentId.toLowerCase().contains(query);
      }).toList();
    }

    return filtered;
  }

  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String get selectedStatusFilter => _selectedStatusFilter;

  StudentProvider() {
    listenToStudents();
  }

  // Subscribe to live real-time stream from 'user' collection
  void listenToStudents() {
    _isLoading = true;
    notifyListeners();

    _studentRepository.streamStudents().listen(
      (studentList) {
        _students = studentList;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  // Update search query state
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // Update status filter state
  void setStatusFilter(String status) {
    _selectedStatusFilter = status;
    notifyListeners();
  }

  // Activate or Deactivate a student account
  Future<void> toggleStudentStatus(String uid, String currentStatus) async {
    try {
      String newStatus = currentStatus.toLowerCase() == 'active'
          ? 'inactive'
          : 'active';
      await _studentRepository.updateAccountStatus(uid, newStatus);
    } catch (e) {
      debugPrint('Error toggling student status: $e');
    }
  }
}
