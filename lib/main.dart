import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'loginpage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://vpzpzakfnsygkpupmvid.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZwenB6YWtmbnN5Z2twdXBtdmlkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkyMDQwNzgsImV4cCI6MjA5NDc4MDA3OH0.1ojYvGy8e8fuNsBiTAfutW-mNaZTUJG5zaChqZAqc8U',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Supabase App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}
