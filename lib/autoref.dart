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

  // Full list of patients fetched in realtime
  List<Map<String, dynamic>> _allPatients = [];

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

    // 2. Setup Realtime Stream for patients in 'autorefwaiting' or 'inautoref'
    _subscribeToQueueStream();
  }

  void _subscribeToQueueStream() {
    final convoyId = widget.userData['convoyid'];

    // Stream registrations in realtime
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
              final isAutorefState =
                  queueFor == 'autorefwaiting' || queueFor == 'inautoref';

              return matchesConvoy && isAutorefState;
            }).toList();

            setState(() {
              _allPatients = filteredData;
            });
          },
          onError: (error) {
            if (mounted) _showSnackBar('Realtime connection error: $error');
          },
        );
  }

  Future<void> _assignPatientToSlot(dynamic patientId) async {
    final inAutorefCount = _allPatients
        .where((p) => p['queuefor']?.toString().toLowerCase() == 'inautoref')
        .length;

    if (_deviceCount > 0 && inAutorefCount >= _deviceCount) {
      _showSnackBar('All Autoref slots are currently full!');
      return;
    }

    try {
      await _supabase
          .from('registrations')
          .update({'queuefor': 'inautoref'})
          .eq('id', patientId);

      if (mounted) {
        _showSnackBar('Patient assigned to Autoref slot!', isError: false);
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to assign patient to slot');
    }
  }

  Future<void> _completeAutoref(dynamic patientId) async {
    try {
      // Mark autoref = true and update queuefor to eyedoctorqueue
      await _supabase
          .from('registrations')
          .update({'autoref': true, 'queuefor': 'eyedoctorqueue'})
          .eq('id', patientId);

      if (mounted) {
        _showSnackBar('Autoref completed! Moved to Eye Doctor Queue.',
            isError: false);
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to complete patient');
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

    // Separate patients actively in slots vs those waiting in queue
    final inAutorefPatients = _allPatients
        .where((p) => p['queuefor']?.toString().toLowerCase() == 'inautoref')
        .toList();

    final autorefWaitingPatients = _allPatients
        .where((p) =>
            p['queuefor']?.toString().toLowerCase() == 'autorefwaiting')
        .toList();

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

                      // Top Dropdown Expansion Container with Patient List & Plus Buttons
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.deepOrange.shade200),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            title: Text(
                              'Autoref Waiting Queue',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange.shade900,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.deepOrange.shade200,
                                ),
                              ),
                              child: Text(
                                '${autorefWaitingPatients.length} Waiting',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange.shade900,
                                ),
                              ),
                            ),
                            children: [
                              const Divider(height: 1),
                              if (autorefWaitingPatients.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  child: const Center(
                                    child: Text(
                                      'No patients currently in Autoref Queue.',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: autorefWaitingPatients.length,
                                    itemBuilder: (context, index) {
                                      final patient =
                                          autorefWaitingPatients[index];

                                      return Card(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        color: Colors.grey.shade50,
                                        child: ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor:
                                                Colors.deepOrange.shade100,
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
                                            'Gender: ${patient['gender'] ?? 'N/A'} | ID: ${patient['id_number'] ?? 'N/A'}',
                                          ),
                                          trailing: IconButton(
                                            icon: const Icon(
                                              Icons.add_circle,
                                              color: Colors.deepOrange,
                                              size: 32,
                                            ),
                                            onPressed: () =>
                                                _assignPatientToSlot(
                                              patient['id'],
                                            ),
                                            tooltip: 'Add to Autoref Slot',
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
                      const SizedBox(height: 24),

                      // Active Machines Section
                      const Text(
                        'Autoref Machines',
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
                            final occupiedPatient =
                                index < inAutorefPatients.length
                                    ? inAutorefPatients[index]
                                    : null;

                            final isOccupied = occupiedPatient != null;

                            return Card(
                              elevation: 3,
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isOccupied
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
                                            color: isOccupied
                                                ? Colors.orange.shade50
                                                : Colors.green.shade50,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isOccupied ? 'Occupied' : 'Ready',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: isOccupied
                                                  ? Colors.orange.shade800
                                                  : Colors.green.shade800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 20),

                                    if (isOccupied) ...[
                                      // Machine is occupied by an active patient
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
                                                  'ID: #${occupiedPatient['id']} | Gender: ${occupiedPatient['gender'] ?? 'N/A'}',
                                                  style: const TextStyle(
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () => _completeAutoref(
                                              occupiedPatient['id'],
                                            ),
                                            icon: const Icon(
                                              Icons.check_circle,
                                              size: 18,
                                            ),
                                            label: const Text('Done'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.green.shade700,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 12,
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
                                          padding: EdgeInsets.symmetric(
                                            vertical: 12.0,
                                          ),
                                          child: Text(
                                            'Slot Available - Add patient from the top dropdown list',
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
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}