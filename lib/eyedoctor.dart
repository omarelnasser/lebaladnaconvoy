import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EyeDoctorPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const EyeDoctorPage({super.key, required this.userData});

  @override
  State<EyeDoctorPage> createState() => _EyeDoctorPageState();
}

class _EyeDoctorPageState extends State<EyeDoctorPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController _notesController = TextEditingController();

  String? _convoyName;
  bool _isLoadingConvoy = true;
  bool _isSaving = false;

  // Realtime queue state
  StreamSubscription<List<Map<String, dynamic>>>? _queueSubscription;
  List<Map<String, dynamic>> _eyeQueuePatients = [];

  // Available convoy eye medicines
  List<Map<String, dynamic>> _convoyMedicines = [];
  Set<dynamic> _selectedMedicineIds = {};

  // Form options
  bool _eyeglasses = false;
  bool _operation = false;

  @override
  void initState() {
    super.initState();
    _loadConvoyAndMedicines();
  }

  Future<void> _loadConvoyAndMedicines() async {
    final convoyId = widget.userData['convoyid'];

    if (convoyId == null) {
      setState(() => _isLoadingConvoy = false);
      return;
    }

    try {
      // 1. Fetch Convoy details
      final convoyResponse = await _supabase
          .from('convoys')
          .select('name')
          .eq('id', convoyId)
          .maybeSingle();

      if (convoyResponse != null) {
        _convoyName = convoyResponse['name'] ?? 'Unknown Convoy';
      }

      // 2. Fetch medicines for this convoy where type = 'eye'
      final medicinesResponse = await _supabase
          .from('medicine')
          .select('id, name')
          .eq('convoyid', convoyId)
          .eq('type', 'eye')
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _convoyMedicines = List<Map<String, dynamic>>.from(medicinesResponse);
        });
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error loading convoy/medicines data: $e');
    } finally {
      if (mounted) setState(() => _isLoadingConvoy = false);
    }

    // 3. Setup realtime listener for patients in 'eye' queue
    _subscribeToEyeQueueStream();
  }

  void _subscribeToEyeQueueStream() {
    final convoyId = widget.userData['convoyid'];

    _queueSubscription = _supabase
        .from('registrations')
        .stream(primaryKey: ['id'])
        .eq('queuefor', 'eye')
        .order('id', ascending: true)
        .listen(
          (data) {
            if (!mounted) return;

            final filteredData = data.where((row) {
              if (convoyId == null) return true;
              return row['convoyid'] == convoyId;
            }).toList();

            setState(() {
              _eyeQueuePatients = filteredData;
            });
          },
          onError: (error) {
            if (mounted) _showSnackBar('Realtime connection error: $error');
          },
        );
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

  Future<void> _savePrescription(Map<String, dynamic> patient) async {
    final patientId = patient['id'];
    final notesText = _notesController.text.trim();

    setState(() => _isSaving = true);

    try {
      // 1. Insert selected medicines into patientmedicine table
      if (_selectedMedicineIds.isNotEmpty) {
        final List<Map<String, dynamic>> rowsToInsert = _selectedMedicineIds
            .map((medId) {
              return {
                'patientid': patientId,
                'medicineid': medId,
                'given': false,
              };
            })
            .toList();

        await _supabase.from('patientmedicine').insert(rowsToInsert);
      }

      // 2. Build ordered queuefor string or fallback to takhasos2 / ended
      final List<String> queueParts = [];

      if (_eyeglasses) {
        queueParts.add('eyeglasses');
      }

      if (_selectedMedicineIds.isNotEmpty) {
        queueParts.add('pharmacy');
      }

      if (_operation) {
        queueParts.add('operation');
      }

      String nextQueueFor;

      if (queueParts.isNotEmpty) {
        nextQueueFor = queueParts.join(',');
      } else {
        // Fallback check: check if takhasos2 exists
        final rawTakhasos2 = patient['takhasos2']?.toString().trim();
        if (rawTakhasos2 != null && rawTakhasos2.isNotEmpty) {
          nextQueueFor = rawTakhasos2.toLowerCase();
        } else {
          nextQueueFor = 'ended';
        }
      }

      // 3. Determine specialty status updates
      final bool isTakhasos1Eye = patient['takhasos1']
          .toString()
          .toLowerCase()
          .contains('eye');

      Map<String, dynamic> updatePayload = {
        'queuefor': nextQueueFor,
        'eyedoctornotes': notesText,
      };

      if (isTakhasos1Eye) {
        updatePayload['takhasos1status'] = true;
      } else {
        updatePayload['takhasos2status'] = true;
      }

      await _supabase
          .from('registrations')
          .update(updatePayload)
          .eq('id', patientId);

      if (mounted) {
        _showSnackBar(
          'Prescription saved! Patient queue updated to: $nextQueueFor',
          isError: false,
        );

        // Optimistically remove the finished patient locally so UI updates immediately
        setState(() {
          _eyeQueuePatients.removeWhere((p) => p['id'] == patientId);
          _notesController.clear();
          _selectedMedicineIds.clear();
          _eyeglasses = false;
          _operation = false;
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to save prescription');
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

  @override
  void dispose() {
    _notesController.dispose();
    _queueSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.userData['name'] ?? 'N/A';
    final userRole = widget.userData['role'] ?? 'Eye Doctor';

    final currentPatient = _eyeQueuePatients.isNotEmpty
        ? _eyeQueuePatients.first
        : null;
    final waitingQueue = _eyeQueuePatients.length > 1
        ? _eyeQueuePatients.skip(1).toList()
        : [];

    final patientAge = currentPatient != null
        ? _calculateAge(currentPatient['dob'])
        : null;
    final hasTakhasos2 =
        currentPatient != null &&
        currentPatient['takhasos2'] != null &&
        currentPatient['takhasos2'].toString().trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eye Doctor Module'),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: const Row(
              children: [
                Icon(Icons.sensors, color: Colors.white, size: 20),
                SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isLoadingConvoy
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
                      const SizedBox(height: 24),

                      // Current Active Patient Section
                      const Text(
                        'Current Patient',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (currentPatient == null)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Center(
                            child: Text(
                              'No patients currently waiting in the Eye queue.',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        // Patient Details Card
                        Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.teal.shade700,
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        currentPatient['fullname'] ??
                                            'Unknown Name',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal.shade800,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.teal.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        'ID: #${currentPatient['id']}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                const SizedBox(height: 4),

                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Age: ${patientAge != null ? "$patientAge yrs" : "N/A"}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Gender: ${currentPatient['gender'] ?? "N/A"}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    const Text(
                                      'Takhasos 1: ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${currentPatient['takhasos1'] ?? "N/A"}',
                                      style: const TextStyle(
                                        color: Colors.indigo,
                                      ),
                                    ),
                                  ],
                                ),
                                if (hasTakhasos2) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Text(
                                        'Takhasos 2: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '${currentPatient['takhasos2']}',
                                        style: const TextStyle(
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                const SizedBox(height: 10),
                                Text(
                                  'National ID: ${currentPatient['id_number'] ?? "N/A"}',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Phone: ${currentPatient['phone'] ?? "N/A"}',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Eye Doctor Notes Container
                        const Text(
                          'Eye Doctor Notes',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText:
                                'Enter clinical observations, diagnoses, or additional instructions...',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Action Referrals (Eyeglasses & Operation)
                        const Text(
                          'Referral Services',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          elevation: 1,
                          child: Column(
                            children: [
                              CheckboxListTile(
                                activeColor: Colors.teal.shade700,
                                title: const Text(
                                  'Eyeglasses Required',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: const Text(
                                  'Route patient to Eyeglasses department',
                                ),
                                value: _eyeglasses,
                                onChanged: (bool? val) {
                                  setState(() => _eyeglasses = val ?? false);
                                },
                              ),
                              const Divider(height: 1),
                              CheckboxListTile(
                                activeColor: Colors.teal.shade700,
                                title: const Text(
                                  'Operation Required',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: const Text(
                                  'Route patient to Operation department',
                                ),
                                value: _operation,
                                onChanged: (bool? val) {
                                  setState(() => _operation = val ?? false);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Prescribe Eye Medicines Section
                        const Text(
                          'Prescribe Eye Medicines',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (_convoyMedicines.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                'No eye medicines configured for this convoy.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _convoyMedicines.length,
                            itemBuilder: (context, index) {
                              final med = _convoyMedicines[index];
                              final medId = med['id'];
                              final medName = med['name'] ?? 'Unknown Medicine';
                              final isSelected = _selectedMedicineIds.contains(
                                medId,
                              );

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: CheckboxListTile(
                                  activeColor: Colors.teal.shade700,
                                  title: Text(
                                    medName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  value: isSelected,
                                  onChanged: (bool? checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedMedicineIds.add(medId);
                                      } else {
                                        _selectedMedicineIds.remove(medId);
                                      }
                                    });
                                  },
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 20),

                        // Save Button
                        _isSaving
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                onPressed: () =>
                                    _savePrescription(currentPatient),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text(
                                  'Save & Next Patient',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ],

                      const SizedBox(height: 28),

                      // Waiting Queue List Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Waiting Queue',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${waitingQueue.length} Waiting',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (waitingQueue.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'No additional patients waiting in queue.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: waitingQueue.length,
                          itemBuilder: (context, index) {
                            final patient = waitingQueue[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.teal.shade100,
                                  child: Text(
                                    '#${patient['id']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal.shade900,
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
                                subtitle: Text('Patient ID: #${patient['id']}'),
                                trailing: Text(
                                  'Pos #${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
