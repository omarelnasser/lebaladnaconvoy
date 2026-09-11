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

  bool _isLoadingConvoy = true;

  // Realtime queue state
  StreamSubscription<List<Map<String, dynamic>>>? _queueSubscription;
  List<Map<String, dynamic>> _queuePatients = [];

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
      final convoyResponse = await _supabase
          .from('convoys')
          .select('name')
          .eq('id', convoyId)
          .maybeSingle();

      if (convoyResponse != null) {
        _convoyName = convoyResponse['name'] ?? 'Unknown Convoy';
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

              // Checks if target queue key exists in queuefor (e.g. 'eye', 'batna', 'autoref', 'eyeglasses')
              final matchesQueue = queueFor.contains(_targetQueue);

              return matchesConvoy && matchesQueue;
            }).toList();

            setState(() {
              _queuePatients = filteredData;
            });
          },
          onError: (error) {
            if (mounted) _showSnackBar('Realtime connection error: $error');
          },
        );
  }

  Future<void> _enterPatient(dynamic patientId) async {
    final newQueueFor = _targetQueue == 'eye'
        ? 'eyeinside'
        : _targetQueue == 'batna'
            ? 'batnainside'
            : '${_targetQueue}inside';

    try {
      await _supabase
          .from('registrations')
          .update({'queuefor': newQueueFor})
          .eq('id', patientId);

      if (mounted) {
        _showSnackBar('Patient moved to $newQueueFor');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error updating queue: $e');
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
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
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
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
                                'Convoy: ${_convoyName ?? "N/A"} | Department Queue: ${_targetQueue.toUpperCase()}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Queue Count Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Active Department Queue',
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
                              '${_queuePatients.length} Waiting',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Patient List
                      Expanded(
                        child: _queuePatients.isEmpty
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
                                itemCount: _queuePatients.length,
                                itemBuilder: (context, index) {
                                  final patient = _queuePatients[index];
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
                                      contentPadding:
                                          const EdgeInsets.symmetric(
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
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}