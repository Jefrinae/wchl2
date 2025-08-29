import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // ✅ Import Firebase core
import 'firebase_options.dart'; // ✅ Import generated Firebase options
import 'pages/home_page.dart'; // ✅ your map-based screen

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize Firebase with options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(RapidResQApp());
}

class RapidResQApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RapidResQ',
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: Colors.white,
      ),
      debugShowCheckedModeBanner: false,
      home: HomePage(), // ✅ loads map screen directly
    );
  }
}
