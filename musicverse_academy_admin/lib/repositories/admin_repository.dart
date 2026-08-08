import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_model.dart';

class AdminRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<AdminModel?> getAdminByAuthUid(String uid) async {
    try {
      final querySnapshot = await _firestore
          .collection('admin')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return AdminModel.fromFirestore(querySnapshot.docs.first);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
