import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'leader_detail_screen.dart';
import 'comparison_screen.dart';

class SearchScreen extends StatefulWidget {
  final String serverUrl;

  const SearchScreen({super.key, required this.serverUrl});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _results = [];
  bool _loading = false;
  String _error = '';
  
  // સરખામણી માટે પસંદ કરેલા ઉમેદવારો
  final Set<int> _selectedForCompare = {};
  final Map<int, Map<String, dynamic>> _selectedDetails = {};

  String get _apiBaseUrl {
    var url = widget.serverUrl.replaceAll(RegExp(r'/api/scan-poster/?$'), '');
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _error = '';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final uri = Uri.parse('$_apiBaseUrl/api/search?q=${Uri.encodeComponent(q)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _results = data['results'] ?? [];
          if (_results.isEmpty) {
            _error = 'કોઈ પરિણામ મળ્યા નથી. અન્ય નામ, ગામ કે જિલ્લો લખીને પ્રયાસ કરો.';
          }
        });
      } else {
        setState(() => _error = 'સર્વર ભૂલ (કોડ: ${res.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'કનેક્શન નિષ્ફળ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCandidateDetail(int politicianId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final uri = Uri.parse('$_apiBaseUrl/api/politician/$politicianId');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final reportCard = data['data'] as Map<String, dynamic>;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LeaderDetailScreen(reportCard: reportCard),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('વિગતો લોડ કરવામાં નિષ્ફળ')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('એરર: $e')),
      );
    }
  }

  Future<void> _toggleCompareSelection(Map<String, dynamic> candidate) async {
    final id = candidate['id'] as int;

    if (_selectedForCompare.contains(id)) {
      setState(() {
        _selectedForCompare.remove(id);
        _selectedDetails.remove(id);
      });
      return;
    }

    if (_selectedForCompare.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('તમે એકસાથે વધુમાં વધુ ૨ ઉમેદવારો સરખાવી શકો છો')),
      );
      return;
    }

    // Fetch full report card for comparison
    try {
      final uri = Uri.parse('$_apiBaseUrl/api/politician/$id');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final report = data['data'] as Map<String, dynamic>;
        setState(() {
          _selectedForCompare.add(id);
          _selectedDetails[id] = report;
        });
      }
    } catch (_) {}
  }

  void _startComparison() {
    if (_selectedForCompare.length != 2) return;
    final keys = _selectedForCompare.toList();
    final candA = _selectedDetails[keys[0]]!;
    final candB = _selectedDetails[keys[1]]!;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComparisonScreen(candA: candA, candB: candB),
      ),
    );
  }

  String _formatInr(dynamic val) {
    double amt = double.tryParse(val?.toString() ?? '0') ?? 0.0;
    if (amt >= 10000000) return '₹ ${(amt / 10000000).toStringAsFixed(1)} કરોડ';
    if (amt >= 100000) return '₹ ${(amt / 100000).toStringAsFixed(1)} લાખ';
    return '₹ ${amt.toStringAsFixed(0)}';
  }

  Color _getPartyColor(String party) {
    final p = party.toUpperCase();
    if (p.contains('BJP') || p.contains('ભાજપ')) return Colors.orange.shade800;
    if (p.contains('INC') || p.contains('કોંગ્રેસ')) return Colors.blue.shade700;
    if (p.contains('AAP') || p.contains('આપ')) return Colors.teal.shade700;
    if (p.contains('AIMIM')) return Colors.green.shade800;
    return Colors.grey.shade700;
  }

  Widget _buildSuggestionChip(String label, String query) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: Colors.indigo.shade50,
      side: BorderSide(color: Colors.indigo.shade200),
      onPressed: () {
        _searchController.text = query;
        _performSearch(query);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('નેતા / કોર્પોરેટર સર્ચ'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // સર્ચ બાર હેડર
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.indigo.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _performSearch,
                  decoration: InputDecoration(
                    hintText: 'નામ, ગામ/શહેર, વોર્ડ, જિલ્લો શોધો...',
                    prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _performSearch('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // ઝડપી ફિલ્ટર્સ
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildSuggestionChip('ગાંધીનગર (GMC)', 'ગાંધીનગર'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('અમદાવાદ (AMC)', 'અમદાવાદ'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('સુરત (SMC)', 'સુરત'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('રાજકોટ (RMC)', 'રાજકોટ'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('વડોદરા (VMC)', 'વડોદરા'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('ગોતા (વોર્ડ ૧)', 'ગોતા'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('ભાજપ (BJP)', 'BJP'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('કોંગ્રેસ (INC)', 'INC'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('આપ (AAP)', 'AAP'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // પરિણામોની યાદી
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('ડેટાબેઝમાંથી શોધી રહ્યા છીએ...'),
                      ],
                    ),
                  )
                : _error.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54, fontSize: 15),
                          ),
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_search, size: 70, color: Colors.indigo.shade200),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'કોઈપણ નેતા કે કોર્પોરેટરને શોધો',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'ઉદાહરણ:\n• નામ: "શિલ્પાબેન", "અલ્પેશ", "નરેન્દ્ર મોદી"\n• વિસ્તાર: "ગાંધીનગર વોર્ડ ૧", "ગોતા", "સુરત"\n• પક્ષ: "BJP", "INC", "AAP"',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.black54, height: 1.5),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (ctx, index) {
                              final item = _results[index] as Map<String, dynamic>;
                              final id = item['id'] as int;
                              final name = item['full_name']?.toString() ?? '-';
                              final party = item['party_name']?.toString() ?? '-';
                              final constituency = item['constituency']?.toString() ?? '-';
                              final edu = item['education']?.toString() ?? '-';
                              final assets = item['total_assets'];
                              final isSelected = _selectedForCompare.contains(id);

                              return Card(
                                elevation: 1.5,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: isSelected
                                      ? const BorderSide(color: Colors.indigo, width: 2)
                                      : BorderSide.none,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _openCandidateDetail(id),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // અવતાર
                                        CircleAvatar(
                                          radius: 24,
                                          backgroundColor: _getPartyColor(party).withAlpha(38),
                                          child: Text(
                                            name.isNotEmpty ? name[0] : '?',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: _getPartyColor(party),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // મુખ્ય વિગત
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      name,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: _getPartyColor(party),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Text(
                                                      party,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                constituency,
                                                style: TextStyle(
                                                  color: Colors.indigo.shade900,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Text(
                                                    'શિક્ષણ: $edu',
                                                    style: const TextStyle(
                                                        fontSize: 12, color: Colors.black54),
                                                  ),
                                                  if (assets != null) ...[
                                                    const Text(' • ',
                                                        style: TextStyle(color: Colors.black38)),
                                                    Text(
                                                      'મિલકત: ${_formatInr(assets)}',
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.green,
                                                          fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // સરખામણી ચેકબોક્સ
                                        IconButton(
                                          icon: Icon(
                                            isSelected
                                                ? Icons.check_circle
                                                : Icons.compare_arrows,
                                            color: isSelected ? Colors.indigo : Colors.black45,
                                          ),
                                          tooltip: 'સરખામણી માટે પસંદ કરો',
                                          onPressed: () => _toggleCompareSelection(item),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),

      // સરખામણી ફ્લોટિંગ બટન
      floatingActionButton: _selectedForCompare.length == 2
          ? FloatingActionButton.extended(
              onPressed: _startComparison,
              icon: const Icon(Icons.compare),
              label: const Text('૨ ઉમેદવારો સરખાવો'),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }
}
