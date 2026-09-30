import 'package:flutter/material.dart';

class QuadrantPlannerApp extends StatelessWidget {
  const QuadrantPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quadrant Planner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const Scaffold(
        body: Center(child: Text('Quadrant Planner v1')),
      ),
    );
  }
}
