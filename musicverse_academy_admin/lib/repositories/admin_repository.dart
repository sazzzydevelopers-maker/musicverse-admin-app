import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_model.dart';

class AdminRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Fetch admin document by UID from the live 'admin' collection
  Future<AdminModel?> getAdminById(String uid) async {
    try {
      final docSnapshot = await _firestore.collection('admin').doc(uid).get();
      if (docSnapshot.exists && docSnapshot.data() != null) {
        return AdminModel.fromFirestore(docSnapshot);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch admin data: $e');
    }
  }

  // Stream admin data in real-time
  Stream<AdminModel?> streamAdmin(String uid) {
    return _firestore.collection('admin').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return AdminModel.fromFirestore(doc);
      }
      return null;
    });
  }
}
