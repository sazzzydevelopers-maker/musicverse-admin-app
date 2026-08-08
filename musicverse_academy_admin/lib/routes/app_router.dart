import 'package:go_router/go_router.dart';
import 'package:musicverse_academy_admin/features/auth/screens/forgot_password_screen.dart';
import 'package:musicverse_academy_admin/features/auth/screens/login_screen.dart';
import 'package:musicverse_academy_admin/features/auth/screens/splash_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
  ],
);
