import 'package:cloud_firestore/cloud_firestore.dart';

class FeePaymentModel {
  final String paymentId;
  final String uid;
  final String studentName;
  final String status;
  final double monthlyFee;
  final DateTime? joinDate;
  final DateTime? lastPaymentDate;
  final DateTime? nextDueDate;
  final DateTime? paymentDate;
  final DateTime? updatedAt;

  FeePaymentModel({
    required this.paymentId,
    required this.uid,
    required this.studentName,
    required this.status,
    required this.monthlyFee,
    this.joinDate,
    this.lastPaymentDate,
    this.nextDueDate,
    this.paymentDate,
    this.updatedAt,
  });

  factory FeePaymentModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return FeePaymentModel(
      paymentId: doc.id,
      uid: data['uid'] ?? '',
      studentName: data['studentName'] ?? '',
      status: data['status'] ?? 'pending',
      monthlyFee: (data['monthlyFee'] is int)
          ? (data['monthlyFee'] as int).toDouble()
          : (data['monthlyFee'] ?? 0.0) as double,
      joinDate: (data['joinDate'] as Timestamp?)?.toDate(),
      lastPaymentDate: (data['lastPaymentDate'] as Timestamp?)?.toDate(),
      nextDueDate: (data['nextDueDate'] as Timestamp?)?.toDate(),
      paymentDate: (data['paymentDate'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'studentName': studentName,
      'status': status,
      'monthlyFee': monthlyFee,
      'joinDate': joinDate != null ? Timestamp.fromDate(joinDate!) : null,
      'lastPaymentDate': lastPaymentDate != null
          ? Timestamp.fromDate(lastPaymentDate!)
          : null,
      'nextDueDate': nextDueDate != null
          ? Timestamp.fromDate(nextDueDate!)
          : null,
      'paymentDate': paymentDate != null
          ? Timestamp.fromDate(paymentDate!)
          : null,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
