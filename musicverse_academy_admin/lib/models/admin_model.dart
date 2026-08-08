import 'package:cloud_firestore/cloud_firestore.dart';

class AdminModel {
  final String uid;
  final String email;
  final String firstname;
  final String lastname;
  final String phone;
  final String role;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  AdminModel({
    required this.uid,
    required this.email,
    required this.firstname,
    required this.lastname,
    required this.phone,
    required this.role,
    this.createdAt,
    this.lastLoginAt,
  });

  factory AdminModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return AdminModel(
      uid: data['uid'] ?? doc.id,
      email: data['email'] ?? '',
      firstname: data['firstname'] ?? '',
      lastname: data['lastname'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'firstname': firstname,
      'lastname': lastname,
      'phone': phone,
      'role': role,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'lastLoginAt': lastLoginAt != null
          ? Timestamp.fromDate(lastLoginAt!)
          : null,
    };
  }
}
