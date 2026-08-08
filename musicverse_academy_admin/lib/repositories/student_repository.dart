import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student_model.dart';

class StudentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'user';

  // Real-time stream of all students from the 'user' collection
  Stream<List<StudentModel>> streamStudents() {
    return _firestore.collection(_collectionName).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => StudentModel.fromFirestore(doc))
          .toList();
    });
  }

  // Fetch a single student by UID / Document ID
  Future<StudentModel?> getStudentById(String uid) async {
    try {
      final doc = await _firestore.collection(_collectionName).doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return StudentModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch student: $e');
    }
  }

  // Add a new student document to the 'user' collection
  Future<void> addStudent(StudentModel student) async {
    try {
      await _firestore
          .collection(_collectionName)
          .doc(student.uid)
          .set(student.toMap());
    } catch (e) {
      throw Exception('Failed to add student: $e');
    }
  }

  // Update an existing student record
  Future<void> updateStudent(
    String uid,
    Map<String, dynamic> updatedData,
  ) async {
    try {
      updatedData['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection(_collectionName).doc(uid).update(updatedData);
    } catch (e) {
      throw Exception('Failed to update student: $e');
    }
  }

  // Toggle or modify account status (Activate/Deactivate)
  Future<void> updateAccountStatus(String uid, String status) async {
    try {
      await _firestore.collection(_collectionName).doc(uid).update({
        'accountStatus': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update account status: $e');
    }
  }
}
