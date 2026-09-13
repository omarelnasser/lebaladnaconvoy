import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DoctorAssistantPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const DoctorAssistantPage({super.key, required this.userData});

  @override
  State<DoctorAssistantPage> createState() => _DoctorAssistantPageState();
}

class _DoctorAssistantPageState extends State<DoctorAssistantPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _convoyName;
  String _targetQueue = 'eye';
  String _departmentTitle = 'Assistant Panel';
  int _doctorSlotsCount = 1;

  bool _isLoadingConvoy = true;

  // Realtime queue state
  StreamSubscription<List<Map<String, dynamic>>>? _queueSubscription;

  // Full fetched queue list
  List<Map<String, dynamic>> _allDepartmentPatients = [];

  // Convoy medicines list for popups
  List<Map<String, dynamic>> _convoyMedicines = [];

  @override
  void initState() {
    super.initState();
    _resolveRoleAndQueue();
    _loadConvoyAndSubscribe();
  }

  /// Maps role string to queuefor target key and human-readable header title
  void _resolveRoleAndQueue() {
    final rawRole =
        widget.userData['role']?.toString().toLowerCase().trim() ?? '';

    if (rawRole.contains('batna')) {
      _targetQueue = 'batna';
      _departmentTitle = 'Batna Doctor Assistant';
    } else if (rawRole.contains('autoref')) {
      _targetQueue = 'autoref';
      _departmentTitle = 'Autoref Doctor Assistant';
    } else if (rawRole.contains('glasses') || rawRole.contains('eyeglasses')) {
      _targetQueue = 'eyeglasses';
      _departmentTitle = 'Eyeglasses Assistant';
    } else {
      // Fallback for eyedoctorassistant / general eye
      _targetQueue = 'eye';
      _departmentTitle = 'Eye Doctor Assistant';
    }
  }

  Future<void> _loadConvoyAndSubscribe() async {
    final convoyId = widget.userData['convoyid'];

    if (convoyId == null) {
      setState(() => _isLoadingConvoy = false);
      return;
    }

    try {
      // 1. Fetch convoy details
      final convoyResponse = await _supabase
          .from('convoys')
          .select('name, takhasos, takhasosnumber')
          .eq('id', convoyId)
          .maybeSingle();

      if (convoyResponse != null) {
        _convoyName = convoyResponse['name'] ?? 'Unknown Convoy';

        final rawTakhasosNum =
            convoyResponse['takhasosnumber']?.toString() ?? '';
        final rawTakhasos = convoyResponse['takhasos']?.toString() ?? '';

        final numParts = rawTakhasosNum
            .split(',')
            .map((e) => int.tryParse(e.trim()) ?? 1)
            .toList();

        final takhasosParts = rawTakhasos
            .split(',')
            .map((e) => e.trim().toLowerCase())
            .toList();

        int targetIndex = 0;
        if (takhasosParts.length > 1 &&
            takhasosParts[1].contains(_targetQueue)) {
          targetIndex = 1;
        }

        if (numParts.isNotEmpty && targetIndex < numParts.length) {
          _doctorSlotsCount = numParts[targetIndex];
        }
      }

      // 2. Fetch medicines for this convoy and specialty type
      final medicinesResponse = await _supabase
          .from('medicine')
          .select('id, name')
          .eq('convoyid', convoyId)
          .eq('type', _targetQueue)
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _convoyMedicines = List<Map<String, dynamic>>.from(medicinesResponse);
        });
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error loading convoy details: $e');
    } finally {
      if (mounted) setState(() => _isLoadingConvoy = false);
    }

    _subscribeToQueueStream();
  }

  void _subscribeToQueueStream() {
    final convoyId = widget.userData['convoyid'];

    _queueSubscription = _supabase
        .from('registrations')
        .stream(primaryKey: ['id'])
        .order('id', ascending: true)
        .listen(
          (data) {
            if (!mounted) return;

            final filteredData = data.where((row) {
              final queueFor = row['queuefor']?.toString().toLowerCase() ?? '';
              final matchesConvoy =
                  convoyId == null || row['convoyid'] == convoyId;

              final matchesQueue = queueFor == 'eyedoctorqueue' ||
                  queueFor.contains(_targetQueue) ||
                  queueFor.contains('${_targetQueue}inside');

              return matchesConvoy && matchesQueue;
            }).toList();

            setState(() {
              _allDepartmentPatients = filteredData;
            });
          },
          onError: (error) {
            if (mounted) _showSnackBar('Realtime connection error: $error');
          },
        );
  }

  Future<void> _enterPatient(dynamic patientId) async {
    final insideCount = _allDepartmentPatients
        .where((p) =>
            p['queuefor']?.toString().toLowerCase() ==
            '${_targetQueue}inside')
        .length;

    if (insideCount >= _doctorSlotsCount) {
      _showSnackBar(
        'All $_doctorSlotsCount doctor slot(s) are currently full! Wait for a doctor to finish.',
      );
      return;
    }

    final newQueueFor = '${_targetQueue}inside';

    try {
      await _supabase
          .from('registrations')
          .update({'queuefor': newQueueFor})
          .eq('id', patientId);

      if (mounted) {
        _showSnackBar('Patient moved inside to Doctor Examination!',
            isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error updating queue: $e');
      }
    }
  }

  void _showDoctorDoneDialog(Map<String, dynamic> patient) {
    final TextEditingController notesController = TextEditingController();
    bool eyeglassesRequired = false;
    bool operationRequired = false;
    final Set<dynamic> selectedMedicineIds = {};
    bool isSavingLocal = false;

    final bool isEyeDepartment = _targetQueue.contains('eye');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Complete Examination: ${patient['fullname'] ?? "Patient"}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Referrals (Eyeglasses & Operations) for Eye Department
                      if (isEyeDepartment) ...[
                        const Text(
                          'Referrals Required:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Card(
                          elevation: 1,
                          child: Column(
                            children: [
                              CheckboxListTile(
                                activeColor: Colors.indigo.shade800,
                                title: const Text('Eyeglasses Required'),
                                subtitle: const Text(
                                  'Route to Eyeglasses department',
                                ),
                                value: eyeglassesRequired,
                                onChanged: (val) {
                                  setDialogState(() {
                                    eyeglassesRequired = val ?? false;
                                  });
                                },
                              ),
                              const Divider(height: 1),
                              CheckboxListTile(
                                activeColor: Colors.indigo.shade800,
                                title: const Text('Operation Required'),
                                subtitle: const Text(
                                  'Route to Operation department',
                                ),
                                value: operationRequired,
                                onChanged: (val) {
                                  setDialogState(() {
                                    operationRequired = val ?? false;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Prescribe Medicines Checklist
                      Text(
                        'Prescribe ${_targetQueue.toUpperCase()} Medicines:',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_convoyMedicines.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'No medicines configured for this department.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        )
                      else
                        Card(
                          elevation: 1,
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _convoyMedicines.length,
                            itemBuilder: (context, index) {
                              final med = _convoyMedicines[index];
                              final medId = med['id'];
                              final isSelected = selectedMedicineIds.contains(
                                medId,
                              );

                              return CheckboxListTile(
                                activeColor: Colors.indigo.shade800,
                                title: Text(med['name'] ?? 'Unknown Medicine'),
                                value: isSelected,
                                onChanged: (checked) {
                                  setDialogState(() {
                                    if (checked == true) {
                                      selectedMedicineIds.add(medId);
                                    } else {
                                      selectedMedicineIds.remove(medId);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Clinical Notes Field
                      const Text(
                        'Doctor Notes:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Enter doctor notes or diagnosis...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSavingLocal ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSavingLocal
                      ? null
                      : () async {
                          setDialogState(() => isSavingLocal = true);

                          await _submitDoctorDone(
                            patient: patient,
                            eyeglasses: eyeglassesRequired,
                            operation: operationRequired,
                            medicineIds: selectedMedicineIds,
                            notes: notesController.text.trim(),
                          );

                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  child: isSavingLocal
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save & Finish'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitDoctorDone({
    required Map<String, dynamic> patient,
    required bool eyeglasses,
    required bool operation,
    required Set<dynamic> medicineIds,
    required String notes,
  }) async {
    final patientId = patient['id'];

    try {
      // 1. Insert selected medicines into patientmedicine table
      if (medicineIds.isNotEmpty) {
        final List<Map<String, dynamic>> rowsToInsert = medicineIds.map((medId) {
          return {
            'patientid': patientId,
            'medicineid': medId,
            'given': false,
          };
        }).toList();

        await _supabase.from('patientmedicine').insert(rowsToInsert);
      }

      // 2. Determine next queue destination
      final List<String> queueParts = [];
      if (eyeglasses) queueParts.add('eyeglasses');
      if (medicineIds.isNotEmpty) queueParts.add('pharmacy');
      if (operation) queueParts.add('operation');

      String nextQueueFor;
      if (queueParts.isNotEmpty) {
        nextQueueFor = queueParts.join(',');
      } else {
        // Fallback: check if secondary specialty exists
        final rawTakhasos2 = patient['takhasos2']?.toString().trim();
        if (rawTakhasos2 != null && rawTakhasos2.isNotEmpty) {
          nextQueueFor = '${rawTakhasos2.toLowerCase()}waiting';
        } else {
          nextQueueFor = 'ended';
        }
      }

      // 3. Specialty status updates
      final bool isTakhasos1Target = patient['takhasos1']
              .toString()
              .toLowerCase()
              .contains(_targetQueue) ??
          false;

      Map<String, dynamic> updatePayload = {
        'queuefor': nextQueueFor,
        'eyedoctornotes': notes,
      };

      if (isTakhasos1Target) {
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
          'Examination finished! Patient moved to: $nextQueueFor',
          isError: false,
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to save examination results');
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

  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.orange : Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.userData['name'] ?? 'Staff';

    // Separate patients inside examination room vs patients waiting outside in queue
    final insidePatients = _allDepartmentPatients
        .where((p) =>
            p['queuefor']?.toString().toLowerCase() ==
            '${_targetQueue}inside')
        .toList();

    final waitingQueuePatients = _allDepartmentPatients
        .where((p) {
          final q = p['queuefor']?.toString().toLowerCase() ?? '';
          return q == 'eyedoctorqueue' ||
              q == _targetQueue ||
              q == '${_targetQueue}waiting';
        })
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_departmentTitle),
        backgroundColor: Colors.indigo.shade800,
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
                      // Assistant Header Info Card
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
                              const SizedBox(height: 4),
                              Text(
                                'Convoy: ${_convoyName ?? "N/A"} | Queue: ${_targetQueue.toUpperCase()}',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Available Doctor Slots: $_doctorSlotsCount',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Live Doctor Slots Container (Patients Currently Inside)
                      const Text(
                        'Active Doctor Examination Slots',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),

                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _doctorSlotsCount,
                        itemBuilder: (context, index) {
                          final occupiedPatient = index < insidePatients.length
                              ? insidePatients[index]
                              : null;
                          final isOccupied = occupiedPatient != null;

                          return Card(
                            elevation: 3,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isOccupied
                                    ? Colors.green.shade700
                                    : Colors.grey.shade300,
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
                                      Text(
                                        'Doctor Room #${index + 1}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo.shade900,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isOccupied
                                              ? Colors.green.shade50
                                              : Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isOccupied
                                              ? 'INSIDE / EXAMINING'
                                              : 'AVAILABLE SLOT',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isOccupied
                                                ? Colors.green.shade800
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 20),
                                  if (isOccupied) ...[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                occupiedPatient['fullname'] ??
                                                    'Unknown Name',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Patient ID: #${occupiedPatient['id']} | Gender: ${occupiedPatient['gender'] ?? 'N/A'}',
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: () =>
                                              _showDoctorDoneDialog(
                                            occupiedPatient,
                                          ),
                                          icon: const Icon(
                                            Icons.check_circle,
                                            size: 18,
                                          ),
                                          label: const Text('DONE'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.green.shade700,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    const Center(
                                      child: Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8.0),
                                        child: Text(
                                          'Slot empty - Click ENTER on a waiting patient below',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Queue Count Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Waiting Queue',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.indigo.shade200),
                            ),
                            child: Text(
                              '${waitingQueuePatients.length} Waiting',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Waiting Patient List
                      waitingQueuePatients.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'No patients currently waiting for $_targetQueue.',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: waitingQueuePatients.length,
                              itemBuilder: (context, index) {
                                final patient = waitingQueuePatients[index];
                                final age = _calculateAge(patient['dob']);
                                final isFirstInLine = index == 0;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  elevation: isFirstInLine ? 3 : 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isFirstInLine
                                          ? Colors.indigo.shade600
                                          : Colors.grey.shade300,
                                      width: isFirstInLine ? 2 : 1,
                                    ),
                                  ),
                                  color: isFirstInLine
                                      ? Colors.indigo.shade50.withOpacity(0.4)
                                      : Colors.white,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: isFirstInLine
                                          ? Colors.indigo.shade700
                                          : Colors.indigo.shade100,
                                      child: Text(
                                        '#${patient['id']}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isFirstInLine
                                              ? Colors.white
                                              : Colors.indigo.shade900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            patient['fullname'] ?? 'N/A',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        if (isFirstInLine)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'NEXT UP',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade900,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Age: ${age != null ? "$age yrs" : "N/A"} | Gender: ${patient['gender'] ?? "N/A"}\n'
                                        'National ID: ${patient['id_number'] ?? "N/A"}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                Colors.indigo.shade700,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: () => _enterPatient(
                                            patient['id'],
                                          ),
                                          child: const Text('ENTER'),
                                        ),
                                      ],
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