import 'package:cloud_firestore/cloud_firestore.dart';

class AdminModel {
  final String uid;
  final String email;
  final String firstname;
  final String lastname;
  final String phone;
  final String role;
  final bool isactive;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  AdminModel({
    required this.uid,
    required this.email,
    required this.firstname,
    required this.lastname,
    required this.phone,
    required this.role,
    required this.isactive,
    this.createdAt,
    this.lastLoginAt,
  });

  // Factory constructor to create an AdminModel from a Firestore Document snapshot
  factory AdminModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AdminModel(
      uid: data['uid'] ?? doc.id,
      email: data['email'] ?? '',
      firstname: data['firstname'] ?? '',
      lastname: data['lastname'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? 'admin',
      isactive: data['isactive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate(),
    );
  }

  // Convert AdminModel to Map for Firestore writing if needed
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'firstname': firstname,
      'lastname': lastname,
      'phone': phone,
      'role': role,
      'isactive': isactive,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'lastLoginAt': lastLoginAt != null
          ? Timestamp.fromDate(lastLoginAt!)
          : null,
    };
  }
}
