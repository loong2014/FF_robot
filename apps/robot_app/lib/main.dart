import 'package:flutter/material.dart';

import 'src/home_page.dart';

void main() {
  runApp(const RobotDogApp());
}

class RobotDogApp extends StatelessWidget {
  const RobotDogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Robot OS Lite',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A7C74),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F4EC),
      ),
      home: const HomePage(),
    );
  }
}
