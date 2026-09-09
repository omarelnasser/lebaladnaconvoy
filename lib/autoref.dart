import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AutorefPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const AutorefPage({super.key, required this.userData});

  @override
  State<AutorefPage> createState() => _AutorefPageState();
}

class _AutorefPageState extends State<AutorefPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _convoyName;
  int _deviceCount = 0;
  bool _isLoadingConvoy = true;

  // Stream subscription for realtime updates
  StreamSubscription<List<Map<String, dynamic>>>? _queueSubscription;
  List<Map<String, dynamic>> _queuePatients = [];

  @override
  void initState() {
    super.initState();
    _loadConvoyAndStartRealtime();
  }

  Future<void> _loadConvoyAndStartRealtime() async {
    final convoyId = widget.userData['convoyid'];

    if (convoyId == null) {
      setState(() => _isLoadingConvoy = false);
      return;
    }

    try {
      // 1. Fetch Convoy name and device count
      final convoyResponse = await _supabase
          .from('convoys')
          .select('name, autorefnumber')
          .eq('id', convoyId)
          .maybeSingle();

      if (convoyResponse != null) {
        _convoyName = convoyResponse['name'] ?? 'Unknown Convoy';
        _deviceCount = convoyResponse['autorefnumber'] is int
            ? convoyResponse['autorefnumber']
            : int.tryParse(
                    convoyResponse['autorefnumber']?.toString() ?? '0',
                  ) ??
                  0;
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error loading convoy details: $e');
    } finally {
      if (mounted) setState(() => _isLoadingConvoy = false);
    }

    // 2. Setup Realtime Stream for queuefor = 'autoref'
    _subscribeToQueueStream();
  }

  void _subscribeToQueueStream() {
    final convoyId = widget.userData['convoyid'];

    // Stream registrations in realtime
    _queueSubscription = _supabase
        .from('registrations')
        .stream(primaryKey: ['id'])
        .eq('queuefor', 'autoref')
        .order('id', ascending: true)
        .listen(
          (data) {
            if (!mounted) return;

            // Filter by convoyid in application layer if stream filter isn't chained
            final filteredData = data.where((row) {
              if (convoyId == null) return true;
              return row['convoyid'] == convoyId;
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

  Future<void> _completeAutoref(dynamic patientId) async {
    try {
      // Update registration record setting autoref = true
      await _supabase
          .from('registrations')
          .update({'autoref': true, 'queuefor': 'eye'})
          .eq('id', patientId);

      if (mounted) {
        _showSnackBar('Autoref marked as completed!', isError: false);
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to update patient record');
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
    final userRole = widget.userData['role'] ?? 'Autoref';

    // Separate patients assigned to active machine slots vs those waiting in queue
    final activePatients = _queuePatients.take(_deviceCount).toList();
    final waitingQueue = _queuePatients.skip(_deviceCount).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Autoref Module'),
        backgroundColor: Colors.deepOrange,
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
                              const SizedBox(height: 4),
                              Text(
                                'Available Autoref Devices: $_deviceCount',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Active Machines Section
                      const Text(
                        'Active Machines',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_deviceCount <= 0)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'No Autoref devices configured for this convoy.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _deviceCount,
                          itemBuilder: (context, index) {
                            final hasPatient = index < activePatients.length;
                            final patient = hasPatient
                                ? activePatients[index]
                                : null;

                            return Card(
                              elevation: 3,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: hasPatient
                                      ? Colors.deepOrange
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
                                          'Machine #${index + 1}',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.deepOrange,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: hasPatient
                                                ? Colors.orange.shade50
                                                : Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            hasPatient ? 'Occupied' : 'Ready',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: hasPatient
                                                  ? Colors.orange.shade800
                                                  : Colors.green.shade800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 20),
                                    if (hasPatient) ...[
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
                                                  patient!['fullname'] ??
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
                                            onPressed: () =>
                                                _completeAutoref(patient['id']),
                                            icon: const Icon(
                                              Icons.check,
                                              size: 18,
                                            ),
                                            label: const Text('Complete'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.deepOrange,
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ] else ...[
                                      const Center(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8.0,
                                          ),
                                          child: Text(
                                            'Waiting for next patient in queue...',
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

                      const SizedBox(height: 24),

                      // Waiting Queue Section
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
                              'No additional patients in waiting queue.',
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
                                  backgroundColor: Colors.deepOrange.shade100,
                                  child: Text(
                                    '#${patient['id']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepOrange,
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
                                  'Gender: ${patient['gender'] ?? 'N/A'}',
                                ),
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
