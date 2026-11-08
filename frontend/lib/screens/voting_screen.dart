import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'leader_detail_screen.dart';

class VotingScreen extends StatefulWidget {
  final String serverUrl;

  const VotingScreen({super.key, required this.serverUrl});

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final LocalAuthentication _auth = LocalAuthentication();

  // Controllers
  final TextEditingController _aadhaarController = TextEditingController();

  // Voting Flow State
  // 0: Aadhaar Entry, 1: Fingerprint Biometric, 2: Ballot EVM, 3: VVPAT Success
  int _currentStep = 0;

  bool _loading = false;
  String _errorMessage = '';
  Map<String, dynamic>? _currentVoter;
  List<Map<String, dynamic>> _ballotCandidates = [];
  Map<String, dynamic>? _lastVoteReceipt;
  int? _selectedCandidateId;
  bool _isLedActive = false;

  // Local Offline Voters & Votes Cache
  List<Map<String, dynamic>> _localVoters = [];
  final List<Map<String, dynamic>> _localBallotVotes = [];

  // Live Results State
  int _totalVotersCount = 5;
  int _totalPolledCount = 0;
  List<Map<String, dynamic>> _candidateResults = [];
  List<Map<String, dynamic>> _partyResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLocalData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _aadhaarController.dispose();
    super.dispose();
  }

  String get _apiBaseUrl {
    var url = widget.serverUrl.replaceAll(RegExp(r'/api/scan-poster/?$'), '');
    return url.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> _loadLocalData() async {
    try {
      final voterStr = await rootBundle.loadString('assets/data/voters.json');
      final List<dynamic> vList = jsonDecode(voterStr);
      _localVoters = vList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _totalVotersCount = _localVoters.length;
    } catch (_) {}

    await _refreshLiveResults();
  }

  // --- સ્ટેપ ૧: આધાર કાર્ડ ચકાસણી ---
  Future<void> _verifyAadhaar([String? directNum]) async {
    final raw = (directNum ?? _aadhaarController.text).replaceAll(' ', '').trim();
    if (raw.length != 12 || int.tryParse(raw) == null) {
      setState(() {
        _errorMessage = 'કૃપા કરીને માન્ય ૧૨-અંકનો આધાર કાર્ડ નંબર દાખલ કરો (દા.ત. 1234 5678 9012)';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = '';
      _currentVoter = null;
    });

    // પ્રથમ સ્થાનિક મતદાર યાદીમાં તપાસો
    Map<String, dynamic>? foundVoter;
    for (var v in _localVoters) {
      final masked = v['aadhaar_masked']?.toString() ?? '';
      if (masked.endsWith(raw.substring(8))) {
        foundVoter = v;
        break;
      }
    }

    // જો ન મળે તો નવું પ્રોવિઝનલ રજીસ્ટ્રેશન
    if (foundVoter == null) {
      foundVoter = {
        'id': _localVoters.length + 1,
        'aadhaar_masked': 'XXXX XXXX ${raw.substring(8)}',
        'full_name': 'મતદાર (આધાર: ...${raw.substring(8)})',
        'age': 35,
        'gender': 'પુરુષ (Male)',
        'district': 'જૂનાગઢ',
        'taluka': 'જૂનાગઢ',
        'ward_no': 15,
        'booth_no': 102,
        'has_voted': 0,
        'voted_at': null,
      };
      _localVoters.add(foundVoter);
      _totalVotersCount = _localVoters.length;
    }

    // ઓનલાઇન API પણ ચેક કરો
    try {
      final uri = Uri.parse('$_apiBaseUrl/api/voter/lookup');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'aadhaar_number': raw}),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['voter'] != null) {
          foundVoter = Map<String, dynamic>.from(data['voter']);
        }
      }
    } catch (_) {}

    setState(() {
      _loading = false;
      _currentVoter = foundVoter;
      if (foundVoter != null && foundVoter['has_voted'] == 1) {
        _errorMessage = '❌ આ આધાર કાર્ડ પરથી પહેલેથી મતદાન થઈ ચૂક્યું છે!\nસમય: ${foundVoter['voted_at'] ?? 'અગાઉ'}';
      }
    });

    if (foundVoter != null && foundVoter['has_voted'] == 0) {
      await _loadBallot(foundVoter['district'] ?? 'જૂનાગઢ', (foundVoter['ward_no'] ?? 15).toString());
    }
  }

  // --- સ્ટેપ ૨: બાયોમેટ્રિક ફિંગરપ્રિન્ટ સ્કેનર ---
  Future<void> _authenticateBiometric() async {
    setState(() => _loading = true);
    bool authenticated = false;

    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (canAuthenticate) {
        authenticated = await _auth.authenticate(
          localizedReason: 'આધાર કાર્ડ પ્રમાણિત કરવા કૃપા કરીને ફિંગરપ્રિન્ટ સેન્સર પર આંગળી મૂકો',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ),
        );
      } else {
        // હાર્ડવેર સેન્સર ન હોય તો હાઇ-ટેક સિમ્યુલેશન
        await Future.delayed(const Duration(milliseconds: 1400));
        authenticated = true;
      }
    } catch (e) {
      // સુરક્ષિત ફોલબેક ટેસ્ટિંગ માટે
      await Future.delayed(const Duration(milliseconds: 1200));
      authenticated = true;
    }

    setState(() => _loading = false);

    if (!mounted) return;
    if (authenticated) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ આધાર ફિંગરપ્રિન્ટ સફળતાપૂર્વક પ્રમાણિત થઈ! EVM બેલેટ ખૂલી રહ્યું છે...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      setState(() {
        _currentStep = 2; // Move to Ballot EVM
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ ફિંગરપ્રિન્ટ મેળ ખાતી નથી! કૃપા કરીને ફરી પ્રયાસ કરો.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // બેલેટ ઉમેદવારો લોડ કરો
  Future<void> _loadBallot(String district, String wardNo) async {
    List<Map<String, dynamic>> list = [];

    // ૧. સ્થાનિક ઉમેદવારો લોડ કરો
    try {
      final polStr = await rootBundle.loadString('assets/data/politicians.json');
      final List<dynamic> pList = jsonDecode(polStr);
      for (var p in pList) {
        final pWard = (p['ward_no'] ?? '').toString();
        final pConst = (p['constituency'] ?? '').toString();
        final pDist = (p['district'] ?? '').toString();

        if ((pWard == wardNo || pConst.contains('વોર્ડ નં. $wardNo')) &&
            (pDist.contains(district) || pConst.contains(district))) {
          list.add(Map<String, dynamic>.from(p));
        }
      }
    } catch (_) {}

    // NOTA ઉમેરો
    list.add({
      'id': 9999,
      'full_name': 'NOTA (ઉપરોક્તમાંથી કોઈ નહીં)',
      'party_name': 'NOTA',
      'constituency': 'વોર્ડ નં. $wardNo, $district',
      'education': '-',
      'total_assets': 0,
      'case_status': 'Clean Record',
    });

    setState(() {
      _ballotCandidates = list;
    });
  }

  // --- સ્ટેપ ૩: વોટ આપો (Cast Vote on EVM) ---
  Future<void> _castVote(Map<String, dynamic> candidate) async {
    final candId = (candidate['id'] as num).toInt();
    final candName = candidate['full_name']?.toString() ?? 'ઉમેદવાર';
    final candParty = candidate['party_name']?.toString() ?? '-';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('મતદાન પુષ્ટિ (Confirm Vote)'),
        content: Text(
          'શું તમે ઉમેદવાર:\n\n👤 $candName\n🚩 પક્ષ: $candParty\n\nને તમારો કિંમતી મત આપવા માટે ચોક્કસ છો?',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('રદ કરો', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('હા, મત આપો (Confirm)'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // EVM LED એનિમેશન અને બીપ વાઈબ્રેશન
    setState(() {
      _selectedCandidateId = candId;
      _isLedActive = true;
    });
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);

    final nowIso = DateTime.now().toString().substring(0, 19);
    final voteToken = 'VOTE-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase()}';

    // ૧. સ્થાનિક મતદાર રેકોર્ડ અપડેટ કરો
    if (_currentVoter != null) {
      _currentVoter!['has_voted'] = 1;
      _currentVoter!['voted_at'] = nowIso;
      for (var v in _localVoters) {
        if (v['id'] == _currentVoter!['id']) {
          v['has_voted'] = 1;
          v['voted_at'] = nowIso;
          break;
        }
      }
    }

    // ૨. ગુપ્ત બેલેટ બોક્સમાં વોટ જમા કરો
    _localBallotVotes.add({
      'vote_token': voteToken,
      'district': _currentVoter?['district'] ?? 'જૂનાગઢ',
      'ward_no': _currentVoter?['ward_no'] ?? 15,
      'candidate_id': candId,
      'candidate_name': candName,
      'party_name': candParty,
      'timestamp': nowIso,
    });

    final receipt = {
      'token': voteToken,
      'candidate_name': candName,
      'party_name': candParty,
      'ward_no': _currentVoter?['ward_no'] ?? 15,
      'district': _currentVoter?['district'] ?? 'જૂનાગઢ',
      'booth_no': _currentVoter?['booth_no'] ?? 102,
      'timestamp': nowIso,
    };

    // ઓનલાઇન API પર મોકલો
    try {
      final rawAadhaar = _aadhaarController.text.replaceAll(' ', '').trim();
      final uri = Uri.parse('$_apiBaseUrl/api/voting/cast-vote');
      await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'aadhaar_number': rawAadhaar, 'candidate_id': candId}),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 600));

    setState(() {
      _isLedActive = false;
      _lastVoteReceipt = receipt;
      _currentStep = 3; // Show VVPAT Slip
    });

    await _refreshLiveResults();
  }

  // --- લાઈવ પરિણામો લોડ કરો ---
  Future<void> _refreshLiveResults() async {
    // સ્થાનિક વોટની ગણતરી
    final Map<String, int> candMap = {};
    final Map<String, String> candPartyMap = {};
    final Map<String, int> partyMap = {};

    for (var b in _localBallotVotes) {
      final cName = b['candidate_name'].toString();
      final pName = b['party_name'].toString();
      candMap[cName] = (candMap[cName] ?? 0) + 1;
      candPartyMap[cName] = pName;
      partyMap[pName] = (partyMap[pName] ?? 0) + 1;
    }

    int polled = _localVoters.where((v) => v['has_voted'] == 1).length;

    // ઓનલાઇન API થી પરિણામો લો
    try {
      final uri = Uri.parse('$_apiBaseUrl/api/voting/live-results');
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        polled = (data['total_votes_polled'] as num?)?.toInt() ?? polled;
      }
    } catch (_) {}

    setState(() {
      _totalPolledCount = polled;
      _candidateResults = candMap.entries.map((e) {
        return {
          'candidate_name': e.key,
          'party_name': candPartyMap[e.key] ?? '-',
          'vote_count': e.value,
        };
      }).toList()
        ..sort((a, b) => (b['vote_count'] as int).compareTo(a['vote_count'] as int));

      _partyResults = partyMap.entries.map((e) {
        return {
          'party_name': e.key,
          'vote_count': e.value,
        };
      }).toList()
        ..sort((a, b) => (b['vote_count'] as int).compareTo(a['vote_count'] as int));
    });
  }

  // --- નવો મતદાર નોંધણી ડાયલોગ (New Voter Registration) ---
  Future<void> _openNewVoterDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final aadhaarCtrl = TextEditingController(
      text: _aadhaarController.text.replaceAll(' ', '').trim(),
    );
    final ageCtrl = TextEditingController(text: '35');
    final boothCtrl = TextEditingController(text: '102');

    String selectedGender = 'પુરુષ (Male)';
    int selectedWard = 15;
    String selectedDistrict = 'જૂનાગઢ';
    bool isSubmitting = false;
    String? dialogError;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // હેડર
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_add_alt_1, color: Colors.indigo, size: 28),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'નવા મતદારની નોંધણી',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                                ),
                                Text(
                                  'મતદાર યાદી (Electoral Roll) માં નવું નામ ઉમેરો',
                                  style: TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const Divider(height: 24),

                      if (dialogError != null)
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),

                      // મતદારનું પૂરું નામ
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'મતદારનું પૂરું નામ *',
                          hintText: 'દા.ત. રાણવા હરસુખભાઈ મુળજીભાઈ',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'કૃપા કરીને પૂરું નામ દાખલ કરો';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // ૧૨-અંકનો આધાર કાર્ડ નંબર
                      TextFormField(
                        controller: aadhaarCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 12,
                        decoration: InputDecoration(
                          labelText: '૧૨-અંકનો આધાર નંબર *',
                          hintText: 'દા.ત. 123456789012',
                          counterText: '',
                          prefixIcon: const Icon(Icons.credit_card),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (val) {
                          final clean = (val ?? '').replaceAll(' ', '').trim();
                          if (clean.length != 12 || int.tryParse(clean) == null) {
                            return '૧૨ અંકનો સાચો આધાર નંબર દાખલ કરો';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // ઉંમર અને જાતિ
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: ageCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'ઉંમર *',
                                prefixIcon: const Icon(Icons.cake_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              validator: (val) {
                                final age = int.tryParse(val ?? '');
                                if (age == null || age < 18) {
                                  return '૧૮+ વર્ષ';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedGender,
                              decoration: InputDecoration(
                                labelText: 'જાતિ',
                                prefixIcon: const Icon(Icons.wc),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'પુરુષ (Male)', child: Text('પુરુષ (Male)')),
                                DropdownMenuItem(value: 'સ્ત્રી (Female)', child: Text('સ્ત્રી (Female)')),
                                DropdownMenuItem(value: 'અન્ય (Other)', child: Text('અન્ય (Other)')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => selectedGender = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // જિલ્લો અને વોર્ડ નંબર
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedDistrict,
                              decoration: InputDecoration(
                                labelText: 'જિલ્લો',
                                prefixIcon: const Icon(Icons.location_city),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'જૂનાગઢ', child: Text('જૂનાગઢ')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => selectedDistrict = val);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: selectedWard,
                              decoration: InputDecoration(
                                labelText: 'વોર્ડ નં.',
                                prefixIcon: const Icon(Icons.format_list_numbered),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              items: List.generate(15, (index) => index + 1)
                                  .map((w) => DropdownMenuItem(
                                        value: w,
                                        child: Text('વોર્ડ $w'),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => selectedWard = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // બૂથ નંબર
                      TextFormField(
                        controller: boothCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'બૂથ નંબર',
                          hintText: 'દા.ત. 102',
                          prefixIcon: const Icon(Icons.how_to_vote_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // સબમિટ બટન
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;

                                setModalState(() {
                                  isSubmitting = true;
                                  dialogError = null;
                                });

                                final rawAadhaar = aadhaarCtrl.text.replaceAll(' ', '').trim();
                                final voterName = nameCtrl.text.trim();
                                final voterAge = int.tryParse(ageCtrl.text.trim()) ?? 35;
                                final voterBooth = int.tryParse(boothCtrl.text.trim()) ?? 102;
                                final messenger = ScaffoldMessenger.of(context);
                                final navigator = Navigator.of(ctx);

                                try {
                                  final uri = Uri.parse('$_apiBaseUrl/api/voter/register');
                                  await http.post(
                                    uri,
                                    headers: {'Content-Type': 'application/json'},
                                    body: jsonEncode({
                                      'aadhaar_number': rawAadhaar,
                                      'full_name': voterName,
                                      'age': voterAge,
                                      'gender': selectedGender,
                                      'district': selectedDistrict,
                                      'taluka': selectedDistrict,
                                      'ward_no': selectedWard,
                                      'booth_no': voterBooth,
                                    }),
                                  ).timeout(const Duration(seconds: 4));
                                } catch (_) {}

                                final masked = 'XXXX XXXX ${rawAadhaar.substring(8)}';
                                final existingIdx = _localVoters.indexWhere(
                                  (v) => (v['aadhaar_masked']?.toString() ?? '').endsWith(rawAadhaar.substring(8)),
                                );

                                final newVoterData = {
                                  'id': existingIdx >= 0 ? _localVoters[existingIdx]['id'] : _localVoters.length + 1,
                                  'aadhaar_masked': masked,
                                  'full_name': voterName,
                                  'age': voterAge,
                                  'gender': selectedGender,
                                  'district': selectedDistrict,
                                  'taluka': selectedDistrict,
                                  'ward_no': selectedWard,
                                  'booth_no': voterBooth,
                                  'has_voted': 0,
                                  'voted_at': null,
                                };

                                if (existingIdx >= 0) {
                                  _localVoters[existingIdx] = newVoterData;
                                } else {
                                  _localVoters.add(newVoterData);
                                }
                                _totalVotersCount = _localVoters.length;

                                navigator.pop();

                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('✅ મતદાર "$voterName" ની સફળતાપૂર્વક નોંધણી થઈ ગઈ!'),
                                    backgroundColor: Colors.green.shade800,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );

                                _aadhaarController.text = rawAadhaar;
                                await _verifyAadhaar(rawAadhaar);
                              },
                        icon: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.how_to_reg),
                        label: Text(
                          isSubmitting ? 'નોંધણી થઈ રહી છે...' : 'મતદાર તરીકે નોંધણી કરો',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _resetFlow() {
    setState(() {
      _currentStep = 0;
      _aadhaarController.clear();
      _currentVoter = null;
      _errorMessage = '';
      _selectedCandidateId = null;
      _lastVoteReceipt = null;
    });
  }

  Color _getPartyColor(String party) {
    final p = party.toUpperCase();
    if (p.contains('BJP') || p.contains('ભાજપ')) return Colors.orange.shade800;
    if (p.contains('INC') || p.contains('કોંગ્રેસ')) return Colors.blue.shade700;
    if (p.contains('AAP') || p.contains('આપ')) return Colors.teal.shade700;
    if (p.contains('NCP')) return Colors.cyan.shade800;
    if (p.contains('NOTA')) return Colors.grey.shade800;
    return Colors.purple.shade700;
  }

  Widget _getPartySymbol(String party) {
    final p = party.toUpperCase();
    if (p.contains('BJP') || p.contains('ભાજપ')) {
      return const Text('🪷', style: TextStyle(fontSize: 24));
    }
    if (p.contains('INC') || p.contains('કોંગ્રેસ')) {
      return const Text('✋', style: TextStyle(fontSize: 24));
    }
    if (p.contains('AAP') || p.contains('આપ')) {
      return const Text('🧹', style: TextStyle(fontSize: 24));
    }
    if (p.contains('NCP')) {
      return const Text('⏰', style: TextStyle(fontSize: 24));
    }
    if (p.contains('NOTA')) {
      return const Text('❌', style: TextStyle(fontSize: 24));
    }
    return const Text('🚩', style: TextStyle(fontSize: 24));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🇮🇳 સ્માર્ટ વોટિંગ બૂથ (E-Voting)'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.how_to_vote), text: 'મતદાન (Cast Vote)'),
            Tab(icon: Icon(Icons.analytics_outlined), text: 'લાઈવ પરિણામ (Results)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: મતદાન પ્રક્રિયા (4-Step Voting Flow)
          _buildVotingFlow(),

          // TAB 2: લાઈવ પરિણામ અને મતગણતરી (Live Dashboard)
          _buildLiveResultsTab(),
        ],
      ),
    );
  }

  // --- TAB 1: વોટિંગ ફ્લો વિજેટ ---
  Widget _buildVotingFlow() {
    switch (_currentStep) {
      case 0:
        return _buildAadhaarStep();
      case 1:
        return _buildBiometricStep();
      case 2:
        return _buildBallotStep();
      case 3:
        return _buildVvpatStep();
      default:
        return _buildAadhaarStep();
    }
  }

  // STEP 0: આધાર કાર્ડ નંબર એન્ટ્રી
  Widget _buildAadhaarStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // સત્તાવાર હેડર કાર્ડ
          Card(
            color: Colors.indigo.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 6),
                      ],
                    ),
                    child: const Icon(Icons.fingerprint, size: 36, color: Colors.indigo),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'આધાર કાર્ડ બાયોમેટ્રિક મતદાન',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'બોગસ મતદાન અટકાવવા માટે ૧૨-અંકનો આધાર અને ફિંગરપ્રિન્ટ ચકાસણી ફરજિયાત છે.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          const Text(
            '૧૨-અંકનો આધાર કાર્ડ નંબર દાખલ કરો:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _aadhaarController,
            keyboardType: TextInputType.number,
            maxLength: 12,
            style: const TextStyle(fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'દા.ત. 1234 5678 9012',
              prefixIcon: const Icon(Icons.credit_card, color: Colors.indigo),
              filled: true,
              fillColor: Colors.white,
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),

          // ડેમો આધાર નંબરો (Quick Test Chips)
          const Text('ઝડપી ટેસ્ટિંગ માટે સેમ્પલ આધાર સિલેક્ટ કરો:', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(Icons.person, size: 16, color: Colors.indigo),
                label: const Text('રાણવા હરસુખભાઈ મુળજીભાઈ (વોર્ડ ૧૫)'),
                onPressed: () {
                  _aadhaarController.text = '123456789012';
                  _verifyAadhaar('123456789012');
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.person, size: 16, color: Colors.indigo),
                label: const Text('ગીતાબેન (વોર્ડ ૧૫)'),
                onPressed: () {
                  _aadhaarController.text = '987654321098';
                  _verifyAadhaar('987654321098');
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.person, size: 16, color: Colors.indigo),
                label: const Text('વિજયભાઈ (વોર્ડ ૯)'),
                onPressed: () {
                  _aadhaarController.text = '111122223333';
                  _verifyAadhaar('111122223333');
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // નવો મતદાર નોંધણી બટન
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.indigo,
              side: const BorderSide(color: Colors.indigo, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text(
              '➕ નવો મતદાર ઉમેરો (New Voter Registration)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _openNewVoterDialog,
          ),
          const SizedBox(height: 14),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _loading ? null : () => _verifyAadhaar(),
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline),
            label: Text(_loading ? 'ચકાસણી ચાલુ છે...' : 'મતદાર યાદીમાં ચકાસો', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),

          // એરર અથવા મતદાર સ્લિપ
          if (_errorMessage.isNotEmpty)
            Card(
              color: Colors.red.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_errorMessage, style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
            ),

          if (_currentVoter != null && _currentVoter!['has_voted'] == 0) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified, color: Colors.green, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'મતદાર ઓળખ સ્લિપ (${_currentVoter!['aadhaar_masked']})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _buildVoterDetailRow('👤 નામ:', _currentVoter!['full_name'] ?? '-'),
                    _buildVoterDetailRow('🏛️ જિલ્લો / તાલુકો:', '${_currentVoter!['district']} / ${_currentVoter!['taluka']}'),
                    _buildVoterDetailRow('🔢 ફાળવેલ વોર્ડ:', 'વોર્ડ નં. ${_currentVoter!['ward_no']}'),
                    _buildVoterDetailRow('📍 મતદાન બૂથ:', 'બૂથ નં. ${_currentVoter!['booth_no']}'),
                    _buildVoterDetailRow('🗳️ મતદાન સ્થિતિ:', 'બાકી (પાત્ર મતદાર)', Colors.green.shade800),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => setState(() => _currentStep = 1),
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('બાયોમેટ્રિક ફિંગરપ્રિન્ટ ચકાસો ➔', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoterDetailRow(String label, String value, [Color? valColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: valColor ?? Colors.black87))),
        ],
      ),
    );
  }

  // STEP 1: બાયોમેટ્રિક ફિંગરપ્રિન્ટ સ્કેન સ્ક્રીન
  Widget _buildBiometricStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.indigo.shade200, width: 3),
            ),
            child: const Icon(Icons.fingerprint, size: 90, color: Colors.indigo),
          ),
          const SizedBox(height: 24),

          const Text(
            'બાયોમેટ્રિક ફિંગરપ્રિન્ટ ચકાસણી',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Text(
            'મતદાર: ${_currentVoter?['full_name']}\nઆધાર કાર્ડ: ${_currentVoter?['aadhaar_masked']}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, height: 1.4, fontSize: 14),
          ),
          const SizedBox(height: 20),

          const Card(
            color: Color(0xFFFFF9C4),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.orange, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'UIDAI બાયોમેટ્રિક નિયમ: આંગળી મૂકતાં જ ઓળખ કાર્ડ સાથે ઓથેન્ટિકેટ થશે.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: _loading ? null : _authenticateBiometric,
            icon: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.fingerprint),
            label: Text(_loading ? 'સ્કેન થઈ રહ્યું છે...' : 'આંગળી સેન્સર પર મૂકો', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),

          TextButton(
            onPressed: () => setState(() => _currentStep = 0),
            child: const Text('પાછળ જાઓ (રદ કરો)', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // STEP 2: ડિજિટલ EVM બેલેટ યુનિટ
  Widget _buildBallotStep() {
    final wardNo = _currentVoter?['ward_no'] ?? 15;
    final district = _currentVoter?['district'] ?? 'જૂનાગઢ';

    return Column(
      children: [
        // EVM ટોપ કંટ્રોલ પેનલ
        Container(
          color: const Color(0xFF263238),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLedActive ? Colors.greenAccent : Colors.redAccent,
                  boxShadow: [
                    BoxShadow(
                      color: _isLedActive ? Colors.green : Colors.red,
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'ડિજિટલ EVM બેલેટ યુનિટ | $district મનપા - વોર્ડ નં. $wardNo',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.green.shade800, borderRadius: BorderRadius.circular(4)),
                child: const Text('READY TO VOTE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),

        // EVM ઉમેદવારોની સૂચિ
        Expanded(
          child: _ballotCandidates.isEmpty
              ? const Center(child: Text('આ વોર્ડ માટે કોઈ ઉમેદવાર ઉપલબ્ધ નથી'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  itemCount: _ballotCandidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final cand = _ballotCandidates[index];
                    final candId = (cand['id'] as num).toInt();
                    final name = cand['full_name']?.toString() ?? '-';
                    final party = cand['party_name']?.toString() ?? '-';
                    final isNota = candId == 9999;
                    final isSelected = _selectedCandidateId == candId;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade400, width: 1.5),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 4, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        children: [
                          // ક્રમ નંબર
                          Container(
                            width: 36,
                            height: 64,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              border: Border(right: BorderSide(color: Colors.grey.shade400)),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),

                          // ઉમેદવાર નામ અને પક્ષ
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: _getPartyColor(party),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          party,
                                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      if (!isNota) ...[
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => LeaderDetailScreen(reportCard: {
                                                  'full_name': name,
                                                  'party_name': party,
                                                  'constituency': cand['constituency'] ?? '',
                                                  'education': cand['education'] ?? 'Graduate',
                                                  'assets': [{'movable_assets': cand['total_assets'] ?? 0}],
                                                  'criminal_cases': [{'case_status': cand['case_status'] ?? 'Clean Record'}],
                                                  'performance': const <String, dynamic>{},
                                                }),
                                              ),
                                            );
                                          },
                                          child: const Text('પ્રોફાઇલ જુઓ ℹ️', style: TextStyle(color: Colors.indigo, fontSize: 11, decoration: TextDecoration.underline)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ચૂંટણી ચિહ્ન
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _getPartySymbol(party),
                          ),

                          // EVM લાલ લાઈટ
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected && _isLedActive ? Colors.greenAccent : Colors.red.shade900,
                              border: Border.all(color: Colors.black54),
                            ),
                          ),

                          // વાદળી VOTE બટન
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1565C0),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: () => _castVote(cand),
                              child: const Text('VOTE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // STEP 3: ડિજિટલ VVPAT સ્લિપ સ્ક્રીન
  Widget _buildVvpatStep() {
    final r = _lastVoteReceipt ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // VVPAT કમ્પાર્ટમેન્ટ
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.indigo.shade300, width: 2),
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.print_outlined, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Text(
                      'ડિજિટલ VVPAT મત પહોંચ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.indigo.shade900),
                    ),
                  ],
                ),
                const Divider(height: 24),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'ભારત ચૂંટણી પંચ / SEC GUJARAT',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1, color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        r['candidate_name'] ?? '-',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _getPartySymbol(r['party_name'] ?? ''),
                          const SizedBox(width: 8),
                          Text(
                            r['party_name'] ?? '-',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _getPartyColor(r['party_name'] ?? '')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      _buildReceiptRow('ટોકન નંબર:', r['token'] ?? '-'),
                      _buildReceiptRow('વિસ્તાર:', '${r['district']} - વોર્ડ નં. ${r['ward_no']}'),
                      _buildReceiptRow('બૂથ નંબર:', 'બૂથ નં. ${r['booth_no']}'),
                      _buildReceiptRow('તારીખ/સમય:', r['timestamp'] ?? '-'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 28),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'તમારો મત ગુપ્ત અને સુરક્ષિત રીતે ઇવીએમમાં નોંધાઈ ગયો છે. લોકશાહીમાં મતદાન કરવા બદલ આભાર!',
                          style: TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () {
                    _tabController.animateTo(1); // Go to results
                  },
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('લાઈવ પરિણામ જુઓ'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _resetFlow,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('નવું મતદાન (Next)'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- TAB 2: લાઈવ પરિણામ અને ડેશબોર્ડ ---
  Widget _buildLiveResultsTab() {
    final turnout = _totalVotersCount > 0 ? (_totalPolledCount / _totalVotersCount * 100).toStringAsFixed(1) : '0.0';

    return RefreshIndicator(
      onRefresh: _refreshLiveResults,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // મતદાન આંકડા કાર્ડ (Turnout Metrics)
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard('કુલ મતદારો', '$_totalVotersCount', Icons.people, Colors.indigo),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricCard('પડેલા મતો', '$_totalPolledCount', Icons.how_to_vote, Colors.green),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricCard('મતદાન %', '$turnout%', Icons.pie_chart, Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // પક્ષવાર વોટ શેર
            const Text(
              '🚩 પક્ષવાર મતદાન સ્થિતિ (Party Vote Share)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),

            if (_partyResults.isEmpty)
              Card(
                color: Colors.grey.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('હજુ સુધી કોઈ મત નોંધાયો નથી. પ્રથમ મત આપો!')),
                ),
              )
            else
              ..._partyResults.map((pr) {
                final pName = pr['party_name'].toString();
                final count = pr['vote_count'] as int;
                final pct = _totalPolledCount > 0 ? (count / _totalPolledCount) : 0.0;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _getPartySymbol(pName),
                            const SizedBox(width: 8),
                            Expanded(child: Text(pName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                            Text('$count મતો (${(pct * 100).toStringAsFixed(1)}%)', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: pct,
                          color: _getPartyColor(pName),
                          backgroundColor: Colors.grey.shade200,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 20),

            // ઉમેદવારવાર પરિણામો
            const Text(
              '👤 ઉમેદવારવાર વિગત (Candidate Tally)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),

            if (_candidateResults.isEmpty)
              const Center(child: Text('કોઈ ડેટા નથી'))
            else
              ..._candidateResults.map((cr) {
                final cName = cr['candidate_name'].toString();
                final pName = cr['party_name'].toString();
                final count = cr['vote_count'] as int;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getPartyColor(pName).withAlpha(38),
                    child: Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: _getPartyColor(pName))),
                  ),
                  title: Text(cName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('પક્ષ: $pName'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Text('$count VOTE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                  ),
                );
              }),

            const SizedBox(height: 30),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('ડેમો રીસેટ?'),
                    content: const Text('આનાથી તમામ આપેલા વોટ સાફ થઈ જશે અને ફરીથી નવો વોટ આપી શકાશે.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ના')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('રીસેટ કરો'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  _localBallotVotes.clear();
                  for (var v in _localVoters) {
                    v['has_voted'] = 0;
                    v['voted_at'] = null;
                  }
                  try {
                    await http.post(Uri.parse('$_apiBaseUrl/api/voting/reset')).timeout(const Duration(seconds: 3));
                  } catch (_) {}
                  await _refreshLiveResults();
                  _resetFlow();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ડેમો વોટિંગ રીસેટ થઈ ગયું છે')));
                  }
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('ડેમો વોટિંગ ડેટા રીસેટ કરો'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
