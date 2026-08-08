import 'package:cloud_firestore/cloud_firestore.dart';

class StudentModel {
  final String uid;
  final String studentId;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String address;
  final String gender;
  final String course;
  final String accountStatus;
  final String feeStatus;
  final String profilePhoto;
  final double monthlyFee;
  final int presentDays;
  final int absentDays;
  final dynamic
  practiceProgress; // Can be Map or String/int depending on legacy data
  final dynamic todayAttendance; // Can be bool or String
  final DateTime? dateOfBirth;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  StudentModel({
    required this.uid,
    required this.studentId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.address,
    required this.gender,
    required this.course,
    required this.accountStatus,
    required this.feeStatus,
    required this.profilePhoto,
    required this.monthlyFee,
    required this.presentDays,
    required this.absentDays,
    this.practiceProgress,
    this.todayAttendance,
    this.dateOfBirth,
    this.createdAt,
    this.updatedAt,
  });

  factory StudentModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return StudentModel(
      uid: data['uid'] ?? doc.id,
      studentId: data['studentId'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      address: data['address'] ?? '',
      gender: data['gender'] ?? '',
      course: data['course'] ?? '',
      accountStatus: data['accountStatus'] ?? 'active',
      feeStatus: data['feeStatus'] ?? 'pending',
      profilePhoto: data['profilePhoto'] ?? '',
      monthlyFee: (data['monthlyFee'] is int)
          ? (data['monthlyFee'] as int).toDouble()
          : (data['monthlyFee'] ?? 0.0) as double,
      presentDays: data['presentDays'] ?? 0,
      absentDays: data['absentDays'] ?? 0,
      practiceProgress: data['practiceProgress'],
      todayAttendance: data['todayAttendance'],
      dateOfBirth: (data['dateOfBirth'] is Timestamp)
          ? (data['dateOfBirth'] as Timestamp).toDate()
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'studentId': studentId,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'address': address,
      'gender': gender,
      'course': course,
      'accountStatus': accountStatus,
      'feeStatus': feeStatus,
      'profilePhoto': profilePhoto,
      'monthlyFee': monthlyFee,
      'presentDays': presentDays,
      'absentDays': absentDays,
      'practiceProgress': practiceProgress,
      'todayAttendance': todayAttendance,
      'dateOfBirth': dateOfBirth != null
          ? Timestamp.fromDate(dateOfBirth!)
          : null,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
