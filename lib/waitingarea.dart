import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WaitingAreaPage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const WaitingAreaPage({super.key, required this.userData});

  @override
  State<WaitingAreaPage> createState() => _WaitingAreaPageState();
}

class _WaitingAreaPageState extends State<WaitingAreaPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _convoyName;
  String? _takhasos1;
  String? _takhasos2;

  bool _isLoading = true;
  bool _isSaving = false;

  // Realtime listeners
  StreamSubscription<List<Map<String, dynamic>>>? _registrationsSubscription;

  // Patient lists and counters
  List<Map<String, dynamic>> _outsidePatientsTakhasos1 = [];
  List<Map<String, dynamic>> _outsidePatientsTakhasos2 = [];

  int _insideCountTakhasos1 = 0;
  int _insideCountTakhasos2 = 0;

  // Staging list for unlimited patients
  final List<Map<String, dynamic>> _stagedPatients = [];

  @override
  void initState() {
    super.initState();
    _loadConvoyDetails();
  }

  Future<void> _loadConvoyDetails() async {
    final convoyId = widget.userData['convoyid'];
    if (convoyId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final convoyResponse = await _supabase
          .from('convoys')
          .select('name, takhasos')
          .eq('id', convoyId)
          .maybeSingle();

      if (convoyResponse != null) {
        _convoyName = convoyResponse['name'] ?? 'Convoy';
        final rawTakhasos = convoyResponse['takhasos']?.toString() ?? '';
        final parts = rawTakhasos
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        _takhasos1 = parts.isNotEmpty ? parts[0] : 'Specialty 1';
        _takhasos2 = parts.length > 1 ? parts[1] : null;
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error loading convoy info: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    _subscribeToQueueStream();
  }

  void _subscribeToQueueStream() {
    final convoyId = widget.userData['convoyid'];

    _registrationsSubscription = _supabase
        .from('registrations')
        .stream(primaryKey: ['id'])
        .eq('convoyid', convoyId)
        .listen((data) {
          if (!mounted) return;

          final t1Lower = _takhasos1?.toLowerCase() ?? '';
          final t2Lower = _takhasos2?.toLowerCase() ?? '';

          // Filter patients waiting outside
          final outsideT1 = data.where((r) {
            final q = r['queuefor']?.toString().toLowerCase() ?? '';
            final t1 = r['takhasos1']?.toString().toLowerCase() ?? '';
            return q == 'outside' && t1.contains(t1Lower);
          }).toList();

          final outsideT2 = data.where((r) {
            final q = r['queuefor']?.toString().toLowerCase() ?? '';
            final t2 = r['takhasos2']?.toString().toLowerCase() ?? '';
            return q == 'outside' && t2Lower.isNotEmpty && t2.contains(t2Lower);
          }).toList();

          // Calculate counts inside active queues
          final countT1 = data.where((r) {
            final q = r['queuefor']?.toString().toLowerCase() ?? '';
            final t1 = r['takhasos1']?.toString().toLowerCase() ?? '';
            return (q.contains('autoref') || q.contains(t1Lower)) &&
                t1.contains(t1Lower);
          }).length;

          final countT2 = data.where((r) {
            final q = r['queuefor']?.toString().toLowerCase() ?? '';
            final t2 = r['takhasos2']?.toString().toLowerCase() ?? '';
            return t2Lower.isNotEmpty &&
                (q.contains('autoref') || q.contains(t2Lower)) &&
                t2.contains(t2Lower);
          }).length;

          setState(() {
            _outsidePatientsTakhasos1 = outsideT1;
            _outsidePatientsTakhasos2 = outsideT2;
            _insideCountTakhasos1 = countT1;
            _insideCountTakhasos2 = countT2;
          });
        });
  }

  void _openSelectionPopup(
    String targetSpecialty,
    List<Map<String, dynamic>> availablePatients,
  ) {
    // Filter out patients that are already in staging
    final unstagedPatients = availablePatients.where((p) {
      return !_stagedPatients.any((staged) => staged['id'] == p['id']);
    }).toList();

    // Sort patients by ID in ascending order
    unstagedPatients.sort((a, b) {
      final idA = a['id'] is int ? a['id'] as int : int.tryParse(a['id'].toString()) ?? 0;
      final idB = b['id'] is int ? b['id'] as int : int.tryParse(b['id'].toString()) ?? 0;
      return idA.compareTo(idB);
    });

    if (unstagedPatients.isEmpty) {
      _showSnackBar('No available unstaged patients for $targetSpecialty');
      return;
    }

    final Set<dynamic> locallySelectedIds = {};

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Select Patients for $targetSpecialty',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Selected: ${locallySelectedIds.length} patient(s)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.teal.shade800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: unstagedPatients.length,
                        itemBuilder: (context, index) {
                          final patient = unstagedPatients[index];
                          final patientId = patient['id'];
                          final isChecked = locallySelectedIds.contains(
                            patientId,
                          );

                          return CheckboxListTile(
                            activeColor: Colors.teal.shade800,
                            title: Text(
                              '#$patientId - ${patient['fullname'] ?? "Unknown"}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              'National ID: ${patient['id_number'] ?? "N/A"}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: isChecked,
                            onChanged: (bool? checked) {
                              setPopupState(() {
                                if (checked == true) {
                                  locallySelectedIds.add(patientId);
                                } else {
                                  locallySelectedIds.remove(patientId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade800,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: locallySelectedIds.isEmpty
                      ? null
                      : () {
                          setState(() {
                            for (final p in unstagedPatients) {
                              if (locallySelectedIds.contains(p['id'])) {
                                final stagedEntry = Map<String, dynamic>.from(
                                  p,
                                );
                                stagedEntry['target_specialty'] =
                                    targetSpecialty;
                                _stagedPatients.add(stagedEntry);
                              }
                            }
                          });
                          Navigator.pop(context);
                        },
                  child: Text('Add Selected (${locallySelectedIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _removeStagedPatient(int index) {
    setState(() {
      _stagedPatients.removeAt(index);
    });
  }

  Future<void> _sendStagedPatientsToQueue() async {
    if (_stagedPatients.isEmpty) {
      _showSnackBar('No patients selected in staging list');
      return;
    }

    setState(() => _isSaving = true);

    try {
      for (final patient in _stagedPatients) {
        final String targetSpecialty =
            patient['target_specialty']?.toString().toLowerCase() ?? '';

        // Determine destination column string based on specialty
        String nextQueue;
        if (targetSpecialty.contains('eye')) {
          nextQueue = 'autorefwaiting';
        } else if (targetSpecialty.contains('batna')) {
          nextQueue = 'batnawaiting';
        } else {
          nextQueue = '${targetSpecialty}waiting';
        }

        await _supabase
            .from('registrations')
            .update({'queuefor': nextQueue})
            .eq('id', patient['id']);
      }

      if (mounted) {
        _showSnackBar(
          'Successfully moved ${_stagedPatients.length} patient(s) to queue!',
          isError: false,
        );
        setState(() {
          _stagedPatients.clear();
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to update patient queues');
    } finally {
      if (mounted) setState(() => _isSaving = false);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Waiting Area Management'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // User & Convoy Header Card
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
                              Text('Convoy: ${_convoyName ?? "N/A"}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Queue Counters Display
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.teal.shade200),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    _takhasos1 ?? 'Takhasos 1',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$_insideCountTakhasos1 Inside',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_takhasos2 != null) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.indigo.shade200,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      _takhasos2!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$_insideCountTakhasos2 Inside',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Multi-Select Popup Button for Specialty 1
                      Text(
                        'Select Patients for ${_takhasos1 ?? "Takhasos 1"}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _openSelectionPopup(
                            _takhasos1 ?? 'Takhasos 1',
                            _outsidePatientsTakhasos1,
                          ),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: Text(
                            'Choose Patients for ${_takhasos1 ?? "Takhasos 1"} (${_outsidePatientsTakhasos1.length} Available)',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.teal.shade800),
                            foregroundColor: Colors.teal.shade800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Multi-Select Popup Button for Specialty 2 (if available)
                      if (_takhasos2 != null) ...[
                        Text(
                          'Select Patients for $_takhasos2',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openSelectionPopup(
                              _takhasos2!,
                              _outsidePatientsTakhasos2,
                            ),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: Text(
                              'Choose Patients for $_takhasos2 (${_outsidePatientsTakhasos2.length} Available)',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.indigo.shade800),
                              foregroundColor: Colors.indigo.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Staging Area List Container
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
                                    'Staged Batch',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${_stagedPatients.length} Selected',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal.shade800,
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
                                      'No patients added to staging list yet.',
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
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      color: Colors.grey.shade50,
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.teal.shade100,
                                          child: Text(
                                            '#${patient['id']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.teal.shade900,
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
                                          'Target: ${patient['target_specialty']}',
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

                              // Send Button
                              _isSaving
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _stagedPatients.isEmpty
                                            ? null
                                            : _sendStagedPatientsToQueue,
                                        icon: const Icon(Icons.send),
                                        label: Text(
                                          'Send Batch to Queue (${_stagedPatients.length})',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal.shade800,
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