import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'insideconvoy.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _convoys = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchConvoys();
  }

  Future<void> _fetchConvoys() async {
    try {
      final response = await _supabase
          .from('convoys')
          .select('*')
          .order('id', ascending: false);

      if (mounted) {
        setState(() {
          _convoys = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to fetch convoys: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  void _showCreateConvoyDialog() {
    final nameController = TextEditingController();
    final takhasosController = TextEditingController();
    final autorefController = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create New Convoy'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Convoy Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: takhasosController,
                  decoration: const InputDecoration(
                    labelText: 'Specialties (comma-separated)',
                    hintText: 'e.g. Eye, Dental, Internal',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: autorefController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Autoref Devices Count',
                    border: OutlineInputBorder(),
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
              onPressed: () async {
                final name = nameController.text.trim();
                final takhasos = takhasosController.text.trim();
                final autorefNum =
                    int.tryParse(autorefController.text.trim()) ?? 0;

                if (name.isEmpty) {
                  _showSnackBar('Please enter a convoy name');
                  return;
                }

                Navigator.pop(context);
                await _createConvoy(name, takhasos, autorefNum);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createConvoy(
    String name,
    String takhasos,
    int autorefNum,
  ) async {
    setState(() => _isLoading = true);
    try {
      await _supabase.from('convoys').insert({
        'name': name,
        'takhasos': takhasos,
        'autorefnumber': autorefNum,
        'ended': false,
      });

      if (mounted) {
        _showSnackBar('Convoy created successfully!', isError: false);
        _fetchConvoys();
      }
    } on PostgrestException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error) {
      if (mounted) _showSnackBar('Failed to create convoy');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.purple.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchConvoys),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _convoys.isEmpty
                    ? const Center(
                        child: Text(
                          'No convoys available. Click + to add one.',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _convoys.length,
                        itemBuilder: (context, index) {
                          final convoy = _convoys[index];
                          final bool isEnded = convoy['ended'] == true;

                          return Card(
                            elevation: 3,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isEnded
                                    ? Colors.grey.shade400
                                    : Colors.green.shade600,
                                width: 1.5,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              title: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      convoy['name'] ?? 'Unnamed Convoy',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isEnded
                                          ? Colors.red.shade50
                                          : Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isEnded
                                            ? Colors.red.shade200
                                            : Colors.green.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isEnded
                                              ? Icons.circle
                                              : Icons.sensors,
                                          size: 14,
                                          color: isEnded
                                              ? Colors.red.shade700
                                              : Colors.green.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isEnded ? 'ENDED' : 'LIVE',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isEnded
                                                ? Colors.red.shade700
                                                : Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  'Specialties: ${convoy['takhasos'] ?? "None"}\nAutoref Devices: ${convoy['autorefnumber'] ?? 0}',
                                  style: const TextStyle(height: 1.4),
                                ),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        InsideConvoyPage(convoy: convoy),
                                  ),
                                );
                                if (result == true) {
                                  _fetchConvoys();
                                }
                              },
                            ),
                          );
                        },
                      ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.purple.shade800,
        foregroundColor: Colors.white,
        onPressed: _showCreateConvoyDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
