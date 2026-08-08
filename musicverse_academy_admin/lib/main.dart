import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'package:musicverse_academy_admin/core/constants/app_colors.dart';
import 'package:musicverse_academy_admin/features/auth/providers/auth_provider.dart';
import 'package:musicverse_academy_admin/routes/app_router.dart';
import 'package:musicverse_academy_admin/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MusicVerseAdminApp());
}

class MusicVerseAdminApp extends StatelessWidget {
  const MusicVerseAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: MaterialApp.router(
        title: 'MusicVerse Academy Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppColors.background,
          primaryColor: AppColors.primary,
        ),
        routerConfig: appRouter,
      ),
    );
  }
}
