// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

// ============================================================================
// MUSICVERSE ACADEMY ADMIN — SINGLE DART FILE
// Requires: device_info_plus: ^12.4.0, firebase_auth, cloud_firestore, shared_preferences, go_router
// ============================================================================

/// The dashboard must call ensureSession() immediately after a successful
/// Firebase Auth login. Settings only attaches to the already-created session.
/// ---------------------------------------------------------------------------
class AdminSessionManager with WidgetsBindingObserver {
  AdminSessionManager._internal();

  static final AdminSessionManager instance = AdminSessionManager._internal();

  String? adminDocumentId;
  String? currentSessionId;

  DocumentReference<Map<String, dynamic>>? _adminRef;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _adminSubscription;
  Timer? _heartbeatTimer;
  Future<void> Function()? _onRemoteLogout;
  bool _isSigningOut = false;
  bool _observerRegistered = false;
  String? _cachedDeviceName;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String _sessionStorageKey(String uid) => 'musicverse_admin_session_$uid';

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      return value.trim().toLowerCase() == 'true';
    }
    if (value is num) return value != 0;
    return false;
  }

  Future<DocumentReference<Map<String, dynamic>>?> _findAdminDocument(
    User user,
  ) async {
    final query = await _firestore
        .collection('admin')
        .where('uid', isEqualTo: user.uid)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return query.docs.first.reference;
  }

  List<Map<String, dynamic>> _readSessions(Map<String, dynamic> adminData) {
    final raw = adminData['activeSessions'];

    if (raw is! List) return <Map<String, dynamic>>[];

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  bool _isSessionFresh(Map<String, dynamic> data) {
    if (_asBool(data['revoked']) || !_asBool(data['isActive'])) {
      return false;
    }

    final lastActive = data['lastActiveAt'];

    if (lastActive is Timestamp) {
      final age = DateTime.now().difference(lastActive.toDate());
      return age <= const Duration(minutes: 2);
    }

    return false;
  }

  Map<String, dynamic> _newSession(
    String sessionId,
    User user,
    DocumentReference<Map<String, dynamic>> adminRef,
    String deviceName,
  ) {
    final now = Timestamp.now();

    return <String, dynamic>{
      'sessionId': sessionId,
      'uid': user.uid,
      'adminDocumentId': adminRef.id,
      'deviceName': deviceName,
      'platform': _platformName(),
      'ipAddress': 'Unavailable',
      'createdAt': now,
      'lastActiveAt': now,
      'isActive': true,
      'revoked': false,
    };
  }

  Future<bool> ensureSession({Future<void> Function()? onRemoteLogout}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    _onRemoteLogout = onRemoteLogout;

    try {
      final adminRef = await _findAdminDocument(user);
      if (adminRef == null) {
        await _forceLocalLogout();
        return false;
      }

      adminDocumentId = adminRef.id;
      _adminRef = adminRef;

      final prefs = await SharedPreferences.getInstance();
      final storageKey = _sessionStorageKey(user.uid);
      final storedSessionId = prefs.getString(storageKey)?.trim();

      String? resolvedSessionId;
      final deviceName = await _getDeviceName();

      // One transaction handles creation/refresh/cleanup atomically.
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(adminRef);
        if (!snapshot.exists) {
          throw StateError('Admin document does not exist.');
        }

        final data = snapshot.data() ?? <String, dynamic>{};
        if (!_asBool(data['isactive'])) {
          throw StateError('Admin account is inactive.');
        }

        final now = Timestamp.now();
        final sessions = _readSessions(data);

        // Remove old/revoked sessions. This prevents old devices from being
        // shown after a later login. Fresh sessions from other devices stay.
        final freshSessions = sessions
            .where(_isSessionFresh)
            .map((session) => Map<String, dynamic>.from(session))
            .toList();

        Map<String, dynamic>? existing;
        if (storedSessionId != null && storedSessionId.isNotEmpty) {
          for (final session in freshSessions) {
            if (session['sessionId']?.toString() == storedSessionId &&
                session['uid']?.toString() == user.uid) {
              existing = session;
              break;
            }
          }
        }

        resolvedSessionId =
            existing?['sessionId']?.toString() ??
            '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(999999)}';

        final currentSession = existing == null
            ? _newSession(resolvedSessionId!, user, adminRef, deviceName)
            : <String, dynamic>{
                ...existing,
                'sessionId': resolvedSessionId,
                'uid': user.uid,
                'adminDocumentId': adminRef.id,
                'deviceName': deviceName,
                'platform': _platformName(),
                'isActive': true,
                'revoked': false,
                'lastActiveAt': now,
              };

        final updatedSessions = <Map<String, dynamic>>[];
        bool replaced = false;

        for (final session in freshSessions) {
          if (session['sessionId']?.toString() == resolvedSessionId) {
            if (!replaced) {
              updatedSessions.add(currentSession);
              replaced = true;
            }
          } else {
            updatedSessions.add(session);
          }
        }

        if (!replaced) {
          updatedSessions.add(currentSession);
        }

        transaction.update(adminRef, {
          'activeSessions': updatedSessions,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (resolvedSessionId == null) return false;

      await prefs.setString(storageKey, resolvedSessionId!);

      _adminRef = adminRef;
      adminDocumentId = adminRef.id;
      currentSessionId = resolvedSessionId;

      await _activateSession(onRemoteLogout: onRemoteLogout);
      return true;
    } catch (e) {
      debugPrint('Admin session initialization error: $e');
      if (e is StateError && e.message == 'Admin account is inactive.') {
        await _forceLocalLogout();
      }
      return false;
    }
  }

  /// Settings never creates a new session.
  /// It only attaches to the session already created by Dashboard/Login.
  Future<bool> attachExistingSession({
    Future<void> Function()? onRemoteLogout,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    _onRemoteLogout ??= onRemoteLogout;

    try {
      DocumentReference<Map<String, dynamic>>? adminRef = _adminRef;

      if (adminRef == null || adminDocumentId == null) {
        adminRef = await _findAdminDocument(user);
      }

      if (adminRef == null) return false;

      final adminData = (await adminRef.get()).data() ?? <String, dynamic>{};

      if (!_asBool(adminData['isactive'])) {
        await _forceLocalLogout();
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final storedSessionId = prefs
          .getString(_sessionStorageKey(user.uid))
          ?.trim();

      final sessionId =
          currentSessionId ??
          (storedSessionId == null || storedSessionId.isEmpty
              ? null
              : storedSessionId);

      if (sessionId == null) return false;

      final sessions = _readSessions(adminData);

      Map<String, dynamic>? existing;

      for (final session in sessions) {
        if (session['sessionId']?.toString() == sessionId &&
            session['uid']?.toString() == user.uid) {
          existing = session;
          break;
        }
      }

      if (existing == null || !_isSessionFresh(existing)) {
        return false;
      }

      final deviceName = await _getDeviceName();
      final refreshed = <String, dynamic>{
        ...existing,
        'isActive': true,
        'revoked': false,
        'lastActiveAt': Timestamp.now(),
        'deviceName': deviceName,
        'platform': _platformName(),
      };

      final updatedSessions = sessions
          .map(
            (session) => session['sessionId']?.toString() == sessionId
                ? refreshed
                : session,
          )
          .toList();

      await adminRef.update({
        'activeSessions': updatedSessions,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _adminRef = adminRef;
      adminDocumentId = adminRef.id;
      currentSessionId = sessionId;

      await _activateSession(onRemoteLogout: onRemoteLogout);
      return true;
    } catch (e) {
      debugPrint('Unable to attach existing admin session: $e');
      return false;
    }
  }

  Future<void> _activateSession({
    Future<void> Function()? onRemoteLogout,
  }) async {
    final adminRef = _adminRef;
    if (adminRef == null || currentSessionId == null) return;

    _onRemoteLogout ??= onRemoteLogout;

    await _adminSubscription?.cancel();

    _adminSubscription = adminRef.snapshots().listen(
      (snapshot) {
        if (!snapshot.exists) {
          _handleRemoteLogout();
          return;
        }

        final data = snapshot.data();

        if (data == null) {
          _handleRemoteLogout();
          return;
        }

        final sessions = _readSessions(data);

        Map<String, dynamic>? current;

        for (final session in sessions) {
          if (session['sessionId']?.toString() == currentSessionId &&
              session['uid']?.toString() ==
                  FirebaseAuth.instance.currentUser?.uid) {
            current = session;
            break;
          }
        }

        // If another device removed this session from activeSessions,
        // immediately sign out this device.
        if (current == null || !_isSessionFresh(current)) {
          _handleRemoteLogout();
        }
      },
      onError: (Object error) {
        debugPrint('Admin session listener error: $error');
      },
    );

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => updateActivity(),
    );

    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }

    await updateActivity();
  }

  Future<void> updateActivity() async {
    final adminRef = _adminRef;
    final user = FirebaseAuth.instance.currentUser;
    final sessionId = currentSessionId;

    if (adminRef == null ||
        user == null ||
        sessionId == null ||
        _isSigningOut) {
      return;
    }

    try {
      final deviceName = await _getDeviceName();
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(adminRef);

        if (!snapshot.exists) return;

        final data = snapshot.data() ?? <String, dynamic>{};
        final sessions = _readSessions(data);

        final updatedSessions = <Map<String, dynamic>>[];

        for (final session in sessions) {
          if (session['sessionId']?.toString() == sessionId &&
              session['uid']?.toString() == user.uid) {
            updatedSessions.add({
              ...session,
              'isActive': true,
              'revoked': false,
              'lastActiveAt': Timestamp.now(),
              'deviceName': deviceName,
              'platform': _platformName(),
            });
          } else {
            updatedSessions.add(session);
          }
        }

        transaction.update(adminRef, {
          'activeSessions': updatedSessions,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('Admin session heartbeat failed: $e');
    }
  }

  Future<void> logoutCurrentSession() async {
    if (_isSigningOut) return;

    _isSigningOut = true;

    final adminRef = _adminRef;
    final user = FirebaseAuth.instance.currentUser;
    final sessionId = currentSessionId;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _adminSubscription?.cancel();
    _adminSubscription = null;

    try {
      // IMPORTANT: Firestore deletion must succeed before Auth is signed out.
      // This guarantees that logout cannot leave a previous session behind.
      if (adminRef != null && sessionId != null) {
        await _removeSessionFromAdmin(adminRef, sessionId);
      }

      final prefs = await SharedPreferences.getInstance();
      if (user != null) {
        await prefs.remove(_sessionStorageKey(user.uid));
      }

      await FirebaseAuth.instance.signOut();
      _clearInMemoryState();
    } catch (e) {
      debugPrint(
        'Logout failed; Firestore session was not confirmed deleted: $e',
      );
      _isSigningOut = false;
      rethrow;
    }
  }

  Future<void> logoutOtherSessions() async {
    final adminRef = _adminRef;
    final currentId = currentSessionId;

    if (adminRef == null || currentId == null) return;

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(adminRef);

      if (!snapshot.exists) return;

      final data = snapshot.data() ?? <String, dynamic>{};
      final sessions = _readSessions(data);

      final remaining = sessions
          .where((session) => session['sessionId']?.toString() == currentId)
          .toList();

      if (remaining.isEmpty) {
        throw StateError('Current admin session was not found.');
      }

      transaction.update(adminRef, {
        'activeSessions': remaining,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> logoutSpecificSession(String sessionId) async {
    final adminRef = _adminRef;
    final targetId = sessionId.trim();

    if (adminRef == null || targetId.isEmpty) return;

    // This method is for OTHER devices only. The current device must use
    // logoutCurrentSession(), because that also signs out Firebase Auth.
    if (targetId == currentSessionId) {
      throw StateError(
        'The current device must use Logout from Current Device.',
      );
    }

    await _removeSessionFromAdmin(adminRef, targetId);
  }

  Future<void> _removeSessionFromAdmin(
    DocumentReference<Map<String, dynamic>> adminRef,
    String sessionId,
  ) async {
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(adminRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? <String, dynamic>{};
      final sessions = _readSessions(data);
      final remaining = sessions
          .where((session) => session['sessionId']?.toString() != sessionId)
          .toList();

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // If this was the last session, remove the field completely.
      // On the next login a brand-new activeSessions field is created.
      if (remaining.isEmpty) {
        updates['activeSessions'] = FieldValue.delete();
      } else {
        updates['activeSessions'] = remaining;
      }

      transaction.update(adminRef, updates);
    });
  }

  Future<void> _handleRemoteLogout() async {
    if (_isSigningOut) return;

    _isSigningOut = true;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await _adminSubscription?.cancel();
    _adminSubscription = null;

    final user = FirebaseAuth.instance.currentUser;

    try {
      final prefs = await SharedPreferences.getInstance();

      if (user != null) {
        await prefs.remove(_sessionStorageKey(user.uid));
      }
    } catch (_) {}

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    final callback = _onRemoteLogout;

    _clearInMemoryState();

    if (callback != null) {
      await callback();
    }
  }

  Future<void> _forceLocalLogout() async {
    final user = FirebaseAuth.instance.currentUser;

    try {
      final prefs = await SharedPreferences.getInstance();

      if (user != null) {
        await prefs.remove(_sessionStorageKey(user.uid));
      }
    } catch (_) {}

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    _clearInMemoryState();
  }

  void _clearInMemoryState() {
    currentSessionId = null;
    adminDocumentId = null;
    _adminRef = null;
    _onRemoteLogout = null;
    _isSigningOut = false;
  }

  String _platformName() {
    if (kIsWeb) return 'Web';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }

  Future<String> _getDeviceName() async {
    if (_cachedDeviceName != null && _cachedDeviceName!.trim().isNotEmpty) {
      return _cachedDeviceName!;
    }

    try {
      if (kIsWeb) {
        _cachedDeviceName = 'Web Browser';
        return _cachedDeviceName!;
      }

      final info = DeviceInfoPlugin();

      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await info.androidInfo;
        final manufacturer = android.manufacturer.trim();
        final model = android.model.trim();

        if (manufacturer.isNotEmpty && model.isNotEmpty) {
          _cachedDeviceName = '${_capitalize(manufacturer)} $model';
        } else if (manufacturer.isNotEmpty) {
          _cachedDeviceName = _capitalize(manufacturer);
        } else if (model.isNotEmpty) {
          _cachedDeviceName = model;
        } else {
          _cachedDeviceName = 'Android Device';
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = await info.iosInfo;
        final name = ios.name.trim();
        final model = ios.model.trim();
        _cachedDeviceName = name.isNotEmpty
            ? name
            : (model.isNotEmpty ? model : 'iPhone');
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        final windows = await info.windowsInfo;
        _cachedDeviceName = windows.computerName.trim().isNotEmpty
            ? windows.computerName.trim()
            : 'Windows PC';
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        final mac = await info.macOsInfo;
        _cachedDeviceName = mac.computerName.trim().isNotEmpty
            ? mac.computerName.trim()
            : 'Mac';
      } else if (defaultTargetPlatform == TargetPlatform.linux) {
        final linux = await info.linuxInfo;
        _cachedDeviceName = linux.name.trim().isNotEmpty
            ? linux.name.trim()
            : 'Linux PC';
      } else {
        _cachedDeviceName = _platformName();
      }
    } catch (e) {
      debugPrint('Unable to read device name: $e');
      _cachedDeviceName = _platformName();
    }

    return _cachedDeviceName!;
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      updateActivity();
    }
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _adminSubscription?.cancel();

    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }

    _heartbeatTimer = null;
    _adminSubscription = null;
    _adminRef = null;
  }
}

/// AppColors matching the MusicVerse Academy design system.
class AppColors {
  static const Color background = Color(0xFF0D1020);
  static const Color cards = Color(0xFF171C35);
  static const Color primary = Color(0xFF7C4DFF);
  static const Color secondary = Color(0xFF9D6BFF);
  static const Color success = Color(0xFF00E676);
  static const Color error = Color(0xFFFF5252);
  static const Color secondaryText = Color(0xFFB0B5D3);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFF232A4E);
}

// ============================================================================
// ADMIN LOGIN
// ============================================================================

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Enter your email and password.');
      return;
    }

    setState(() => _loading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'no-user',
          message: 'Firebase did not return a signed-in user.',
        );
      }

      final sessionCreated = await AdminSessionManager.instance.ensureSession(
        onRemoteLogout: () async {
          if (mounted) context.go('/login');
        },
      );

      if (!sessionCreated) {
        throw FirebaseAuthException(
          code: 'admin-session-failed',
          message: 'This Firebase account is not an active admin account.',
        );
      }

      if (!mounted) return;
      context.go('/dashboard');
    } on FirebaseAuthException catch (e) {
      _showError(_friendlyAuthError(e));
    } catch (e) {
      debugPrint('Admin login error: $e');
      _showError('Unable to sign in. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      case 'admin-session-failed':
        return e.message ?? 'This account is not an active admin account.';
      default:
        return e.message ?? 'Unable to sign in.';
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.cards,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.admin_panel_settings,
                    color: AppColors.primary,
                    size: 64,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'MusicVerse Admin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                  const SizedBox(height: 28),
                  _loginField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  _loginField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.textWhite,
                              ),
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textWhite),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.secondaryText),
        prefixIcon: Icon(icon, color: AppColors.secondary),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}

