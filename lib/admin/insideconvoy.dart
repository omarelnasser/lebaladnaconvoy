import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lookup.dart';

class InsideConvoyPage extends StatefulWidget {
  final Map<String, dynamic> convoy;

  const InsideConvoyPage({super.key, required this.convoy});

  @override
  State<InsideConvoyPage> createState() => _InsideConvoyPageState();
}

class _InsideConvoyPageState extends State<InsideConvoyPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late String _convoyName;
  late bool _isEnded;
  late bool _isBreak;
  bool _isUpdating = false;

  // Realtime Statistics State
  StreamSubscription<List<Map<String, dynamic>>>? _statsSubscription;
  Map<String, int> _stats = {
    'total': 0,
    'outside': 0,
    'autoref': 0,
    'eye': 0,
    'batna': 0,
    'pharmacy': 0,
    'eyeglasses': 0,
    'operation': 0,
    'ended': 0,
  };
  bool _isLoadingStats = true;

  // Medicines state
  List<Map<String, dynamic>> _medicines = [];
  bool _isLoadingMedicines = true;

  // Roles state
  List<Map<String, dynamic>> _roles = [];
  bool _isLoadingRoles = true;

  final List<String> _availableRoles = [
    'registration',
    'autoref',
    'eyedoctor',
    'pharmacy',
    'batnadoctor',
    'waitingarea',
    'operationbus',
    'general',
    'eyedoctorassistant',
    'autorefdoctorassistant',
    'batnadoctorassistant',
    'glassesassistant',
  ];

  @override
  void initState() {
    super.initState();
    _convoyName = widget.convoy['name'] ?? 'Unnamed Convoy';
    _isEnded = widget.convoy['ended'] == true;
    _isBreak = widget.convoy['break'] == true;
    _fetchMedicines();
    _fetchRoles();
    _subscribeToLiveStats();
  }

  // ---------------------------------------------------------------------------
  // Realtime Statistics Listener
  // ---------------------------------------------------------------------------
  void _subscribeToLiveStats() {
    final convoyId = widget.convoy['id'];

    _statsSubscription = _supabase
        .from('registrations')
        .stream(primaryKey: ['id'])
        .eq('convoyid', convoyId)
        .listen(
          (data) {
            if (!mounted) return;

            int total = data.length;
            int outside = 0;
            int autoref = 0;
            int eye = 0;
            int batna = 0;
            int pharmacy = 0;
            int eyeglasses = 0;
            int operation = 0;
            int ended = 0;

            for (final row in data) {
              final queueFor =
                  row['queuefor']?.toString().toLowerCase().trim() ?? '';

              if (queueFor == 'outside') {
                outside++;
              }
              if (queueFor.contains('autoref')) {
                autoref++;
              }
              if (queueFor.contains('eye')) {
                eye++;
              }
              if (queueFor.contains('batna')) {
                batna++;
              }
              if (queueFor.contains('pharmacy')) {
                pharmacy++;
              }
              if (queueFor.contains('eyeglasses')) {
                eyeglasses++;
              }
              if (queueFor.contains('operation')) {
                operation++;
              }
              if (queueFor == 'ended') {
                ended++;
              }
            }

            setState(() {
              _stats = {
                'total': total,
                'outside': outside,
                'autoref': autoref,
                'eye': eye,
                'batna': batna,
                'pharmacy': pharmacy,
                'eyeglasses': eyeglasses,
                'operation': operation,
                'ended': ended,
              };
              _isLoadingStats = false;
            });
          },
          onError: (e) {
            if (mounted) setState(() => _isLoadingStats = false);
          },
        );
  }

  // Parses takhasos column into a clean list of specialty choices
  List<String> _getConvoySpecialties() {
    final rawTakhasos = widget.convoy['takhasos']?.toString();
    if (rawTakhasos == null || rawTakhasos.trim().isEmpty) {
      return ['eye', 'general'];
    }

    final specialties = rawTakhasos
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();

    if (specialties.isEmpty) {
      return ['eye', 'general'];
    }

    return specialties;
  }

  // ---------------------------------------------------------------------------
  // Roles Management
  // ---------------------------------------------------------------------------
  Future<void> _fetchRoles() async {
    try {
      final response = await _supabase
          .from('roles')
          .select('*')
          .eq('convoyid', widget.convoy['id'])
          .order('id', ascending: true);

      if (mounted) {
        setState(() {
          _roles = List<Map<String, dynamic>>.from(response);
          _isLoadingRoles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to load roles');
        setState(() => _isLoadingRoles = false);
      }
    }
  }

  void _showAddOrEditRoleDialog({Map<String, dynamic>? roleData}) {
    final isEditing = roleData != null;
    final nameController = TextEditingController(text: roleData?['name'] ?? '');

    String? selectedRole = roleData?['role']?.toString().toLowerCase().trim();
    if (selectedRole != null && !_availableRoles.contains(selectedRole)) {
      selectedRole = null;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(isEditing ? 'Edit User Role' : 'Add User Role'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isEditing) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'User ID: #${roleData['id']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role Type',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select Role'),
                    items: _availableRoles.map((role) {
                      return DropdownMenuItem<String>(
                        value: role,
                        child: Text(role.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setModalState(() => selectedRole = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();

                    if (name.isEmpty) {
                      _showSnackBar('Full Name is required');
                      return;
                    }

                    if (selectedRole == null) {
                      _showSnackBar('Please select a valid role');
                      return;
                    }

                    Navigator.pop(context);

                    if (isEditing) {
                      await _updateRole(roleData['id'], name, selectedRole!);
                    } else {
                      await _addRole(name, selectedRole!);
                    }
                  },
                  child: Text(isEditing ? 'Save' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addRole(String name, String role) async {
    try {
      await _supabase.from('roles').insert({
        'name': name,
        'role': role,
        'convoyid': widget.convoy['id'],
      });

      if (mounted) {
        _showSnackBar('User role added!', isError: false);
        _fetchRoles();
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to add role');
    }
  }

  Future<void> _updateRole(dynamic id, String name, String role) async {
    try {
      await _supabase
          .from('roles')
          .update({'name': name, 'role': role})
          .eq('id', id);

      if (mounted) {
        _showSnackBar('User role updated!', isError: false);
        _fetchRoles();
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to update role');
    }
  }

  Future<void> _deleteRole(dynamic id) async {
    try {
      await _supabase.from('roles').delete().eq('id', id);

      if (mounted) {
        _showSnackBar('User role removed', isError: false);
        _fetchRoles();
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to delete role');
    }
  }

  // ---------------------------------------------------------------------------
  // Medicines Management
  // ---------------------------------------------------------------------------
  Future<void> _fetchMedicines() async {
    try {
      final response = await _supabase
          .from('medicine')
          .select('*')
          .eq('convoyid', widget.convoy['id'])
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _medicines = List<Map<String, dynamic>>.from(response);
          _isLoadingMedicines = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to load medicines');
        setState(() => _isLoadingMedicines = false);
      }
    }
  }

  void _showAddOrEditMedicineDialog({Map<String, dynamic>? medicine}) {
    final nameController = TextEditingController(text: medicine?['name'] ?? '');
    final isEditing = medicine != null;
    final availableSpecialties = _getConvoySpecialties();

    String? selectedType = medicine?['type']?.toString().toLowerCase().trim();
    if (selectedType != null && !availableSpecialties.contains(selectedType)) {
      selectedType = null;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(isEditing ? 'Edit Medicine' : 'Add New Medicine'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Medicine Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Specialty Category (Type)',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select Specialty Category'),
                    items: availableSpecialties.map((specialty) {
                      return DropdownMenuItem<String>(
                        value: specialty,
                        child: Text(specialty.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setModalState(() => selectedType = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();

                    if (name.isEmpty) {
                      _showSnackBar('Medicine name cannot be empty');
                      return;
                    }

                    if (selectedType == null) {
                      _showSnackBar('Please select a specialty category');
                      return;
                    }

                    Navigator.pop(context);

                    if (isEditing) {
                      await _updateMedicine(
                        medicine['id'],
                        name,
                        selectedType!,
                      );
                    } else {
                      await _addMedicine(name, selectedType!);
                    }
                  },
                  child: Text(isEditing ? 'Save' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addMedicine(String name, String type) async {
    try {
      await _supabase.from('medicine').insert({
        'name': name,
        'type': type,
        'convoyid': widget.convoy['id'],
      });

      if (mounted) {
        _showSnackBar('Medicine added!', isError: false);
        _fetchMedicines();
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to add medicine');
    }
  }

  Future<void> _updateMedicine(dynamic id, String name, String type) async {
    try {
      await _supabase
          .from('medicine')
          .update({'name': name, 'type': type})
          .eq('id', id);

      if (mounted) {
        _showSnackBar('Medicine updated!', isError: false);
        _fetchMedicines();
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to update medicine');
    }
  }

  Future<void> _deleteMedicine(dynamic id) async {
    try {
      await _supabase.from('medicine').delete().eq('id', id);

      if (mounted) {
        _showSnackBar('Medicine removed', isError: false);
        _fetchMedicines();
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to delete medicine');
    }
  }

  void _navigateToAllPatients() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ConvoyPatientsListScreen(convoyId: widget.convoy['id']),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Convoy Status Actions
  // ---------------------------------------------------------------------------
  Future<void> _toggleConvoyEnded() async {
    setState(() => _isUpdating = true);

    try {
      final newStatus = !_isEnded;
      await _supabase
          .from('convoys')
          .update({'ended': newStatus})
          .eq('id', widget.convoy['id']);

      if (mounted) {
        setState(() => _isEnded = newStatus);
        _showSnackBar(
          newStatus ? 'Convoy marked as ENDED' : 'Convoy marked as LIVE',
          isError: newStatus,
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to update status');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _toggleConvoyBreak() async {
    setState(() => _isUpdating = true);

    try {
      final newBreakStatus = !_isBreak;
      await _supabase
          .from('convoys')
          .update({'break': newBreakStatus})
          .eq('id', widget.convoy['id']);

      if (mounted) {
        setState(() => _isBreak = newBreakStatus);
        _showSnackBar(
          newBreakStatus ? 'Convoy set to ON BREAK' : 'Convoy break RESUMED',
          isError: newBreakStatus,
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to update break status');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showEditNameDialog() {
    final nameController = TextEditingController(text: _convoyName);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Convoy Name'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Convoy Name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isEmpty) {
                  _showSnackBar('Name cannot be empty');
                  return;
                }
                Navigator.pop(context);
                await _updateConvoyName(newName);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateConvoyName(String newName) async {
    setState(() => _isUpdating = true);

    try {
      await _supabase
          .from('convoys')
          .update({'name': newName})
          .eq('id', widget.convoy['id']);

      if (mounted) {
        setState(() => _convoyName = newName);
        _showSnackBar('Convoy name updated successfully!', isError: false);
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to update convoy name');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
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

  Widget _buildStatChip(String label, int value, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: text.withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_convoyName),
          backgroundColor: Colors.purple.shade800,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Convoy Name',
              onPressed: _showEditNameDialog,
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Banner Containers
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _isEnded
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isEnded
                                  ? Colors.red.shade200
                                  : Colors.green.shade200,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Convoy Status',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isEnded ? 'ENDED' : 'LIVE',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _isEnded
                                      ? Colors.red.shade800
                                      : Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _isBreak
                                ? Colors.amber.shade50
                                : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isBreak
                                  ? Colors.amber.shade300
                                  : Colors.blue.shade200,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Break Status',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isBreak ? 'ON BREAK' : 'ACTIVE',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _isBreak
                                      ? Colors.amber.shade900
                                      : Colors.blue.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Action Control Buttons
                  if (_isUpdating)
                    const Center(child: CircularProgressIndicator())
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _toggleConvoyBreak,
                            icon: Icon(
                              _isBreak ? Icons.play_arrow : Icons.pause,
                              size: 18,
                            ),
                            label: Text(
                              _isBreak ? 'Resume' : 'Take Break',
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isBreak
                                  ? Colors.amber.shade800
                                  : Colors.orange.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _toggleConvoyEnded,
                            icon: Icon(
                              _isEnded ? Icons.refresh : Icons.stop,
                              size: 18,
                            ),
                            label: Text(
                              _isEnded ? 'Make Live' : 'End Convoy',
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isEnded
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // Realtime Convoy Statistics Section
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.bar_chart, color: Colors.purple),
                                  SizedBox(width: 8),
                                  Text(
                                    'Live Statistics',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.sensors,
                                      size: 12,
                                      color: Colors.green,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'REALTIME',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 20),

                          if (_isLoadingStats)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else ...[
                            // Total Registered Banner
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.purple.shade200,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Registered Patients:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    '${_stats['total']}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Grid Matrix for Department Statuses
                            GridView.count(
                              crossAxisCount: 3,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1.8,
                              children: [
                                _buildStatChip(
                                  'Outside Waiting',
                                  _stats['outside']!,
                                  Colors.orange.shade50,
                                  Colors.orange.shade900,
                                ),
                                _buildStatChip(
                                  'In Autoref',
                                  _stats['autoref']!,
                                  Colors.blue.shade50,
                                  Colors.blue.shade900,
                                ),
                                _buildStatChip(
                                  'In Eye Queue',
                                  _stats['eye']!,
                                  Colors.teal.shade50,
                                  Colors.teal.shade900,
                                ),
                                _buildStatChip(
                                  'In Batna Queue',
                                  _stats['batna']!,
                                  Colors.indigo.shade50,
                                  Colors.indigo.shade900,
                                ),
                                _buildStatChip(
                                  'In Pharmacy',
                                  _stats['pharmacy']!,
                                  Colors.cyan.shade50,
                                  Colors.cyan.shade900,
                                ),
                                _buildStatChip(
                                  'In Glasses',
                                  _stats['eyeglasses']!,
                                  Colors.amber.shade50,
                                  Colors.amber.shade900,
                                ),
                                _buildStatChip(
                                  'In Operation',
                                  _stats['operation']!,
                                  Colors.red.shade50,
                                  Colors.red.shade900,
                                ),
                                _buildStatChip(
                                  'Completed (Ended)',
                                  _stats['ended']!,
                                  Colors.green.shade50,
                                  Colors.green.shade900,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Patient Search & Quick Lookup (Imported from lookup.dart)
                  PatientLookupWidget(
                    convoyId: widget.convoy['id'],
                    onShowAllPatients: _navigateToAllPatients,
                  ),
                  const SizedBox(height: 20),

                  // Medicines Dropdown Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ExpansionTile(
                      shape: const RoundedRectangleBorder(
                        side: BorderSide.none,
                      ),
                      title: Text(
                        'Medicines Catalog (${_medicines.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle,
                              color: Colors.purple,
                            ),
                            onPressed: () => _showAddOrEditMedicineDialog(),
                            tooltip: 'Add Medicine',
                          ),
                          const Icon(Icons.expand_more),
                        ],
                      ),
                      children: [
                        if (_isLoadingMedicines)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_medicines.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                              child: Text(
                                'No medicines configured.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _medicines.length,
                            itemBuilder: (context, index) {
                              final med = _medicines[index];
                              return ListTile(
                                title: Text(
                                  med['name']?.toString() ?? 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'Type: ${med['type']?.toString() ?? "general"}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.blue,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _showAddOrEditMedicineDialog(
                                            medicine: med,
                                          ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _deleteMedicine(med['id']),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Roles Dropdown Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ExpansionTile(
                      shape: const RoundedRectangleBorder(
                        side: BorderSide.none,
                      ),
                      title: Text(
                        'Convoy Roles (${_roles.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.person_add,
                              color: Colors.purple,
                            ),
                            onPressed: () => _showAddOrEditRoleDialog(),
                            tooltip: 'Add Role',
                          ),
                          const Icon(Icons.expand_more),
                        ],
                      ),
                      children: [
                        if (_isLoadingRoles)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_roles.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                              child: Text(
                                'No user roles assigned to this convoy.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _roles.length,
                            itemBuilder: (context, index) {
                              final roleData = _roles[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.purple.shade50,
                                  child: Text(
                                    '#${roleData['id']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple.shade800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  roleData['name']?.toString() ?? 'Unnamed',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'Role: ${roleData['role']?.toString() ?? "N/A"}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.blue,
                                        size: 20,
                                      ),
                                      onPressed: () => _showAddOrEditRoleDialog(
                                        roleData: roleData,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _deleteRole(roleData['id']),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Convoy Patients List Sub-Screen
// ---------------------------------------------------------------------------
class ConvoyPatientsListScreen extends StatefulWidget {
  final dynamic convoyId;

  const ConvoyPatientsListScreen({super.key, required this.convoyId});

  @override
  State<ConvoyPatientsListScreen> createState() =>
      _ConvoyPatientsListScreenState();
}

class _ConvoyPatientsListScreenState extends State<ConvoyPatientsListScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _patients = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPatients();
  }

  Future<void> _fetchPatients() async {
    try {
      final response = await _supabase
          .from('registrations')
          .select('*')
          .eq('convoyid', widget.convoyId)
          .order('id', ascending: false);

      if (mounted) {
        setState(() {
          _patients = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convoy Registered Patients'),
        backgroundColor: Colors.purple.shade800,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _patients.isEmpty
                    ? const Center(
                        child: Text(
                          'No registered patients found for this convoy.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _patients.length,
                        itemBuilder: (context, index) {
                          final patient = _patients[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.purple.shade100,
                                child: Text(
                                  '#${patient['id']}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple.shade900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              title: Text(
                                patient['fullname']?.toString() ?? 'N/A',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'Queue: ${patient['queuefor']} | National ID: ${patient['id_number']}',
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
    );
  }
}
