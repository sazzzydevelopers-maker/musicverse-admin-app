import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:go_router/go_router.dart';

import 'package:musicverse_academy_admin/features/auth/screens/forgot_password_screen.dart';
import 'package:musicverse_academy_admin/features/auth/screens/dashboard_screen.dart';
import 'package:musicverse_academy_admin/features/auth/screens/login_screen.dart';
import 'package:musicverse_academy_admin/features/auth/screens/login_animation_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/login',

  redirect: (context, state) {
    final user = fb.FirebaseAuth.instance.currentUser;
    final loggedIn = user != null;

    final location = state.matchedLocation;

    // Public pages
    final isPublicRoute =
        location == '/login' ||
        location == '/forgot-password' ||
        location == '/login-animation';

    // User is not logged in.
    // Only allow Login, Forgot Password and Login Animation.
    if (!loggedIn && !isPublicRoute) {
      return '/login';
    }

    // Logged-in user trying to go back to Login.
    if (loggedIn && location == '/login') {
      return '/dashboard';
    }

    // IMPORTANT:
    // Do not redirect /login-animation.
    // The animation screen will navigate to dashboard
    // after the animation finishes.
    return null;
  },

  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),

    GoRoute(
      path: '/login-animation',
      builder: (context, state) => const LoginAnimationScreen(),
    ),

    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
  ],
);
