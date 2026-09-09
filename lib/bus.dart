import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OperationBusPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const OperationBusPage({super.key, required this.userData});

  @override
  State<OperationBusPage> createState() => _OperationBusPageState();
}

class _OperationBusPageState extends State<OperationBusPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _convoyName;
  bool _isLoadingConvoy = true;
  bool _isSaving = false;

  // Realtime subscription & patient queues
  StreamSubscription<List<Map<String, dynamic>>>? _registrationsSubscription;
  List<Map<String, dynamic>> _waitingOperationPatients = [];

  // Dropdown selected item
  Map<String, dynamic>? _selectedPatient;

  // Batch staging list
  final List<Map<String, dynamic>> _stagedPatients = [];

  @override
  void initState() {
    super.initState();
    _loadConvoyDetails();
  }

  Future<void> _loadConvoyDetails() async {
    final convoyId = widget.userData['convoyid'];

    if (convoyId == null) {
      setState(() => _isLoadingConvoy = false);
      return;
    }

    try {
      final convoyResponse = await _supabase
          .from('convoys')
          .select('name')
          .eq('id', convoyId)
          .maybeSingle();

      if (convoyResponse != null) {
        _convoyName = convoyResponse['name'] ?? 'Operation Bus';
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error loading convoy info: $e');
    } finally {
      if (mounted) setState(() => _isLoadingConvoy = false);
    }

    _subscribeToOperationQueueStream();
  }

  void _subscribeToOperationQueueStream() {
    final convoyId = widget.userData['convoyid'];

    _registrationsSubscription = _supabase
        .from('registrations')
        .stream(primaryKey: ['id'])
        .order('id', ascending: true)
        .listen(
          (data) {
            if (!mounted) return;

            final filteredData = data.where((r) {
              final queueFor = r['queuefor']?.toString().toLowerCase() ?? '';
              final matchesConvoy =
                  convoyId == null || r['convoyid'] == convoyId;

              return matchesConvoy && queueFor.contains('operation');
            }).toList();

            setState(() {
              _waitingOperationPatients = filteredData;
            });
          },
          onError: (error) {
            if (mounted) _showSnackBar('Realtime connection error: $error');
          },
        );
  }

  void _stagePatient(Map<String, dynamic> patient) {
    final isAlreadyStaged = _stagedPatients.any(
      (p) => p['id'] == patient['id'],
    );
    if (isAlreadyStaged) {
      _showSnackBar('Patient is already in the processing list');
      return;
    }

    setState(() {
      _stagedPatients.add(patient);
      _selectedPatient = null;
    });
  }

  void _removeStagedPatient(int index) {
    setState(() {
      _stagedPatients.removeAt(index);
    });
  }

  Future<void> _finishAndMarkAsEnded() async {
    if (_stagedPatients.isEmpty) {
      _showSnackBar('No patients added to the list');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final List<dynamic> patientIds = _stagedPatients
          .map((p) => p['id'])
          .toList();

      // Batch update queuefor to 'ended'
      await _supabase
          .from('registrations')
          .update({'queuefor': 'ended'})
          .filter('id', 'in', patientIds);

      if (mounted) {
        _showSnackBar(
          'Successfully marked ${_stagedPatients.length} patient(s) as ended!',
          isError: false,
        );
        setState(() {
          _stagedPatients.clear();
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to update patient statuses');
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
    _registrationsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.userData['name'] ?? 'Staff';
    final userRole = widget.userData['role']?.toString() ?? 'operationbus';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operation Bus Management'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingConvoy
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Card
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
                                'Convoy: ${_convoyName ?? "N/A"} | Role: $userRole',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Queue Counter Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Operation Bus Queue',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Patients scheduled for operation',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${_waitingOperationPatients.length} Waiting',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Dropdown Selection
                      const Text(
                        'Select Patient for Operation Bus',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        value: _selectedPatient,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Select patient queued for operation...',
                        ),
                        items: _waitingOperationPatients.map((p) {
                          return DropdownMenuItem<Map<String, dynamic>>(
                            value: p,
                            child: Text('#${p['id']} - ${p['fullname']}'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            _stagePatient(val);
                          }
                        },
                      ),
                      const SizedBox(height: 24),

                      // Batch Processing Container
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
                                  const Text(
                                    'Selected Bus Patients',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${_stagedPatients.length} Added',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),

                              if (_stagedPatients.isEmpty)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Text(
                                      'No patients added to the list yet.',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _stagedPatients.length,
                                  itemBuilder: (context, index) {
                                    final patient = _stagedPatients[index];
                                    final age = _calculateAge(patient['dob']);

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      color: Colors.grey.shade50,
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.red.shade100,
                                          child: Text(
                                            '#${patient['id']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red.shade900,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          patient['fullname'] ?? 'Unknown',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'Age: ${age != null ? "$age yrs" : "N/A"} | ID: ${patient['id_number'] ?? "N/A"}',
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle,
                                            color: Colors.red,
                                          ),
                                          onPressed: () =>
                                              _removeStagedPatient(index),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              const SizedBox(height: 16),

                              // Save Button
                              _isSaving
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _stagedPatients.isEmpty
                                            ? null
                                            : _finishAndMarkAsEnded,
                                        icon: const Icon(Icons.check_circle),
                                        label: Text(
                                          'Save & Mark as Ended (${_stagedPatients.length})',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red.shade800,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                            ],
                          ),
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
