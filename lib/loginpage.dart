import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pharmacy.dart';
import 'registration.dart';
import 'eyedoctor.dart';
import 'autoref.dart';
import 'waitingarea.dart';
import 'batnadoctor.dart';
import 'doctorassistant.dart';
import 'bus.dart';
import 'admin/admin.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _idController = TextEditingController();
  bool _isLoading = false;

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> _loginAndNavigate() async {
    final enteredId = _idController.text.trim();

    if (enteredId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter an ID')));
      return;
    }

    // Direct route check for Admin passkey
    if (enteredId == 'omar2005') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AdminPage()),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Lookup user in 'roles' table by ID
      final response = await _supabase
          .from('roles')
          .select('id, name, role, convoyid')
          .eq('id', enteredId)
          .maybeSingle();

      if (response == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No record found for this ID'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final String role =
          response['role']?.toString().toLowerCase().trim() ?? '';

      if (!mounted) return;

      // Navigate based on assigned role
      if (role == 'pharmacy') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PharmacyPage(userData: response),
          ),
        );
      } else if (role == 'registration') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RegistrationPage(userData: response),
          ),
        );
      } else if (role == 'autoref') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AutorefPage(userData: response),
          ),
        );
      } else if (role == 'eyedoctor') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => EyeDoctorPage(userData: response),
          ),
        );
      } else if (role == 'waitingarea') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => WaitingAreaPage(userData: response),
          ),
        );
      } else if (role == 'batnadoctor') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => BatnaDoctorPage(userData: response),
          ),
        );
      } else if (role == 'operationbus') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OperationBusPage(userData: response),
          ),
        );
      } else if (role == 'eyedoctorassistant' ||
          role == 'autorefdoctorassistant' ||
          role == 'batnadoctorassistant' ||
          role == 'glassesassistant') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DoctorAssistantPage(userData: response),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unrecognized role: "${response['role']}"'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message), backgroundColor: Colors.red),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unexpected error occurred'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter your ID',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _idController,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    hintText: 'Enter ID',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.text,
                  onSubmitted: (_) => _loginAndNavigate(),
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _loginAndNavigate,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Login',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
