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
  
  // એડવાન્સ ફિલ્ટર્સ માટે controllers
  final TextEditingController _filterNameCtrl = TextEditingController();
  final TextEditingController _filterDistrictCtrl = TextEditingController();
  final TextEditingController _filterTalukaCtrl = TextEditingController();
  final TextEditingController _filterWardCtrl = TextEditingController();
  String _selectedParty = 'તમામ';

  bool _showAdvancedFilters = false;
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

  Future<void> _performSearch({String? customQuery}) async {
    final q = (customQuery ?? _searchController.text).trim();
    final name = _filterNameCtrl.text.trim();
    final dist = _filterDistrictCtrl.text.trim();
    final tal = _filterTalukaCtrl.text.trim();
    final ward = _filterWardCtrl.text.trim();
    final party = _selectedParty != 'તમામ' ? _selectedParty : '';

    if (q.isEmpty && name.isEmpty && dist.isEmpty && tal.isEmpty && ward.isEmpty && party.isEmpty) {
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
      final queryParams = <String, String>{};
      if (q.isNotEmpty) queryParams['q'] = q;
      if (name.isNotEmpty) queryParams['name'] = name;
      if (dist.isNotEmpty) queryParams['district'] = dist;
      if (tal.isNotEmpty) queryParams['taluka'] = tal;
      if (ward.isNotEmpty) queryParams['ward'] = ward;
      if (party.isNotEmpty) queryParams['party'] = party;

      final uri = Uri.parse('$_apiBaseUrl/api/search').replace(queryParameters: queryParams);
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _results = data['results'] ?? [];
          if (_results.isEmpty) {
            _error = 'કોઈ પરિણામ મળ્યા નથી. કૃપા કરીને નામ, ગામ, વોર્ડ કે જિલ્લો તપાસીને ફરી પ્રયાસ કરો.';
          }
        });
      } else {
        setState(() => _error = 'સર્વર ભૂલ (કોડ: ${res.statusCode}). કૃપા કરીને થોડીવાર પછી પ્રયાસ કરો.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'કનેક્શન નિષ્ફળ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetFilters() {
    _searchController.clear();
    _filterNameCtrl.clear();
    _filterDistrictCtrl.clear();
    _filterTalukaCtrl.clear();
    _filterWardCtrl.clear();
    setState(() {
      _selectedParty = 'તમામ';
      _results = [];
      _error = '';
    });
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
        _performSearch(customQuery: query);
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
        actions: [
          IconButton(
            icon: Icon(_showAdvancedFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: 'વિગતવાર ફિલ્ટર (જિલ્લો, ગામ, વોર્ડ, નામ)',
            onPressed: () {
              setState(() => _showAdvancedFilters = !_showAdvancedFilters);
            },
          ),
        ],
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (val) => _performSearch(),
                        decoration: InputDecoration(
                          hintText: 'નામ, ગામ/શહેર, વોર્ડ, જિલ્લો લખો...',
                          prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    _performSearch();
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
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onPressed: () => _performSearch(),
                      child: const Text('શોધો'),
                    ),
                  ],
                ),

                // વિગતવાર ફિલ્ટર પેનલ (Expandable Multi-Field Form)
                if (_showAdvancedFilters) ...[
                  const SizedBox(height: 12),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'વિગતવાર શોધ ફિલ્ટર્સ:',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo),
                              ),
                              TextButton(
                                onPressed: _resetFilters,
                                child: const Text('રીસેટ કરો', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _filterDistrictCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'જિલ્લો / મનપા',
                                    hintText: 'દા.ત. જૂનાગઢ, અમદાવાદ',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _filterTalukaCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'તાલુકો / ગામ',
                                    hintText: 'દા.ત. જૂનાગઢ, ગોતા',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: TextField(
                                  controller: _filterWardCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'વોર્ડ નં.',
                                    hintText: 'દા.ત. 15',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _filterNameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'નેતાનું નામ',
                                    hintText: 'દા.ત. રણજીત લાખાભાઈ પરમાર',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Text('પક્ષ: ', style: TextStyle(fontWeight: FontWeight.w500)),
                              const SizedBox(width: 8),
                              DropdownButton<String>(
                                value: _selectedParty,
                                isDense: true,
                                items: ['તમામ', 'BJP', 'INC', 'AAP', 'AIMIM', 'IND'].map((p) {
                                  return DropdownMenuItem(value: p, child: Text(p));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedParty = val);
                                },
                              ),
                              const Spacer(),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _performSearch(),
                                icon: const Icon(Icons.search, size: 18),
                                label: const Text('ફિલ્ટર લાગુ કરો'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                // ઝડપી ફિલ્ટર્સ
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildSuggestionChip('📍 જૂનાગઢ (વોર્ડ ૧૫ - રણજીત પરમાર)', 'જૂનાગઢ વોર્ડ 15 રણજીત'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('📍 ગાંધીનગર (વોર્ડ ૧ - શિલ્પાબેન)', 'ગાંધીનગર 1 શિલ્પાબેન'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('📍 અમદાવાદ (ગોતા - વોર્ડ ૧)', 'ગોતા વોર્ડ 1'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('સુરત (SMC)', 'સુરત'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('રાજકોટ (RMC)', 'રાજકોટ'),
                      const SizedBox(width: 6),
                      _buildSuggestionChip('વડોદરા (VMC)', 'વડોદરા'),
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
                                    'ઉદાહરણ:\n• એક જ લાઈનમાં: "જુનાગઢ વોર્ડ 15 રણજીત લાખાભાઈ પરમાર"\n• અથવા ઉપર આપેલા "ફિલ્ટર" આઇકોન પર ક્લિક કરીને જિલ્લો, ગામ, વોર્ડ અને નામ અલગથી ભરીને શોધો.',
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
                              final caseStatus = item['case_status']?.toString() ?? 'Clean Record';
                              final isSelected = _selectedForCompare.contains(id);

                              return Card(
                                elevation: 2,
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
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                children: [
                                                  Text(
                                                    'શિક્ષણ: $edu',
                                                    style: const TextStyle(
                                                        fontSize: 12, color: Colors.black54),
                                                  ),
                                                  if (assets != null)
                                                    Text(
                                                      'મિલકત: ${_formatInr(assets)}',
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.green,
                                                          fontWeight: FontWeight.bold),
                                                    ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 6, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: caseStatus.toLowerCase().contains('clean')
                                                          ? Colors.green.shade50
                                                          : Colors.red.shade50,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      caseStatus,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: caseStatus.toLowerCase().contains('clean')
                                                            ? Colors.green.shade700
                                                            : Colors.red.shade700,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
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
