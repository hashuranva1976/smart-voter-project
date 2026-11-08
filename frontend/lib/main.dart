import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'models/scan_models.dart';
import 'screens/scan_result_screen.dart';
import 'screens/search_screen.dart';
import 'screens/voting_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'સ્માર્ટ વોટર',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  String serverUrl = 'https://smart-voter-project.onrender.com/api/scan-poster';

  void _updateServerUrl(String newUrl) {
    setState(() => serverUrl = newUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          PosterScanTab(
            serverUrl: serverUrl,
            onServerUrlChanged: _updateServerUrl,
            onOpenSearch: () => setState(() => _currentIndex = 1),
          ),
          SearchScreen(serverUrl: serverUrl),
          VotingScreen(serverUrl: serverUrl),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner, color: Colors.indigo),
            label: 'પોસ્ટર સ્કેનર',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search, color: Colors.indigo),
            label: 'નેતા / વોર્ડ શોધો',
          ),
          NavigationDestination(
            icon: Icon(Icons.how_to_vote_outlined),
            selectedIcon: Icon(Icons.how_to_vote, color: Colors.indigo),
            label: 'મતદાન કેન્દ્ર',
          ),
        ],
      ),
    );
  }
}

class PosterScanTab extends StatefulWidget {
  final String serverUrl;
  final ValueChanged<String> onServerUrlChanged;
  final VoidCallback onOpenSearch;

  const PosterScanTab({
    super.key,
    required this.serverUrl,
    required this.onServerUrlChanged,
    required this.onOpenSearch,
  });

  @override
  State<PosterScanTab> createState() => _PosterScanTabState();
}

class _PosterScanTabState extends State<PosterScanTab> {
  bool _loading = false;
  final ImagePicker _picker = ImagePicker();

  Future<Size> _getSize(File file) async {
    final bytes = await file.readAsBytes();
    final c = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (img) => c.complete(img));
    final img = await c.future;
    return Size(img.width.toDouble(), img.height.toDouble());
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: widget.serverUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('સર્વર URL સેટિંગ્સ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ક્લાઉડ: https://smart-voter-project.onrender.com/api/scan-poster\n'
              'લોકલ એમ્યુલેટર: http://10.0.2.2:5000/api/scan-poster\n'
              'રિયલ ફોન (WiFi): http://<PC-IP>:5000/api/scan-poster',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Backend API URL',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('રદ કરો'),
          ),
          ElevatedButton(
            onPressed: () {
              var newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                newUrl = newUrl.replaceAll(RegExp(r'/+$'), '');
                if (!newUrl.endsWith('/api/scan-poster')) {
                  newUrl = '$newUrl/api/scan-poster';
                }
                widget.onServerUrlChanged(newUrl);
              }
              Navigator.pop(ctx);
            },
            child: const Text('સેવ કરો'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final XFile? xf = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
    if (xf == null) return;

    final file = File(xf.path);
    setState(() => _loading = true);

    try {
      final size = await _getSize(file);
      final req = http.MultipartRequest('POST', Uri.parse(widget.serverUrl));
      req.files.add(await http.MultipartFile.fromPath('image', file.path));

      final streamedResponse = await req.send().timeout(const Duration(seconds: 90));
      final res = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = ((body['leaders'] ?? []) as List)
            .map((e) => LeaderScanItem.fromJson(e as Map<String, dynamic>))
            .toList();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScanResultScreen(
              file: file,
              leaders: list,
              originalSize: size,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('સર્વર પ્રતિસાદ આપવામાં નિષ્ફળ (કોડ: ${res.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('કનેક્શન એરર: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('સ્માર્ટ વોટર - પોસ્ટર સ્કેનર'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'નામ/ગામ/વોર્ડથી શોધો',
            onPressed: widget.onOpenSearch,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'સર્વર સેટિંગ્સ',
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('પોસ્ટરનું વિશ્લેષણ થઈ રહ્યું છે...'),
                ],
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ઝડપી સર્ચ બેનર કાર્ડ
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: Colors.indigo.shade50,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: widget.onOpenSearch,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.search, color: Colors.indigo, size: 28),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'નામ, ગામ, વોર્ડ કે જિલ્લો થી શોધો',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.indigo,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'ફોટો વગર પણ સમગ્ર ગુજરાતના ઉમેદવારો ઉપલબ્ધ',
                                      style: TextStyle(fontSize: 12, color: Colors.black54),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.indigo),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),
                    const Icon(Icons.document_scanner, size: 80, color: Colors.indigo),
                    const SizedBox(height: 16),
                    const Text(
                      'અથવા ચૂંટણી પોસ્ટરનો ફોટો પાડો',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'પોસ્ટરમાં રહેલા તમામ નેતાઓને ઓટોમેટિક ઓળખશે',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: () => _pickAndUpload(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('કેમેરાથી સ્કેન કરો', style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: () => _pickAndUpload(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('ગેલેરીમાંથી પસંદ કરો', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
