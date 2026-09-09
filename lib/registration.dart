import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrationPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const RegistrationPage({super.key, required this.userData});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final _fullNameController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _convoyName;
  List<String> _takhasosOptions = [];
  String? _selectedTakhasos1;
  String? _selectedTakhasos2;

  DateTime? _calculatedDob;
  int? _calculatedAge;
  String? _calculatedGender;
  String? _idErrorMessage;

  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchConvoyDetails();
    _idNumberController.addListener(_onIdChanged);
  }

  Future<void> _fetchConvoyDetails() async {
    final convoyId = widget.userData['convoyid'];

    if (convoyId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await _supabase
          .from('convoys')
          .select('name, takhasos')
          .eq('id', convoyId)
          .maybeSingle();

      if (response != null && mounted) {
        final rawTakhasos = response['takhasos'] as String?;

        List<String> parsedOptions = [];
        if (rawTakhasos != null && rawTakhasos.trim().isNotEmpty) {
          parsedOptions = rawTakhasos
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }

        setState(() {
          _convoyName = response['name'] ?? 'Unknown Convoy';
          _takhasosOptions = parsedOptions;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onIdChanged() {
    final text = _idNumberController.text.trim();

    if (text.length == 14) {
      _calculateDobAgeAndGender(text);
    } else {
      setState(() {
        _calculatedDob = null;
        _calculatedAge = null;
        _calculatedGender = null;
        _idErrorMessage = text.isNotEmpty
            ? 'ID must be exactly 14 digits'
            : null;
      });
    }
  }

  void _calculateDobAgeAndGender(String id) {
    try {
      final centuryDigit = int.parse(id[0]);
      final yearDigits = int.parse(id.substring(1, 3));
      final month = int.parse(id.substring(3, 5));
      final day = int.parse(id.substring(5, 7));
      final genderDigit = int.parse(id[12]);

      int fullYear;
      if (centuryDigit == 2) {
        fullYear = 1900 + yearDigits;
      } else if (centuryDigit == 3) {
        fullYear = 2000 + yearDigits;
      } else {
        setState(() {
          _calculatedDob = null;
          _calculatedAge = null;
          _calculatedGender = null;
          _idErrorMessage = 'Invalid ID format (1st digit must be 2 or 3)';
        });
        return;
      }

      final dob = DateTime(fullYear, month, day);
      final now = DateTime.now();

      int age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age--;
      }

      final String gender = (genderDigit % 2 != 0) ? 'Male' : 'Female';

      setState(() {
        _calculatedDob = dob;
        _calculatedAge = age;
        _calculatedGender = gender;
        _idErrorMessage = null;
      });
    } catch (e) {
      setState(() {
        _calculatedDob = null;
        _calculatedAge = null;
        _calculatedGender = null;
        _idErrorMessage = 'Invalid date or sequence in ID';
      });
    }
  }

  Future<void> _submitRegistration() async {
    final fullName = _fullNameController.text.trim();
    final idNumber = _idNumberController.text.trim();
    final phone = _phoneController.text.trim();

    if (fullName.isEmpty) {
      _showSnackBar('Please enter patient full name');
      return;
    }

    if (idNumber.length != 14) {
      _showSnackBar('ID Number must be exactly 14 digits');
      return;
    }

    if (_calculatedDob == null || _calculatedGender == null) {
      _showSnackBar('Invalid ID number — cannot parse details');
      return;
    }

    if (phone.length != 11) {
      _showSnackBar('Phone number must be exactly 11 digits');
      return;
    }

    if (_selectedTakhasos1 == null) {
      _showSnackBar('Please select Takhasos 1');
      return;
    }

    if (_selectedTakhasos1 == _selectedTakhasos2) {
      _showSnackBar('Takhasos 1 and Takhasos 2 cannot be the same');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final formattedDob =
          "${_calculatedDob!.year.toString().padLeft(4, '0')}-${_calculatedDob!.month.toString().padLeft(2, '0')}-${_calculatedDob!.day.toString().padLeft(2, '0')}";

      final response = await _supabase
          .from('registrations')
          .insert({
            'fullname': fullName,
            'id_number': idNumber,
            'phone': phone,
            'takhasos1': _selectedTakhasos1,
            'takhasos2': _selectedTakhasos2,
            'dob': formattedDob,
            'gender': _calculatedGender,
            'convoyid': widget.userData['convoyid'],
            'registerid': widget.userData['id'],
            'pharmacy': false,
            'takhasos1status': false,
            'takhasos2status': false,
            'autoref': false,
            'queuefor': 'outside',
          })
          .select('id')
          .single();

      final newPatientId = response['id'];

      if (mounted) {
        _showSuccessDialog(newPatientId, fullName);

        _fullNameController.clear();
        _idNumberController.clear();
        _phoneController.clear();
        setState(() {
          _selectedTakhasos1 = null;
          _selectedTakhasos2 = null;
          _calculatedDob = null;
          _calculatedAge = null;
          _calculatedGender = null;
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to submit registration');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSuccessDialog(dynamic patientId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('Registration Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient: $name'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Assigned Patient ID:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '#$patientId',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _navigateToAllRegistrations() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AllRegistrationsPage(convoyId: widget.userData['convoyid']),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    _idNumberController.removeListener(_onIdChanged);
    _fullNameController.dispose();
    _idNumberController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.userData['name'] ?? 'N/A';
    final userRole = widget.userData['role'] ?? 'Registration';

    final takhasos2Options = _takhasosOptions
        .where((option) => option != _selectedTakhasos1)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registration Module'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'All Registrations',
            onPressed: _navigateToAllRegistrations,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 24.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // User Info Card
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome, $userName',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Role: $userRole | Convoy: ${_convoyName ?? "N/A"}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // "All Registrations" Action Button
                      OutlinedButton.icon(
                        onPressed: _navigateToAllRegistrations,
                        icon: const Icon(
                          Icons.people_alt,
                          color: Colors.indigo,
                        ),
                        label: const Text(
                          'View All Registrations',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Colors.indigo),
                        ),
                      ),
                      const SizedBox(height: 24),

                      const Text(
                        'Register New Patient',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Patient Full Name
                      TextField(
                        controller: _fullNameController,
                        decoration: const InputDecoration(
                          labelText: 'Patient Full Name',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ID Number
                      TextField(
                        controller: _idNumberController,
                        maxLength: 14,
                        decoration: InputDecoration(
                          labelText: 'ID Number (14 digits)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.badge),
                          errorText: _idErrorMessage,
                          counterText: '${_idNumberController.text.length}/14',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 8),

                      // Calculated Info Box (DOB, Age, Gender)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Calculated Patient Info:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'DOB: ${_calculatedDob != null ? "${_calculatedDob!.day}/${_calculatedDob!.month}/${_calculatedDob!.year}" : "---"}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Age: ${_calculatedAge != null ? "$_calculatedAge yrs" : "---"}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.indigo,
                                  ),
                                ),
                                Text(
                                  'Gender: ${_calculatedGender ?? "---"}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.teal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Phone Number
                      TextField(
                        controller: _phoneController,
                        maxLength: 11,
                        decoration: InputDecoration(
                          labelText: 'Phone Number (11 digits)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.phone),
                          counterText: '${_phoneController.text.length}/11',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),

                      // Takhasos 1 Dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedTakhasos1,
                        decoration: const InputDecoration(
                          labelText: 'Takhasos 1 (Required)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.medical_services),
                        ),
                        hint: const Text('Select Takhasos 1'),
                        items: _takhasosOptions.map((String option) {
                          return DropdownMenuItem<String>(
                            value: option,
                            child: Text(option),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedTakhasos1 = newValue;
                            if (_selectedTakhasos2 == newValue) {
                              _selectedTakhasos2 = null;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Takhasos 2 Dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedTakhasos2,
                        decoration: const InputDecoration(
                          labelText: 'Takhasos 2 (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.medical_services_outlined),
                        ),
                        hint: const Text('Select Takhasos 2'),
                        items: takhasos2Options.map((String option) {
                          return DropdownMenuItem<String>(
                            value: option,
                            child: Text(option),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedTakhasos2 = newValue;
                          });
                        },
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      _isSubmitting
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton(
                              onPressed: _submitRegistration,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: const Text(
                                'Save Registration',
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

// ---------------------------------------------------------------------------
// All Registrations ListView Screen
// ---------------------------------------------------------------------------
class AllRegistrationsPage extends StatefulWidget {
  final dynamic convoyId;

  const AllRegistrationsPage({super.key, required this.convoyId});

  @override
  State<AllRegistrationsPage> createState() => _AllRegistrationsPageState();
}

class _AllRegistrationsPageState extends State<AllRegistrationsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _patients = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRegistrations();
  }

  Future<void> _fetchRegistrations() async {
    try {
      var query = _supabase.from('registrations').select('id, fullname');

      if (widget.convoyId != null) {
        query = query.eq('convoyid', widget.convoyId);
      }

      final response = await query.order('id', ascending: false);

      if (mounted) {
        setState(() {
          _patients = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Registered Patients'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _patients.isEmpty
                    ? const Center(
                        child: Text(
                          'No registered patients found.',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _patients.length,
                        itemBuilder: (context, index) {
                          final patient = _patients[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.indigo.shade100,
                                child: Text(
                                  '#${patient['id']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              title: Text(
                                patient['fullname'] ?? 'N/A',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Text('Patient ID: ${patient['id']}'),
                            ),
                          );
                        },
                      ),
              ),
            ),
    );
  }
}
