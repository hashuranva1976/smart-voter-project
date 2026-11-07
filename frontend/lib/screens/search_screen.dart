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

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // અલગ ખાનાઓ માટે Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _villageController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _wardController = TextEditingController();
  String _selectedParty = 'તમામ';

  // સીધા સર્ચ માટે Controller
  final TextEditingController _singleSearchController = TextEditingController();

  List<dynamic> _results = [];
  bool _loading = false;
  String _error = '';
  bool _hasSearched = false;

  // સરખામણી માટે પસંદ કરેલા ઉમેદવારો
  final Set<int> _selectedForCompare = {};
  final Map<int, Map<String, dynamic>> _selectedDetails = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _districtController.dispose();
    _villageController.dispose();
    _cityController.dispose();
    _wardController.dispose();
    _singleSearchController.dispose();
    super.dispose();
  }

  String get _apiBaseUrl {
    var url = widget.serverUrl.replaceAll(RegExp(r'/api/scan-poster/?$'), '');
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> _searchByFields() async {
    final name = _nameController.text.trim();
    final district = _districtController.text.trim();
    final village = _villageController.text.trim();
    final city = _cityController.text.trim();
    final ward = _wardController.text.trim();
    final party = _selectedParty != 'તમામ' ? _selectedParty : '';

    if (name.isEmpty && district.isEmpty && village.isEmpty && city.isEmpty && ward.isEmpty && party.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('કૃપા કરીને શોધવા માટે ઓછામાં ઓછું એક ખાનું ભરો')),
      );
      return;
    }

    final queryParams = <String, String>{};
    if (name.isNotEmpty) queryParams['name'] = name;
    if (district.isNotEmpty) queryParams['district'] = district;
    if (village.isNotEmpty) queryParams['village'] = village;
    if (city.isNotEmpty) queryParams['city'] = city;
    if (ward.isNotEmpty) queryParams['ward'] = ward;
    if (party.isNotEmpty) queryParams['party'] = party;

    await _executeApiSearch(queryParams);
  }

  Future<void> _searchBySingleBar([String? customQ]) async {
    final q = (customQ ?? _singleSearchController.text).trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('કૃપા કરીને શોધવા માટે કંઈક લખો')),
      );
      return;
    }
    await _executeApiSearch({'q': q});
  }

  Future<void> _executeApiSearch(Map<String, String> queryParams) async {
    setState(() {
      _loading = true;
      _error = '';
      _hasSearched = true;
      _results = [];
    });

    try {
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
        setState(() => _error = 'સર્વર ભૂલ (કોડ: ${res.statusCode}). કૃપા કરીને ફરી પ્રયાસ કરો.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'કનેક્શન નિષ્ફળ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearAllFields() {
    _nameController.clear();
    _districtController.clear();
    _villageController.clear();
    _cityController.clear();
    _wardController.clear();
    _singleSearchController.clear();
    setState(() {
      _selectedParty = 'તમામ';
      _results = [];
      _error = '';
      _hasSearched = false;
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
      Navigator.pop(context);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('નેતા / કોર્પોરેટર સર્ચ'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'વિગતવાર ખાના ભરીને'),
            Tab(icon: Icon(Icons.search), text: 'સીધું લખીને'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ઉપરનું ઇનપુટ કન્ટેનર (Tabs)
          Container(
            color: Colors.indigo.shade50,
            constraints: const BoxConstraints(maxHeight: 330),
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: અલગ-અલગ ખાના (Dedicated Form Fields)
                SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    children: [
                      // ૧. નેતાનું નામ
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: '👤 નેતા / ઉમેદવારનું નામ',
                          hintText: 'દા.ત. રણજીત લાખાભાઈ પરમાર',
                          prefixIcon: Icon(Icons.person, color: Colors.indigo),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ૨. જિલ્લો અને તાલુકો/ગામ
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _districtController,
                              decoration: const InputDecoration(
                                labelText: '🏛️ જિલ્લો',
                                hintText: 'દા.ત. જૂનાગઢ',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _villageController,
                              decoration: const InputDecoration(
                                labelText: '📍 ગામ / તાલુકો',
                                hintText: 'દા.ત. જૂનાગઢ',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ૩. શહેર અને વોર્ડ નંબર
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _cityController,
                              decoration: const InputDecoration(
                                labelText: '🏙️ શહેર / મનપા',
                                hintText: 'દા.ત. જૂનાગઢ મનપા',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _wardController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '🔢 વોર્ડ નં.',
                                hintText: 'દા.ત. 15',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ૪. પક્ષ પસંદગી અને બટનો
                      Row(
                        children: [
                          const Text('🚩 પક્ષ: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedParty,
                                isDense: true,
                                items: ['તમામ', 'કોંગ્રેસ (INC)', 'BJP', 'AAP', 'અપક્ષ (IND)'].map((p) {
                                  return DropdownMenuItem(value: p, child: Text(p));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedParty = val);
                                },
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _clearAllFields,
                            child: const Text('સાફ કરો', style: TextStyle(color: Colors.red)),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            onPressed: _searchByFields,
                            icon: const Icon(Icons.search, size: 18),
                            label: const Text('શોધો', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // TAB 2: સીધું લખીને સર્ચ (Single Universal Search Bar)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _singleSearchController,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (val) => _searchBySingleBar(),
                              decoration: InputDecoration(
                                hintText: 'દા.ત. જૂનાગઢ વોર્ડ 15 રણજીત કોંગ્રેસ...',
                                prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
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
                            onPressed: () => _searchBySingleBar(),
                            child: const Text('શોધો'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ActionChip(
                            label: const Text('📍 જૂનાગઢ વોર્ડ ૧૫ (રણજીત પરમાર)', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              _singleSearchController.text = 'જૂનાગઢ વોર્ડ 15 રણજીત કોંગ્રેસ';
                              _searchBySingleBar('જૂનાગઢ વોર્ડ 15 રણજીત કોંગ્રેસ');
                            },
                          ),
                          ActionChip(
                            label: const Text('📍 ગાંધીનગર વોર્ડ ૧ (શિલ્પાબેન)', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              _singleSearchController.text = 'ગાંધીનગર 1 શિલ્પાબેન';
                              _searchBySingleBar('ગાંધીનગર 1 શિલ્પાબેન');
                            },
                          ),
                          ActionChip(
                            label: const Text('📍 ગોતા વોર્ડ ૧ (અમદાવાદ)', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              _singleSearchController.text = 'ગોતા વોર્ડ 1';
                              _searchBySingleBar('ગોતા વોર્ડ 1');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1),

          // નીચે પરિણામોની યાદી
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
                    : !_hasSearched
                        ? Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.badge_outlined, size: 64, color: Colors.indigo.shade200),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'ઉપરના ખાનામાં વિગત ભરીને શોધો',
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'તમે નામ, જિલ્લો, ગામ, શહેર કે વોર્ડ નંબર\nકોઈપણ એક કે વધુ ખાના ભરીને "શોધો" દબાવો.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.black54, height: 1.4),
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
                                              const SizedBox(height: 6),
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

                                        // સરખામણી આઇકોન
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
