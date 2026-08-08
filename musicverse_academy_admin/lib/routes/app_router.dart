import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:go_router/go_router.dart';
import 'package:musicverse_academy_admin/features/auth/screens/forgot_password_screen.dart';
import 'package:musicverse_academy_admin/features/auth/screens/dashboard_screen.dart';
import 'package:musicverse_academy_admin/features/auth/screens/login_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/dashboard',

  redirect: (context, state) {
    final user = fb.FirebaseAuth.instance.currentUser;
    final loggedIn = user != null;

    final isPublicRoute =
        state.matchedLocation == '/login' ||
        state.matchedLocation == '/forgot-password';

    // User is not logged in.
    // Allow both Login and Forgot Password.
    if (!loggedIn && !isPublicRoute) {
      return '/login';
    }

    // User is already logged in.
    // Don't allow them to return to Login.
    if (loggedIn && state.matchedLocation == '/login') {
      return '/dashboard';
    }

    return null;
  },

  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
  ],
);
