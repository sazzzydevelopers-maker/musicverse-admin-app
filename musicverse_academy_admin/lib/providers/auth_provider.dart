import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/admin_model.dart';
import '../repositories/admin_repository.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AdminRepository _adminRepository = AdminRepository();

  User? _firebaseUser;
  AdminModel? _adminModel;
  bool _isLoading = false;
  String? _errorMessage;

  User? get firebaseUser => _firebaseUser;
  AdminModel? get adminModel => _adminModel;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _firebaseUser != null && _adminModel != null;

  AuthProvider() {
    _initAuthListener();
  }

  // Listen to Firebase Auth state changes
  void _initAuthListener() {
    _auth.authStateChanges().listen((user) async {
      _firebaseUser = user;
      if (user != null) {
        await fetchAdminProfile(user.uid);
      } else {
        _adminModel = null;
      }
      notifyListeners();
    });
  }

  // Fetch admin details from the live 'admin' collection
  Future<void> fetchAdminProfile(String uid) async {
    try {
      _adminModel = await _adminRepository.getAdminByAuthUid(uid);
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // Admin Login with Email & Password
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Authenticate with Firebase Auth
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      if (userCredential.user != null) {
        String uid = userCredential.user!.uid;

        // 2. Verify existence and permissions in the live 'admin' collection
        AdminModel? admin = await _adminRepository.getAdminByAuthUid(uid);

        if (admin == null) {
          await _auth.signOut();

          _errorMessage = 'Access Denied: You are not authorized as an admin.';

          _isLoading = false;
          notifyListeners();

          return false;
        }

        _adminModel = admin;
        _firebaseUser = userCredential.user;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _isLoading = false;
      notifyListeners();
      return false;
    } on FirebaseAuthException catch (e) {
      _errorMessage = e.message ?? 'Authentication failed.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Admin Logout
  Future<void> logout() async {
    await _auth.signOut();
    _adminModel = null;
    _firebaseUser = null;
    notifyListeners();
  }
}
