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
        _idErrorMessage =
            text.isNotEmpty ? 'ID must be exactly 14 digits' : null;
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

      // Check if Eye specialty is included in selected specialties
      final t1Lower = _selectedTakhasos1?.toLowerCase() ?? '';
      final t2Lower = _selectedTakhasos2?.toLowerCase() ?? '';
      final bool hasEye = t1Lower.contains('eye') || t2Lower.contains('eye');

      // Calculate initial field states based on specialty selections
      final bool? initialAutoref = hasEye ? false : null;
      final bool? initialEyeglasses = hasEye ? false : null;

      final bool? t1Status = _selectedTakhasos1 != null ? false : null;
      final bool? t2Status = _selectedTakhasos2 != null ? false : null;

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
            'takhasos1status': t1Status,
            'takhasos2status': t2Status,
            'autoref': initialAutoref,
            'eyeglasses': initialEyeglasses,
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
        builder: (context) => AllRegistrationsPage(
          convoyId: widget.userData['convoyid'],
          takhasosOptions: _takhasosOptions,
        ),
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
  final List<String> takhasosOptions;

  const AllRegistrationsPage({
    super.key,
    required this.convoyId,
    this.takhasosOptions = const [],
  });

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
      var query = _supabase.from('registrations').select('*');

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

  int? _calculateAge(String? dobString) {
    if (dobString == null) return null;
    try {
      final dob = DateTime.parse(dobString);
      final now = DateTime.now();
      int age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }

  void _showPatientDetailDialog(Map<String, dynamic> patient) {
    final age = _calculateAge(patient['dob']?.toString());
    final queueFor = patient['queuefor']?.toString().toLowerCase() ?? '';

    final bool isAutorefDone = patient['autoref'] == true;
    final bool isTakhasos1Done = patient['takhasos1status'] == true;
    final bool isTakhasos2Done = patient['takhasos2status'] == true;

    final String takhasos1 = patient['takhasos1']?.toString() ?? 'Specialty 1';
    final String? takhasos2 = patient['takhasos2']?.toString();

    bool isQueueActive(String specialty) {
      final key = specialty.toLowerCase().trim();
      return queueFor.contains(key);
    }

    String getQueueSubtitle(String specialty, bool isDone) {
      if (isDone) return 'Examination Completed';
      final key = specialty.toLowerCase().trim();
      if (queueFor.contains('${key}inside')) {
        return 'Currently Inside Examination Room';
      } else if (queueFor.contains(key)) {
        return 'Waiting in Queue';
      }
      return 'Pending';
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.all(16),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Patient Movement & Profile',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.purple),
                tooltip: 'Edit Patient',
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _showEditPatientDialog(patient);
                },
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Pharmacy-Style Header Container
                Card(
                  elevation: 2,
                  color: Colors.purple.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.purple.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                patient['fullname']?.toString() ??
                                    'Unknown Name',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade900,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'ID: #${patient['id']}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Age: ${age != null ? "$age yrs" : "N/A"}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Gender: ${patient['gender']?.toString() ?? "N/A"}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.indigo,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'National ID: ${patient['id_number']?.toString() ?? "N/A"}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Phone: ${patient['phone']?.toString() ?? "N/A"}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Timeline Movement Section
                const Text(
                  'Movement Timeline',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Step 1: Registration
                _buildTimelineStep(
                  title: 'Registration',
                  subtitle: 'Patient registered in system',
                  isDone: true,
                ),

                // Step 2: Autoref / Waiting Area
                _buildTimelineStep(
                  title: 'Autoref Station',
                  subtitle: isAutorefDone
                      ? 'Completed'
                      : (queueFor.contains('autoref')
                            ? 'Currently in Queue'
                            : 'Pending'),
                  isDone: isAutorefDone,
                  isActive: queueFor.contains('autoref'),
                ),

                // Step 3: Primary Specialty (Takhasos 1)
                _buildTimelineStep(
                  title: '$takhasos1 Doctor',
                  subtitle: getQueueSubtitle(takhasos1, isTakhasos1Done),
                  isDone: isTakhasos1Done,
                  isActive: isQueueActive(takhasos1),
                ),

                // Step 4: Secondary Specialty (Takhasos 2) - if assigned
                if (takhasos2 != null && takhasos2.trim().isNotEmpty)
                  _buildTimelineStep(
                    title: '$takhasos2 Doctor',
                    subtitle: getQueueSubtitle(takhasos2, isTakhasos2Done),
                    isDone: isTakhasos2Done,
                    isActive: isQueueActive(takhasos2),
                  ),

                // Step 5: Eyeglasses / Operation Referrals
                if (queueFor.contains('eyeglasses'))
                  _buildTimelineStep(
                    title: 'Eyeglasses Department',
                    subtitle: 'Routed for eyeglasses fitting',
                    isDone: false,
                    isActive: true,
                  ),

                if (queueFor.contains('operation'))
                  _buildTimelineStep(
                    title: 'Operation Department',
                    subtitle: 'Scheduled for surgery/operation',
                    isDone: false,
                    isActive: true,
                  ),

                // Step 6: Pharmacy
                _buildTimelineStep(
                  title: 'Pharmacy',
                  subtitle: queueFor.contains('pharmacy')
                      ? 'Awaiting medicine dispensing'
                      : (queueFor == 'ended'
                            ? 'Medicines Received'
                            : 'Pending'),
                  isDone:
                      queueFor == 'ended' &&
                      (isTakhasos1Done || isTakhasos2Done),
                  isActive: queueFor.contains('pharmacy'),
                  isLast: true,
                ),

                // Clinical Notes Display
                if (patient['eyedoctornotes'] != null &&
                    patient['eyedoctornotes'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Doctor Notes:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          patient['eyedoctornotes'].toString(),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                _showEditPatientDialog(patient);
              },
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Edit Patient Details'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimelineStep({
    required String title,
    required String subtitle,
    required bool isDone,
    bool isActive = false,
    bool isLast = false,
  }) {
    final Color stepColor = isDone
        ? Colors.green
        : (isActive ? Colors.orange : Colors.grey.shade400);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isDone
                    ? Colors.green
                    : (isActive
                          ? Colors.orange.shade100
                          : Colors.grey.shade200),
                shape: BoxShape.circle,
                border: Border.all(color: stepColor, width: 2),
              ),
              child: Icon(
                isDone
                    ? Icons.check
                    : (isActive ? Icons.play_arrow : Icons.circle),
                size: 14,
                color: isDone
                    ? Colors.white
                    : (isActive ? Colors.orange.shade900 : Colors.grey),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 32,
                color: isDone ? Colors.green : Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDone
                            ? Colors.green.shade900
                            : (isActive
                                  ? Colors.orange.shade900
                                  : Colors.black87),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDone
                            ? Colors.green.shade50
                            : (isActive
                                  ? Colors.orange.shade50
                                  : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isDone
                            ? 'DONE'
                            : (isActive ? 'NEXT / IN QUEUE' : 'PENDING'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: stepColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showEditPatientDialog(Map<String, dynamic> patient) {
    final nameController =
        TextEditingController(text: patient['fullname']?.toString() ?? '');
    final idController =
        TextEditingController(text: patient['id_number']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: patient['phone']?.toString() ?? '');

    String? selectedT1 = patient['takhasos1'];
    String? selectedT2 = patient['takhasos2'];
    String? gender = patient['gender'];
    DateTime? dob;

    if (patient['dob'] != null && patient['dob'].toString().isNotEmpty) {
      try {
        dob = DateTime.parse(patient['dob'].toString());
      } catch (_) {}
    }

    String? idErrorMsg;
    bool isSaving = false;

    void updateParsedInfo(String idText, StateSetter setDialogState) {
      final text = idText.trim();
      if (text.length == 14) {
        try {
          final centuryDigit = int.parse(text[0]);
          final yearDigits = int.parse(text.substring(1, 3));
          final month = int.parse(text.substring(3, 5));
          final day = int.parse(text.substring(5, 7));
          final genderDigit = int.parse(text[12]);

          int fullYear = (centuryDigit == 2)
              ? 1900 + yearDigits
              : (centuryDigit == 3)
                  ? 2000 + yearDigits
                  : -1;

          if (fullYear != -1) {
            setDialogState(() {
              dob = DateTime(fullYear, month, day);
              gender = (genderDigit % 2 != 0) ? 'Male' : 'Female';
              idErrorMsg = null;
            });
            return;
          }
        } catch (_) {}
      }
      setDialogState(() {
        idErrorMsg = text.isNotEmpty ? 'ID must be 14 digits' : null;
      });
    }

    showDialog(
      context: context,
      builder: (editDialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final t2Options = widget.takhasosOptions
                .where((opt) => opt != selectedT1)
                .toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  const Icon(Icons.edit, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Edit Patient #${patient['id']}'),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: idController,
                      maxLength: 14,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'ID Number (14 digits)',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.badge),
                        errorText: idErrorMsg,
                      ),
                      onChanged: (val) => updateParsedInfo(val, setDialogState),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'DOB: ${dob != null ? "${dob!.day}/${dob!.month}/${dob!.year}" : "---"}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Gender: ${gender ?? "---"}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      maxLength: 11,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: widget.takhasosOptions.contains(selectedT1)
                          ? selectedT1
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Takhasos 1',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.medical_services),
                      ),
                      hint: const Text('Select Takhasos 1'),
                      items: widget.takhasosOptions.map((opt) {
                        return DropdownMenuItem(value: opt, child: Text(opt));
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedT1 = val;
                          if (selectedT2 == val) selectedT2 = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value:
                          t2Options.contains(selectedT2) ? selectedT2 : null,
                      decoration: const InputDecoration(
                        labelText: 'Takhasos 2',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.medical_services_outlined),
                      ),
                      hint: const Text('Select Takhasos 2'),
                      items: t2Options.map((opt) {
                        return DropdownMenuItem(value: opt, child: Text(opt));
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedT2 = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(editDialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final updatedName = nameController.text.trim();
                          final updatedId = idController.text.trim();
                          final updatedPhone = phoneController.text.trim();

                          if (updatedName.isEmpty ||
                              updatedId.length != 14 ||
                              updatedPhone.length != 11 ||
                              selectedT1 == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Please verify all required fields.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);

                          final formattedDob = dob != null
                              ? "${dob!.year.toString().padLeft(4, '0')}-${dob!.month.toString().padLeft(2, '0')}-${dob!.day.toString().padLeft(2, '0')}"
                              : null;

                          try {
                            await _supabase.from('registrations').update({
                              'fullname': updatedName,
                              'id_number': updatedId,
                              'phone': updatedPhone,
                              'takhasos1': selectedT1,
                              'takhasos2': selectedT2,
                              'dob': formattedDob,
                              'gender': gender,
                            }).eq('id', patient['id']);

                            if (mounted) {
                              Navigator.pop(editDialogContext);
                              _fetchRegistrations();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Patient details updated successfully'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Failed to update patient details'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
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
                              onTap: () => _showPatientDetailDialog(patient),
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
                              subtitle: Text(
                                'Phone: ${patient['phone'] ?? "N/A"} | T1: ${patient['takhasos1'] ?? "N/A"}',
                              ),
                              trailing: const Icon(
                                Icons.visibility,
                                color: Colors.purple,
                                size: 20,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
    );
  }
}