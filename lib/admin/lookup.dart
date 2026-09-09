import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PatientLookupWidget extends StatefulWidget {
  final dynamic convoyId;
  final VoidCallback onShowAllPatients;

  const PatientLookupWidget({
    super.key,
    required this.convoyId,
    required this.onShowAllPatients,
  });

  @override
  State<PatientLookupWidget> createState() => _PatientLookupWidgetState();
}

class _PatientLookupWidgetState extends State<PatientLookupWidget> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _patientSearchController =
      TextEditingController();

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

  Future<void> _searchAndShowPatient() async {
    final codeText = _patientSearchController.text.trim();
    final patientId = int.tryParse(codeText);

    if (patientId == null) {
      _showSnackBar('Please enter a valid numeric Patient ID');
      return;
    }

    try {
      final response = await _supabase
          .from('registrations')
          .select('*')
          .eq('convoyid', widget.convoyId)
          .eq('id', patientId)
          .maybeSingle();

      if (response == null) {
        if (mounted) _showSnackBar('No patient found with ID: #$patientId');
        return;
      }

      if (mounted) {
        _showPatientDetailDialog(response);
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to fetch patient details: $error');
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

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.all(16),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          title: const Text(
            'Patient Movement & Profile',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                  subtitle: isTakhasos1Done
                      ? 'Examination Completed'
                      : (queueFor.contains(takhasos1.toLowerCase())
                            ? 'Currently in Queue'
                            : 'Pending'),
                  isDone: isTakhasos1Done,
                  isActive: queueFor.contains(takhasos1.toLowerCase()),
                ),

                // Step 4: Secondary Specialty (Takhasos 2) - if assigned
                if (takhasos2 != null && takhasos2.trim().isNotEmpty)
                  _buildTimelineStep(
                    title: '$takhasos2 Doctor',
                    subtitle: isTakhasos2Done
                        ? 'Examination Completed'
                        : (queueFor.contains(takhasos2.toLowerCase())
                              ? 'Currently in Queue'
                              : 'Pending'),
                    isDone: isTakhasos2Done,
                    isActive: queueFor.contains(takhasos2.toLowerCase()),
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
            TextButton(
              onPressed: () => Navigator.pop(context),
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
  }

  @override
  void dispose() {
    _patientSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Patient Quick Lookup',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _patientSearchController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Enter Patient ID only',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _searchAndShowPatient(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _searchAndShowPatient,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  child: const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onShowAllPatients,
                icon: const Icon(Icons.people_alt, color: Colors.purple),
                label: const Text(
                  'Show All Patients',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.purple.shade700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
