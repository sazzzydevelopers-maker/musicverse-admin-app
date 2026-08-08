import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fee_payment_model.dart';

class PaymentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionName = 'feePayments';

  // Stream all fee payment records in real-time
  Stream<List<FeePaymentModel>> streamPayments() {
    return _firestore.collection(_collectionName).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => FeePaymentModel.fromFirestore(doc))
          .toList();
    });
  }

  // Stream payments associated with a specific student UID
  Stream<List<FeePaymentModel>> streamPaymentsForStudent(String uid) {
    return _firestore
        .collection(_collectionName)
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => FeePaymentModel.fromFirestore(doc))
              .toList();
        });
  }

  // Add or update a payment record
  Future<void> savePayment(FeePaymentModel payment) async {
    try {
      final docRef = payment.paymentId.isNotEmpty
          ? _firestore.collection(_collectionName).doc(payment.paymentId)
          : _firestore.collection(_collectionName).doc();

      final data = payment.toMap();
      if (payment.paymentId.isEmpty) {
        data['joinDate'] = FieldValue.serverTimestamp();
      }

      await docRef.set(data, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to save payment record: $e');
    }
  }
}
