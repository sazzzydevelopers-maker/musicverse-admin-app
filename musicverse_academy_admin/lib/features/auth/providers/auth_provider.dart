import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:musicverse_academy_admin/features/auth/services/auth_service.dart';
import 'package:musicverse_academy_admin/models/admin_model.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  fb.User? get currentUser => _authService.currentUser;

  Stream<fb.User?> get authStateChanges => _authService.authStateChanges;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Existing admin data
  AdminModel? _adminModel;
  AdminModel? get adminModel => _adminModel;

  // Check whether the current user is an authorized admin.
  bool get isAdminAuthorized {
    if (_adminModel == null) {
      return false;
    }

    final role = _adminModel!.role.toLowerCase();

    return role == 'admin';
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Firebase Authentication
      await _authService.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = _authService.currentUser;

      if (user == null) {
        _errorMessage = 'Unable to get the authenticated user.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Find the admin document using the Firebase Authentication UID.
      final adminSnapshot = await FirebaseFirestore.instance
          .collection('admin')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      // No matching admin document.
      if (adminSnapshot.docs.isEmpty) {
        await _authService.signOut();

        _adminModel = null;
        _errorMessage = 'You do not have administrator access.';

        _isLoading = false;
        notifyListeners();

        return false;
      }

      // Use your EXISTING AdminModel.fromFirestore() method.
      final adminDocument = adminSnapshot.docs.first;

      _adminModel = AdminModel.fromFirestore(adminDocument);

      // Check active status.

      // Check admin role.
      final role = _adminModel!.role.toLowerCase();

      if (role != 'admin') {
        await _authService.signOut();

        _adminModel = null;
        _errorMessage = 'You do not have administrator access.';

        _isLoading = false;
        notifyListeners();

        return false;
      }

      _isLoading = false;
      notifyListeners();

      return true;
    } on fb.FirebaseAuthException catch (e) {
      _errorMessage = _firebaseAuthErrorMessage(e);

      _isLoading = false;
      notifyListeners();

      return false;
    } catch (e) {
      _errorMessage = 'Unable to sign in. Please try again.';

      _isLoading = false;
      notifyListeners();

      return false;
    }
  }

  // Load admin information for an already authenticated user.
  Future<bool> loadAdminProfile() async {
    final user = _authService.currentUser;

    if (user == null) {
      _adminModel = null;
      notifyListeners();
      return false;
    }

    try {
      final adminSnapshot = await FirebaseFirestore.instance
          .collection('admin')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (adminSnapshot.docs.isEmpty) {
        _adminModel = null;
        notifyListeners();
        return false;
      }

      final adminDocument = adminSnapshot.docs.first;

      // Use your existing model.
      _adminModel = AdminModel.fromFirestore(adminDocument);

      final role = _adminModel!.role.toLowerCase();

      final authorized = role == 'admin';

      if (!authorized) {
        _adminModel = null;
        notifyListeners();
        return false;
      }

      notifyListeners();
      return true;
    } catch (e) {
      _adminModel = null;
      notifyListeners();
      return false;
    }
  }

  // Restore an existing Firebase login session.
  Future<bool> restoreAdminSession() async {
    final user = _authService.currentUser;

    if (user == null) {
      _adminModel = null;
      notifyListeners();
      return false;
    }

    return loadAdminProfile();
  }

  Future<bool> resetPassword(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.sendPasswordResetEmail(email);

      _isLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _errorMessage = 'Unable to send password reset email.';

      _isLoading = false;
      notifyListeners();

      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();

    _adminModel = null;
    _errorMessage = null;

    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  String _firebaseAuthErrorMessage(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Invalid email or password.';

      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'user-disabled':
        return 'This Firebase account has been disabled.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';

      default:
        return e.message ?? 'Unable to sign in. Please try again.';
    }
  }
}