// ============================================================================
// ADMIN DASHBOARD
// ============================================================================

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  String _adminName = 'Administrator';
  String _adminId = 'Loading...';

  @override
  void initState() {
    super.initState();
    _initializeDashboardSession();
  }

  Future<void> _initializeDashboardSession() async {
    final success = await AdminSessionManager.instance.ensureSession(
      onRemoteLogout: () async {
        if (mounted) context.go('/login');
      },
    );

    if (!mounted) return;

    if (!success) {
      context.go('/login');
      return;
    }

    await _loadAdminHeader();
  }

  Future<void> _loadAdminHeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('admin')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (!mounted) return;

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();
        setState(() {
          _adminName =
              ((data['fullname'] ??
                      data['firstname'] ??
                      user.displayName ??
                      'Administrator')
                  .toString()
                  .trim()
                  .isEmpty)
              ? 'Administrator'
              : (data['fullname'] ??
                        data['firstname'] ??
                        user.displayName ??
                        'Administrator')
                    .toString()
                    .trim();
          _adminId = (data['adminId'] ?? 'N/A').toString();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        context.go('/login');
      }
    } catch (e) {
      debugPrint('Dashboard admin profile error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await AdminSessionManager.instance.logoutCurrentSession();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cards,
        elevation: 0,
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.secondary,
            ),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: AppColors.error),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                await AdminSessionManager.instance.updateActivity();
                await _loadAdminHeader();
              },
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Welcome, $_adminName',
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Admin ID: $_adminId',
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _dashboardCard(
                    icon: Icons.circle,
                    title: 'Active Session',
                    value: 'Connected to Firestore',
                    color: AppColors.success,
                  ),
                  const SizedBox(height: 14),
                  _dashboardCard(
                    icon: Icons.devices,
                    title: 'Current Device',
                    value:
                        '${AdminSessionManager.instance.currentSessionId ?? 'Creating session...'}',
                    color: AppColors.secondary,
                  ),
                  const SizedBox(height: 14),
                  _dashboardCard(
                    icon: Icons.security,
                    title: 'Account',
                    value: 'Active Admin',
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textWhite,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _dashboardCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cards,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Main Settings Screen with Responsive Layout (Desktop Two-Column / Mobile Stack)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedCategoryIndex = 0;
  bool _isSaving = false;

  // Device/session display state.
  String? _adminDocumentId;
  String? _currentSessionId;
  bool _isSigningOut = false;

  // Form Controllers for Academy Settings
  final TextEditingController _academyNameController = TextEditingController(
    text: 'MusicVerse Academy',
  );
  final TextEditingController _academyEmailController = TextEditingController(
    text: 'contact@musicverse.edu',
  );
  final TextEditingController _academyPhoneController = TextEditingController(
    text: '+1 (555) 382-9481',
  );
  final TextEditingController _academyAddressController = TextEditingController(
    text: '124 Crescendo Avenue',
  );
  final TextEditingController _academyCityController = TextEditingController(
    text: 'Austin',
  );
  final TextEditingController _academyStateController = TextEditingController(
    text: 'TX',
  );
  final TextEditingController _academyCountryController = TextEditingController(
    text: 'United States',
  );
  final TextEditingController _academyWebsiteController = TextEditingController(
    text: 'https://musicverse.edu',
  );

  // Application Preferences States
  String _selectedCurrency = 'USD (\$Mer)';
  String _selectedDateFormat = 'MM/DD/YYYY';
  String _selectedTimeFormat = '12-Hour';
  final int _defaultPageSize = 25;
  bool _confirmBeforeDelete = true;

  // Notification Toggles
  bool _notifPayments = true;
  bool _notifNewStudents = true;
  bool _notifAttendance = false;
  bool _notifSystem = true;

  // Appearance Settings
  String _themeMode = 'Dark';
  bool _compactMode = false;

  final List<Map<String, dynamic>> _categories = [
    {'title': 'Academy', 'icon': Icons.school},
    {'title': 'Admin Profile', 'icon': Icons.person},
    {'title': 'Appearance', 'icon': Icons.palette},
    {'title': 'Notifications', 'icon': Icons.notifications},
    {'title': 'Security', 'icon': Icons.security},
    {'title': 'Preferences', 'icon': Icons.settings_applications},
    {'title': 'User Data Status', 'icon': Icons.bolt},
  ];

  Future<void> Function()? get _handleRemoteSessionRevocation => null;

  @override
  void initState() {
    super.initState();
    _initializeCurrentDeviceSession();
  }

  /// Connect Security to the current admin session.
  ///
  /// Normally the session is created immediately after successful login.
  /// If the dashboard-created session is missing, ensureSession() creates one
  /// in the existing admin document's activeSessions field as a recovery path.
  Future<void> _initializeCurrentDeviceSession() async {
    try {
      var ready = await AdminSessionManager.instance.attachExistingSession(
        onRemoteLogout: _handleRemoteSessionRevocation,
      );

      // Recovery path for a stale/missing local session.
      // This writes to:
      // admin/{adminDocumentId}.activeSessions
      // It does not create another collection or subcollection.
      if (!ready) {
        ready = await AdminSessionManager.instance.ensureSession(
          onRemoteLogout: _handleRemoteSessionRevocation,
        );
      }

      if (!mounted) return;

      setState(() {
        _adminDocumentId = AdminSessionManager.instance.adminDocumentId;
        _currentSessionId = AdminSessionManager.instance.currentSessionId;
      });

      if (!ready) {
        debugPrint('Unable to register the current admin device session.');
      }
    } catch (e) {
      debugPrint('Unable to initialize admin device session in Settings: $e');
    }
  }

  IconData _getDeviceIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
      case 'ios':
        return Icons.smartphone;
      case 'windows':
      case 'linux':
        return Icons.computer;
      case 'macos':
        return Icons.laptop_mac;
      case 'web':
        return Icons.language;
      default:
        return Icons.devices;
    }
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.trim().toLowerCase() == 'true';
    if (value is num) return value != 0;
    return false;
  }

  String _formatLastActive(dynamic value) {
    final now = DateTime.now();

    if (value is Timestamp) {
      final timestamp = value.toDate();
      final difference = now.difference(timestamp);

      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inHours < 1) return '${difference.inMinutes} min ago';
      if (difference.inDays < 1) return '${difference.inHours} hours ago';
      if (difference.inDays == 1) return 'Yesterday';
      return '${difference.inDays} days ago';
    }

    if (value is DateTime) {
      final difference = now.difference(value);

      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inHours < 1) return '${difference.inMinutes} min ago';
      if (difference.inDays < 1) return '${difference.inHours} hours ago';
      if (difference.inDays == 1) return 'Yesterday';
      return '${difference.inDays} days ago';
    }

    return 'Recently';
  }

  bool _isSessionFresh(Map<String, dynamic> data) {
    if (_asBool(data['revoked']) || !_asBool(data['isActive'])) {
      return false;
    }

    final lastActive = data['lastActiveAt'];
    if (lastActive is! Timestamp) {
      return true;
    }

    final age = DateTime.now().difference(lastActive.toDate());
    return age <= const Duration(minutes: 2);
  }

  @override
  void dispose() {
    _academyNameController.dispose();
    _academyEmailController.dispose();
    _academyPhoneController.dispose();
    _academyAddressController.dispose();
    _academyCityController.dispose();
    _academyStateController.dispose();
    _academyCountryController.dispose();
    _academyWebsiteController.dispose();
    super.dispose();
  }

  Future<void> _refreshSettings() async {
    await _initializeCurrentDeviceSession();

    if (!mounted) return;

    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      // Save Academy Settings to Firestore under settings/academy
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('academy')
          .set({
            'name': _academyNameController.text.trim(),
            'email': _academyEmailController.text.trim(),
            'phone': _academyPhoneController.text.trim(),
            'address': _academyAddressController.text.trim(),
            'city': _academyCityController.text.trim(),
            'state': _academyStateController.text.trim(),
            'country': _academyCountryController.text.trim(),
            'website': _academyWebsiteController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // Save App Preferences and Notifications
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('app_preferences')
          .set({
            'currency': _selectedCurrency,
            'dateFormat': _selectedDateFormat,
            'timeFormat': _selectedTimeFormat,
            'pageSize': _defaultPageSize,
            'confirmDelete': _confirmBeforeDelete,
            'notifPayments': _notifPayments,
            'notifNewStudents': _notifNewStudents,
            'notifAttendance': _notifAttendance,
            'notifSystem': _notifSystem,
            'themeMode': _themeMode,
            'compactMode': _compactMode,
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings successfully updated!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to save settings. Please check your connection and try again.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cards,
        title: const Text(
          'Are you sure?',
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: const Text(
          'This device will be signed out and its Firestore session will be deleted.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Confirm',
              style: TextStyle(color: AppColors.textWhite),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout != true || _isSigningOut) return;

    _isSigningOut = true;

    try {
      // Removes the current session from the existing admin document
      // and signs out Firebase Auth.
      await AdminSessionManager.instance.logoutCurrentSession();

      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      _isSigningOut = false;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to complete logout. Please check your connection and try again.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cards,
        elevation: 0,
        leading: isDesktop ? null : const SizedBox(width: 72),
        title: const Text(
          'Settings Dashboard',
          style: TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.secondary),
            tooltip: 'Refresh',
            onPressed: _refreshSettings,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.error),
            tooltip: 'Logout',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manage your MusicVerse Academy administration preferences.',
                style: TextStyle(color: AppColors.secondaryText, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildNavigationPanel(width: 280),
                          const SizedBox(width: 24),
                          Expanded(child: _buildContentPanel()),
                        ],
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: 56,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _categories.length,
                              itemBuilder: (context, index) {
                                final isSelected =
                                    _selectedCategoryIndex == index;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ChoiceChip(
                                    selected: isSelected,
                                    label: Text(_categories[index]['title']),
                                    selectedColor: AppColors.primary,
                                    backgroundColor: AppColors.cards,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? AppColors.textWhite
                                          : AppColors.secondaryText,
                                    ),
                                    onSelected: (_) => setState(
                                      () => _selectedCategoryIndex = index,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(child: _buildContentPanel()),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationPanel({required double width}) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.cards,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _categories.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (context, index) {
          final isSelected = _selectedCategoryIndex == index;
          return ListTile(
            leading: Icon(
              _categories[index]['icon'],
              color: isSelected ? AppColors.primary : AppColors.secondaryText,
            ),
            title: Text(
              _categories[index]['title'],
              style: TextStyle(
                color: isSelected
                    ? AppColors.textWhite
                    : AppColors.secondaryText,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedTileColor: AppColors.primary.withOpacity(0.15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            onTap: () => setState(() => _selectedCategoryIndex = index),
          );
        },
      ),
    );
  }

  Widget _buildContentPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cards,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _categories[_selectedCategoryIndex]['title'],
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_selectedCategoryIndex != 6 && _selectedCategoryIndex != 4)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textWhite,
                  ),
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textWhite,
                          ),
                        )
                      : const Icon(Icons.save, size: 16),
                  label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                ),
            ],
          ),
          const Divider(color: AppColors.divider, height: 32),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.cards,
              onRefresh: _refreshSettings,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _getSelectedSectionWidget(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getSelectedSectionWidget() {
    switch (_selectedCategoryIndex) {
      case 0:
        return _buildAcademySection();
      case 1:
        return _buildAdminProfileSection();
      case 2:
        return _buildAppearanceSection();
      case 3:
        return _buildNotificationsSection();
      case 4:
        return _buildSecuritySection();
      case 5:
        return _buildPreferencesSection();
      case 6:
        return _buildFirebaseStatusSection();
      default:
        return Container();
    }
  }

  Widget _buildAcademySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField('Academy Name', _academyNameController),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField('Academy Email', _academyEmailController),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField('Academy Phone', _academyPhoneController),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField('Street Address', _academyAddressController),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildTextField('City', _academyCityController)),
            const SizedBox(width: 16),
            Expanded(child: _buildTextField('State', _academyStateController)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField('Country', _academyCountryController),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField('Website', _academyWebsiteController),
            ),
          ],
        ),
      ],
    );
  }

  Future<Map<String, dynamic>> _loadAdminProfileData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return {
        'adminDocumentId': 'N/A',
        'adminId': 'N/A',
        'firstname': 'N/A',
        'lastname': 'Not set',
        'fullname': 'N/A',
        'email': 'N/A',
        'phone': 'Not set',
        'role': 'N/A',
        'isactive': false,
        'uid': 'N/A',
        'emailVerified': false,
        'displayName': 'N/A',
        'photoURL': '',
        'createdAt': null,
        'updatedAt': null,
        'lastSignIn': null,
      };
    }

    final adminQuery = await FirebaseFirestore.instance
        .collection('admin')
        .where('uid', isEqualTo: user.uid)
        .limit(1)
        .get();

    DocumentSnapshot<Map<String, dynamic>>? adminSnapshot;

    if (adminQuery.docs.isNotEmpty) {
      adminSnapshot = adminQuery.docs.first;
    }

    final adminData = adminSnapshot?.data() ?? <String, dynamic>{};

    String adminId = '';

    if (adminSnapshot == null) {
      throw StateError(
        'No admin document exists for the signed-in Firebase UID.',
      );
    }

    final existingAdminId = adminData['adminId'];
    if (existingAdminId is String && existingAdminId.trim().isNotEmpty) {
      adminId = existingAdminId.trim();
    } else {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final random = Random.secure();
      final code = List.generate(
        6,
        (_) => chars[random.nextInt(chars.length)],
      ).join();

      adminId = 'SZYD-ADM-$code';

      await adminSnapshot.reference.set({
        'adminId': adminId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      adminData['adminId'] = adminId;
      adminData['updatedAt'] = Timestamp.now();
    }

    final firstname = (adminData['firstname'] ?? '').toString().trim();
    final lastname = (adminData['lastname'] ?? '').toString().trim();
    final fullname = (adminData['fullname'] ?? '').toString().trim();
    final email = (adminData['email'] ?? user.email ?? '').toString().trim();
    final phone =
        (adminData['phone'] ??
                adminData['phoneNumber'] ??
                user.phoneNumber ??
                '')
            .toString()
            .trim();
    final role = (adminData['role'] ?? 'admin').toString().trim();
    final isActive = _asBool(adminData['isactive']);
    final displayName =
        (user.displayName ?? fullname).toString().trim().isNotEmpty
        ? (user.displayName ?? fullname).toString().trim()
        : (fullname.isNotEmpty
              ? fullname
              : (firstname.isNotEmpty
                    ? firstname
                    : 'MusicVerse Administrator'));

    final mergedAdminData = <String, dynamic>{
      ...adminData,
      'adminId': adminId,
      'email': email,
      'firstname': firstname,
      'lastname': lastname,
      'fullname': fullname,
      'phone': phone,
      'role': role,
      'isactive': isActive,
      'uid': user.uid,
      'emailVerified': user.emailVerified,
      'displayName': displayName,
      'photoURL': user.photoURL ?? adminData['photoURL'] ?? '',
      'createdAt': adminData['createdAt'],
      'updatedAt': adminData['updatedAt'],
      'lastSignIn': user.metadata.lastSignInTime,
      'adminDocumentId': adminSnapshot.id,
    };

    return mergedAdminData;
  }

  String _formatAdminDate(dynamic value) {
    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }

    if (date == null) return 'Not available';

    final localDate = date.toLocal();

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${localDate.year}-${twoDigits(localDate.month)}-${twoDigits(localDate.day)} '
        '${twoDigits(localDate.hour)}:${twoDigits(localDate.minute)}';
  }

  String _adminRoleLabel(dynamic value) {
    final role = value?.toString().trim() ?? '';

    if (role.isEmpty) return 'Not set';

    return role
        .split(RegExp(r'[_-]'))
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Widget _buildAdminProfileSection() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadAdminProfileData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        if (snapshot.hasError) {
          return _buildDeviceEmptyState(
            icon: Icons.person_off_outlined,
            title: 'Unable to load admin profile',
            subtitle: 'Check the Firestore Security Rules and try again.',
            isError: true,
          );
        }

        final data = snapshot.data ?? <String, dynamic>{};
        final photoUrl = (data['photoURL'] ?? '').toString().trim();
        final displayName = (data['displayName'] ?? 'MusicVerse Administrator')
            .toString();
        final role = _adminRoleLabel(data['role']);
        final isActive = _asBool(data['isactive']);
        final emailVerified = _asBool(data['emailVerified']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 520;

                final avatar = CircleAvatar(
                  radius: 42,
                  backgroundColor: AppColors.primary,
                  backgroundImage: photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl.isEmpty
                      ? const Icon(
                          Icons.person,
                          size: 44,
                          color: AppColors.textWhite,
                        )
                      : null,
                );

                final identity = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Role: $role',
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: (isActive ? AppColors.success : AppColors.error)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isActive ? 'ACTIVE ACCOUNT' : 'INACTIVE ACCOUNT',
                        style: TextStyle(
                          color: isActive ? AppColors.success : AppColors.error,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [avatar, const SizedBox(height: 14), identity],
                  );
                }

                return Row(
                  children: [
                    avatar,
                    const SizedBox(width: 20),
                    Expanded(child: identity),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _buildReadOnlyField(
              'Admin ID',
              data['adminId']?.toString() ?? 'Not available',
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'First Name',
              (data['firstname']?.toString().trim().isNotEmpty ?? false)
                  ? data['firstname'].toString()
                  : 'Not set',
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Last Name',
              (data['lastname']?.toString().trim().isNotEmpty ?? false)
                  ? data['lastname'].toString()
                  : 'Not set',
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Full Name',
              (data['fullname']?.toString().trim().isNotEmpty ?? false)
                  ? data['fullname'].toString()
                  : displayName,
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Email Address',
              (data['email']?.toString().trim().isNotEmpty ?? false)
                  ? data['email'].toString()
                  : 'Not set',
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Phone Number',
              (data['phone']?.toString().trim().isNotEmpty ?? false)
                  ? data['phone'].toString()
                  : 'Not set',
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField('Role', role),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Account Status',
              isActive ? 'Active' : 'Inactive',
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Email Verification',
              emailVerified ? 'Verified' : 'Not Verified',
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Firebase UID',
              data['uid']?.toString() ?? 'N/A',
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Admin Document ID',
              data['adminDocumentId']?.toString() ?? 'N/A',
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Account Created',
              _formatAdminDate(data['createdAt']),
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Last Updated',
              _formatAdminDate(data['updatedAt']),
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Last Sign In',
              _formatAdminDate(data['lastSignIn']),
            ),
            const SizedBox(height: 16),
            _buildReadOnlyField(
              'Profile Photo URL',
              photoUrl.isNotEmpty ? photoUrl : 'Not set',
            ),
          ],
        );
      },
    );
  }

  Widget _buildAppearanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Theme Mode',
          style: TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _themeMode,
          dropdownColor: AppColors.cards,
          style: const TextStyle(color: AppColors.textWhite),
          decoration: _inputDecoration(),
          items: ['Dark', 'Light', 'System']
              .map(
                (val) => DropdownMenuItem<String>(value: val, child: Text(val)),
              )
              .toList(),
          onChanged: (val) => setState(() => _themeMode = val ?? 'Dark'),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text(
            'Compact Dashboard View',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Reduce spacing and padding across tables and widgets.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _compactMode,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _compactMode = val),
        ),
      ],
    );
  }

  Widget _buildNotificationsSection() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            'Payment Reminders',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Receive alerts when fee payments are overdue or completed.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _notifPayments,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _notifPayments = val),
        ),
        SwitchListTile(
          title: const Text(
            'New Student Registrations',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Get notified when a new student enrolls in MusicVerse Academy.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _notifNewStudents,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _notifNewStudents = val),
        ),
        SwitchListTile(
          title: const Text(
            'Attendance Alerts',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Daily summaries of student attendance logs.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _notifAttendance,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _notifAttendance = val),
        ),
        SwitchListTile(
          title: const Text(
            'System & Security Notifications',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Alerts regarding Firebase status and security events.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _notifSystem,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _notifSystem = val),
        ),
      ],
    );
  }

  Widget _buildSecuritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password Management',
          style: TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'To update your password, a secure reset link will be sent to your registered email via Firebase Authentication.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textWhite,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () async {
            final email = FirebaseAuth.instance.currentUser?.email;
            if (email != null) {
              await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Password reset email sent!'),
                  backgroundColor: AppColors.success,
                ),
              );
            }
          },
          icon: const Icon(Icons.lock_reset),
          label: const Text('Send Password Reset Email'),
        ),
        const Divider(color: AppColors.divider, height: 40),

        // Current device.
        Row(
          children: [
            const Expanded(
              child: Text(
                'Current Device',
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.success.withOpacity(0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: AppColors.success),
                  SizedBox(width: 6),
                  Text(
                    'Active now',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'This is the device currently signed in to the admin application.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 14),
        _buildActiveDevices(showCurrentOnly: true),

        const SizedBox(height: 28),

        // Other active devices.
        Row(
          children: [
            const Expanded(
              child: Text(
                'Active Devices',
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _logoutAllOtherDevices,
              icon: const Icon(Icons.logout, size: 17),
              label: const Text('Log Out Others'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Other devices currently signed in to this admin account.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 14),
        _buildActiveDevices(showCurrentOnly: false),

        const Divider(color: AppColors.divider, height: 40),
        const Text(
          'Session Control',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.textWhite,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout from Current Device'),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveDevices({required bool showCurrentOnly}) {
    final user = FirebaseAuth.instance.currentUser;
    final adminDocumentId = _adminDocumentId;

    if (user == null || adminDocumentId == null) {
      return _buildDeviceEmptyState(
        icon: Icons.person_off_outlined,
        title: 'Preparing admin session...',
        subtitle: 'Your admin device session is being registered.',
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('admin')
          .doc(adminDocumentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildDeviceEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Device sessions unavailable',
            subtitle: 'Check Firestore access to the existing admin document.',
            isError: true,
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final data = snapshot.data?.data();

        if (data == null) {
          return _buildDeviceEmptyState(
            icon: Icons.person_off_outlined,
            title: 'Admin account unavailable',
            subtitle: 'The existing admin document could not be loaded.',
            isError: true,
          );
        }

        final rawSessions = data['activeSessions'];
        final sessions = rawSessions is List
            ? rawSessions
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .where(_isSessionFresh)
                  .toList()
            : <Map<String, dynamic>>[];

        sessions.sort((a, b) {
          final aTime = a['lastActiveAt'];
          final bTime = b['lastActiveAt'];

          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }

          if (aTime is Timestamp) return -1;
          if (bTime is Timestamp) return 1;

          return 0;
        });

        final selectedSessions = sessions.where((session) {
          final id = session['sessionId']?.toString();

          return showCurrentOnly
              ? id == _currentSessionId
              : id != _currentSessionId;
        }).toList();

        if (selectedSessions.isEmpty) {
          return _buildDeviceEmptyState(
            icon: showCurrentOnly
                ? Icons.phone_android_outlined
                : Icons.devices_other_outlined,
            title: showCurrentOnly
                ? 'No current active session'
                : 'No other active devices',
            subtitle: showCurrentOnly
                ? 'The current admin session is not present in Firestore yet.'
                : 'No other devices are currently signed in.',
          );
        }

        return Column(
          children: selectedSessions.map((data) {
            final sessionId = data['sessionId']?.toString() ?? '';

            final deviceName =
                (data['deviceName'] as String?)?.trim().isNotEmpty == true
                ? data['deviceName'] as String
                : 'Unknown Device';

            final platform =
                (data['platform'] as String?)?.trim().isNotEmpty == true
                ? data['platform'] as String
                : 'Unknown';

            final ipAddress =
                (data['ipAddress'] as String?)?.trim().isNotEmpty == true
                ? data['ipAddress'] as String
                : 'Unavailable';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildDeviceCard(
                sessionId: sessionId,
                deviceName: deviceName,
                platform: platform,
                ipAddress: ipAddress,
                lastActiveText: _formatLastActive(data['lastActiveAt']),
                isCurrent: sessionId == _currentSessionId,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDeviceEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    bool isError = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isError
              ? AppColors.error.withOpacity(0.35)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (isError ? AppColors.error : AppColors.primary)
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isError ? AppColors.error : AppColors.secondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard({
    required String sessionId,
    required String deviceName,
    required String platform,
    required String ipAddress,
    required String lastActiveText,
    required bool isCurrent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? AppColors.primary.withOpacity(0.65)
              : AppColors.divider,
          width: isCurrent ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isCurrent
                ? AppColors.primary.withOpacity(0.08)
                : Colors.transparent,
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 560;

          final deviceIcon = Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.24),
                  AppColors.secondary.withOpacity(0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _getDeviceIcon(platform),
              color: AppColors.secondary,
              size: 25,
            ),
          );

          final titleRow = Row(
            children: [
              Flexible(
                child: Text(
                  deviceName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'CURRENT',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          );

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleRow,
              const SizedBox(height: 7),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _deviceMeta(Icons.devices_outlined, platform),
                  _deviceMeta(Icons.language_outlined, ipAddress),
                  _deviceMeta(Icons.access_time_outlined, lastActiveText),
                ],
              ),
            ],
          );

          final logoutButton = OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: isCurrent
                  ? AppColors.secondaryText
                  : AppColors.error,
              side: BorderSide(
                color: isCurrent ? AppColors.divider : AppColors.error,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: isCurrent
                ? null
                : () => _logoutDevice(sessionId, deviceName),
            icon: const Icon(Icons.logout, size: 17),
            label: Text(isCurrent ? 'This Device' : 'Log Out'),
          );

          final information = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              deviceIcon,
              const SizedBox(width: 14),
              Expanded(child: details),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                information,
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: logoutButton),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: information),
              const SizedBox(width: 16),
              logoutButton,
            ],
          );
        },
      ),
    );
  }

  Widget _deviceMeta(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.secondaryText),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _logoutDevice(String sessionId, String deviceName) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cards,
        title: const Text(
          'Log Out Device?',
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: Text(
          'Log out $deviceName from the admin application?',
          style: const TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: AppColors.textWhite),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    try {
      // Remove the target device session from the existing admin document.
      // The target device's global admin-document listener signs it out.
      await AdminSessionManager.instance.logoutSpecificSession(sessionId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$deviceName was logged out.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to log out that device. Check your connection and permissions.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _logoutAllOtherDevices() async {
    if (_adminDocumentId == null || _currentSessionId == null) return;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cards,
        title: const Text(
          'Log Out Other Devices?',
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: const Text(
          'All other active admin devices will be signed out. This device will remain signed in.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Log Out Others',
              style: TextStyle(color: AppColors.textWhite),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    try {
      await AdminSessionManager.instance.logoutOtherSessions();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All other devices were logged out.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to log out other devices. Check your connection and permissions.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Default Currency',
          style: TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedCurrency,
          dropdownColor: AppColors.cards,
          style: const TextStyle(color: AppColors.textWhite),
          decoration: _inputDecoration(),
          items: ['USD (\$Mer)', 'EUR (€)', 'INR (₹)', 'GBP (£)']
              .map((val) => DropdownMenuItem(value: val, child: Text(val)))
              .toList(),
          onChanged: (val) =>
              setState(() => _selectedCurrency = val ?? 'USD (\$Mer)'),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;

            final dateFormatField = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Date Format',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedDateFormat,
                  dropdownColor: AppColors.cards,
                  style: const TextStyle(color: AppColors.textWhite),
                  decoration: _inputDecoration(),
                  items: ['MM/DD/YYYY', 'DD/MM/YYYY', 'YYYY-MM-DD']
                      .map(
                        (val) => DropdownMenuItem(value: val, child: Text(val)),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedDateFormat = val ?? 'MM/DD/YYYY'),
                ),
              ],
            );

            final timeFormatField = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Time Format',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedTimeFormat,
                  dropdownColor: AppColors.cards,
                  style: const TextStyle(color: AppColors.textWhite),
                  decoration: _inputDecoration(),
                  items: ['12-Hour', '24-Hour']
                      .map(
                        (val) => DropdownMenuItem(value: val, child: Text(val)),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setState(() => _selectedTimeFormat = val ?? '12-Hour'),
                ),
              ],
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dateFormatField,
                  const SizedBox(height: 16),
                  timeFormatField,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: dateFormatField),
                const SizedBox(width: 16),
                Expanded(child: timeFormatField),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text(
            'Confirmation Before Deleting Records',
            style: TextStyle(color: AppColors.textWhite),
          ),
          subtitle: const Text(
            'Show a warning prompt before removing students, staff, or payments.',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          value: _confirmBeforeDelete,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _confirmBeforeDelete = val),
        ),
      ],
    );
  }

  Widget _buildFirebaseStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusRow('Firebase Connection', 'Connected', AppColors.success),
        const SizedBox(height: 12),
        _statusRow(
          'Authentication Service',
          'Active (Firebase Auth)',
          AppColors.success,
        ),
        const SizedBox(height: 12),
        _statusRow(
          'Database Engine',
          'Active (Cloud Firestore)',
          AppColors.success,
        ),
        const SizedBox(height: 12),
        _statusRow('Storage Service', 'Operational', AppColors.success),
        const SizedBox(height: 24),
        const Text(
          'Note: All services are running optimally. API credentials are securely managed and hidden.',
          style: TextStyle(color: AppColors.secondaryText, fontSize: 13),
        ),
      ],
    );
  }

  Widget _statusRow(String title, String status, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 500;

          final statusContent = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  status,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                statusContent,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(child: statusContent),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: const TextStyle(color: AppColors.textWhite),
          decoration: _inputDecoration(),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }
}
