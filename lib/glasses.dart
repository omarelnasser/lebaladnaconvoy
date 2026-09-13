import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GlassesPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const GlassesPage({super.key, required this.userData});

  @override
  State<GlassesPage> createState() => _GlassesPageState();
}

class _GlassesPageState extends State<GlassesPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _convoyName;
  bool _isLoadingConvoy = true;

  // Realtime queue state
  StreamSubscription<List<Map<String, dynamic>>>? _queueSubscription;

  // Full fetched queue list
  List<Map<String, dynamic>> _allGlassesPatients = [];

  // List of patients with eyeglassestrue == true
  List<Map<String, dynamic>> _completedGlassesPatients = [];

  @override
  void initState() {
    super.initState();
    _loadConvoyAndSubscribe();
  }

  Future<void> _loadConvoyAndSubscribe() async {
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
        setState(() {
          _convoyName = convoyResponse['name'] ?? 'Unknown Convoy';
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

            // Filter active queue patients
            final filteredActive = data.where((row) {
              final queueFor = row['queuefor']?.toString().toLowerCase() ?? '';
              final matchesConvoy =
                  convoyId == null || row['convoyid'] == convoyId;

              final isGlassesState = queueFor.contains('eyeglasses') ||
                  queueFor.contains('insideeyeglasses');

              return matchesConvoy && isGlassesState;
            }).toList();

            // Filter completed eyeglasses patients
            final filteredCompleted = data.where((row) {
              final matchesConvoy =
                  convoyId == null || row['convoyid'] == convoyId;
              final isEyeglassesDone = row['eyeglassestrue'] == true;

              return matchesConvoy && isEyeglassesDone;
            }).toList();

            setState(() {
              _allGlassesPatients = filteredActive;
              _completedGlassesPatients = filteredCompleted;
            });
          },
          onError: (error) {
            if (mounted) _showSnackBar('Realtime connection error: $error');
          },
        );
  }

  Future<void> _enterPatient(Map<String, dynamic> patient) async {
    final patientId = patient['id'];
    final rawQueueFor = patient['queuefor']?.toString() ?? '';

    // Replace eyeglasses with insideeyeglasses in queuefor string
    final List<String> queueParts =
        rawQueueFor.split(',').map((e) => e.trim()).toList();

    for (int i = 0; i < queueParts.length; i++) {
      if (queueParts[i].toLowerCase() == 'eyeglasses') {
        queueParts[i] = 'insideeyeglasses';
        break;
      }
    }

    final newQueueFor = queueParts.join(',');

    try {
      await _supabase
          .from('registrations')
          .update({'queuefor': newQueueFor})
          .eq('id', patientId);

      if (mounted) {
        _showSnackBar(
          'Patient moved inside Eyeglasses fitting!',
          isError: false,
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to move patient inside');
    }
  }

  Future<void> _completeGlasses(Map<String, dynamic> patient) async {
    final patientId = patient['id'];
    final rawQueueFor = patient['queuefor']?.toString() ?? '';

    // Remove 'insideeyeglasses' or 'eyeglasses' from queue string
    List<String> queueParts = rawQueueFor
        .split(',')
        .map((e) => e.trim())
        .where((e) =>
            e.toLowerCase() != 'eyeglasses' &&
            e.toLowerCase() != 'insideeyeglasses' &&
            e.isNotEmpty)
        .toList();

    // Determine next queue state
    String nextQueueFor;
    if (queueParts.isNotEmpty) {
      nextQueueFor = queueParts.join(',');
    } else {
      nextQueueFor = 'ended';
    }

    try {
      // Set eyeglassestrue = true and update queuefor
      await _supabase
          .from('registrations')
          .update({'eyeglassestrue': true, 'queuefor': nextQueueFor})
          .eq('id', patientId);

      if (mounted) {
        _showSnackBar(
          'Eyeglasses fitting completed! Patient moved to: $nextQueueFor',
          isError: false,
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to complete patient');
    }
  }

  void _showCompletedGlassesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Completed Glasses',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Text(
                  '${_completedGlassesPatients.length} Total',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: _completedGlassesPatients.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'No patients have completed eyeglasses yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _completedGlassesPatients.length,
                    itemBuilder: (context, index) {
                      final patient = _completedGlassesPatients[index];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.green.shade50.withOpacity(0.4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade100,
                            child: Text(
                              '#${patient['id']}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900,
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
                            'National ID: ${patient['id_number'] ?? "N/A"}\nPhone: ${patient['phone'] ?? "N/A"}',
                          ),
                          trailing: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
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
    _queueSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.userData['name'] ?? 'N/A';
    final userRole = widget.userData['role'] ?? 'Glasses Assistant';

    // Separate patients inside fitting room vs patients waiting outside in queue
    final insidePatients = _allGlassesPatients.where((p) {
      final q = p['queuefor']?.toString().toLowerCase() ?? '';
      return q.contains('insideeyeglasses');
    }).toList();

    final waitingPatients = _allGlassesPatients.where((p) {
      final q = p['queuefor']?.toString().toLowerCase() ?? '';
      return q.contains('eyeglasses') && !q.contains('insideeyeglasses');
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eyeglasses Department'),
        backgroundColor: Colors.purple.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_red_eye_outlined),
            tooltip: 'View Completed Glasses',
            onPressed: _showCompletedGlassesDialog,
          ),
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
                      const SizedBox(height: 16),

                      // Button to View All Completed Glasses
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _showCompletedGlassesDialog,
                          icon: const Icon(Icons.check_circle,
                              color: Colors.purple),
                          label: Text(
                            'View Completed Glasses (${_completedGlassesPatients.length})',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade900,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: Colors.purple.shade800,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Active Inside Fitting Container
                      const Text(
                        'Inside Eyeglasses Fitting',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (insidePatients.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Center(
                            child: Text(
                              'No patient currently inside fitting room.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: insidePatients.length,
                          itemBuilder: (context, index) {
                            final patient = insidePatients[index];

                            return Card(
                              elevation: 3,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.purple.shade700,
                                  width: 1.5,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            patient['fullname'] ??
                                                'Unknown Name',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Patient ID: #${patient['id']} | Gender: ${patient['gender'] ?? 'N/A'}',
                                            style: const TextStyle(
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () => _completeGlasses(patient),
                                      icon: const Icon(
                                        Icons.check_circle,
                                        size: 18,
                                      ),
                                      label: const Text('Complete'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade700,
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
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 24),

                      // Waiting Queue Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Eyeglasses Waiting Queue',
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
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.purple.shade200,
                              ),
                            ),
                            child: Text(
                              '${waitingPatients.length} Waiting',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Waiting Patient List
                      waitingPatients.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'No patients currently waiting for eyeglasses.',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: waitingPatients.length,
                              itemBuilder: (context, index) {
                                final patient = waitingPatients[index];
                                final age = _calculateAge(patient['dob']);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.purple.shade100,
                                      child: Text(
                                        '#${patient['id']}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purple.shade900,
                                          fontSize: 12,
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
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Age: ${age != null ? "$age yrs" : "N/A"} | Gender: ${patient['gender'] ?? "N/A"}\n'
                                        'National ID: ${patient['id_number'] ?? "N/A"}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    trailing: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.purple.shade800,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () => _enterPatient(patient),
                                      child: const Text('ENTER'),
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