import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'HomeScreen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return M3EMaterialApp(
      data: M3EThemeData.light(),
      home: const HomeScreen(),
    );
  }
}
