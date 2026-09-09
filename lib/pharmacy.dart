import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PharmacyPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const PharmacyPage({super.key, required this.userData});

  @override
  State<PharmacyPage> createState() => _PharmacyPageState();
}

class _PharmacyPageState extends State<PharmacyPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final _searchIdController = TextEditingController();

  String? _convoyName;
  bool _isInitLoading = true;
  bool _isSearching = false;
  bool _isSaving = false;

  // Patient details state
  Map<String, dynamic>? _patientDetails;
  int? _patientAge;

  // Prescribed medicines list with selection state
  List<Map<String, dynamic>> _prescribedMedicines = [];
  Set<dynamic> _selectedMedicineIds = {};

  @override
  void initState() {
    super.initState();
    _fetchConvoyName();
  }

  Future<void> _fetchConvoyName() async {
    final convoyId = widget.userData['convoyid'];

    if (convoyId == null) {
      setState(() => _isInitLoading = false);
      return;
    }

    try {
      final response = await _supabase
          .from('convoys')
          .select('name')
          .eq('id', convoyId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _convoyName = response != null ? response['name'] : 'Unknown Convoy';
          _isInitLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isInitLoading = false);
      }
    }
  }

  Future<void> _searchPatient() async {
    final enteredIdText = _searchIdController.text.trim();

    if (enteredIdText.isEmpty) {
      _showSnackBar('Please enter a Patient ID');
      return;
    }

    final patientId = int.tryParse(enteredIdText) ?? enteredIdText;
    final userConvoyId = widget.userData['convoyid'];

    setState(() {
      _isSearching = true;
      _patientDetails = null;
      _patientAge = null;
      _prescribedMedicines = [];
      _selectedMedicineIds.clear();
    });

    try {
      // 1. Fetch patient details including 'pharmacy' column
      var patientQuery = _supabase
          .from('registrations')
          .select(
            'id, fullname, id_number, phone, takhasos1, takhasos2, takhasos1status, takhasos2status, dob, pharmacy, convoyid',
          )
          .eq('id', patientId);

      if (userConvoyId != null) {
        patientQuery = patientQuery.eq('convoyid', userConvoyId);
      }

      final patientResponse = await patientQuery.maybeSingle();

      if (patientResponse == null) {
        if (mounted) {
          _showSnackBar(
            'No patient found with ID: $enteredIdText for this convoy',
            isError: true,
          );
        }
        return;
      }

      // 2. Calculate Age from DOB
      int? age;
      if (patientResponse['dob'] != null) {
        try {
          final dob = DateTime.parse(patientResponse['dob'].toString());
          final now = DateTime.now();
          age = now.year - dob.year;
          if (now.month < dob.month ||
              (now.month == dob.month && now.day < dob.day)) {
            age--;
          }
        } catch (_) {}
      }

      // 3. Fetch medicines from 'patientmedicine' joined with 'medicine'
      final medicinesResponse = await _supabase
          .from('patientmedicine')
          .select('medicineid, given, medicine:medicineid(name)')
          .eq('patientid', patientId);

      if (mounted) {
        final List<Map<String, dynamic>> medList =
            List<Map<String, dynamic>>.from(medicinesResponse);

        final Set<dynamic> preSelected = {};
        for (var item in medList) {
          if (item['given'] == true) {
            preSelected.add(item['medicineid']);
          }
        }

        setState(() {
          _patientDetails = patientResponse;
          _patientAge = age;
          _prescribedMedicines = medList;
          _selectedMedicineIds = preSelected;
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted)
        _showSnackBar('An error occurred while fetching patient details');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _saveDispensedMedicines() async {
    if (_patientDetails == null) return;

    final currentUserId = widget.userData['id'];
    final patientId = _patientDetails!['id'];

    setState(() => _isSaving = true);

    try {
      // 1. Update ALL medicines in patientmedicine
      for (var item in _prescribedMedicines) {
        final medicineId = item['medicineid'];
        final isSelected = _selectedMedicineIds.contains(medicineId);

        await _supabase
            .from('patientmedicine')
            .update({'given': isSelected, 'giverid': currentUserId})
            .match({'patientid': patientId, 'medicineid': medicineId});
      }

      // 2. Mark pharmacy = true in registrations table
      await _supabase
          .from('registrations')
          .update({'pharmacy': true})
          .eq('id', patientId);

      if (mounted) {
        _showSnackBar(
          'Prescription status saved successfully!',
          isError: false,
        );

        // Reset search controller and clear current patient display
        _searchIdController.clear();
        setState(() {
          _patientDetails = null;
          _patientAge = null;
          _prescribedMedicines = [];
          _selectedMedicineIds.clear();
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to update medicine records');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Widget _buildStatusChip(bool? isDone) {
    final done = isDone == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: done ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: done ? Colors.green.shade400 : Colors.orange.shade400,
        ),
      ),
      child: Text(
        done ? 'Done' : 'Pending',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: done ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      ),
    );
  }

  Widget _buildPharmacyStatusBadge(bool? isPharmacyGiven) {
    final given = isPharmacyGiven == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: given ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: given ? Colors.green.shade600 : Colors.orange.shade600,
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            given ? Icons.check_circle : Icons.pending,
            color: given ? Colors.green.shade800 : Colors.orange.shade800,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            given ? 'Medicines Dispensed' : 'Pending Pharmacy Dispensing',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: given ? Colors.green.shade900 : Colors.orange.shade900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.userData['name'] ?? 'N/A';
    final userRole = widget.userData['role'] ?? 'Pharmacy';

    final hasTakhasos2 =
        _patientDetails != null &&
        _patientDetails!['takhasos2'] != null &&
        _patientDetails!['takhasos2'].toString().trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pharmacy Module'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isInitLoading
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
                      // User Info Header Card
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
                      const SizedBox(height: 24),

                      // Search Patient Section
                      const Text(
                        'Search Patient Prescription',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchIdController,
                              decoration: const InputDecoration(
                                labelText: 'Enter Patient ID',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.search),
                              ),
                              keyboardType: TextInputType.number,
                              onSubmitted: (_) => _searchPatient(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _isSearching ? null : _searchPatient,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 18,
                              ),
                            ),
                            child: _isSearching
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Search'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Patient Details Card
                      if (_patientDetails != null) ...[
                        Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                              color: Colors.teal,
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header: Patient Name
                                Text(
                                  _patientDetails!['fullname'] ??
                                      'Unknown Name',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal,
                                  ),
                                ),
                                const Divider(height: 20),
                                const SizedBox(height: 4),

                                // Row 1: Age & Takhasos 1
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Age: ${_patientAge != null ? "$_patientAge yrs" : "N/A"}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          '${_patientDetails!['takhasos1'] ?? "N/A"}',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.indigo,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildStatusChip(
                                          _patientDetails!['takhasos1status'],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),

                                // Row 2: Takhasos 2 (Only if not null/empty)
                                if (hasTakhasos2) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${_patientDetails!['takhasos2']}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildStatusChip(
                                        _patientDetails!['takhasos2status'],
                                      ),
                                    ],
                                  ),
                                ],

                                const SizedBox(height: 12),
                                Text(
                                  'National ID: ${_patientDetails!['id_number'] ?? "N/A"}',
                                  style: const TextStyle(fontSize: 15),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Phone: ${_patientDetails!['phone'] ?? "N/A"}',
                                  style: const TextStyle(fontSize: 15),
                                ),
                                const SizedBox(height: 14),

                                // Pharmacy Status Badge
                                _buildPharmacyStatusBadge(
                                  _patientDetails!['pharmacy'],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Prescribed Medicines Section
                        const Text(
                          'Prescribed Medicines',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (_prescribedMedicines.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                'No prescribed medicines found for this patient.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        else ...[
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _prescribedMedicines.length,
                            itemBuilder: (context, index) {
                              final item = _prescribedMedicines[index];
                              final medicineData =
                                  item['medicine'] as Map<String, dynamic>?;
                              final medicineName =
                                  medicineData?['name'] ?? 'Unknown Medicine';
                              final medicineId = item['medicineid'];
                              final isGiven = item['given'] == true;
                              final isSelected = _selectedMedicineIds.contains(
                                medicineId,
                              );

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: isGiven
                                    ? Colors.grey.shade200
                                    : Colors.white,
                                child: CheckboxListTile(
                                  activeColor: isGiven
                                      ? Colors.grey.shade600
                                      : Colors.teal,
                                  title: Text(
                                    medicineName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isGiven
                                          ? Colors.grey.shade700
                                          : Colors.black87,
                                    ),
                                  ),
                                  value: isSelected,
                                  onChanged: (bool? checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedMedicineIds.add(medicineId);
                                      } else {
                                        _selectedMedicineIds.remove(medicineId);
                                      }
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          // Save Dispensed Medicines Button
                          _isSaving
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton(
                                  onPressed: _saveDispensedMedicines,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text(
                                    'Save',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
