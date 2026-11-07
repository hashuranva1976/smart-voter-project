import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'models/scan_models.dart';
import 'screens/scan_result_screen.dart';

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
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = false;
  final ImagePicker _picker = ImagePicker();

  // લાઈવ ક્લાઉડ સર્વર (Render) અથવા લોકલ સર્વર
  String serverUrl = 'https://smart-voter-project.onrender.com/api/scan-poster';

  Future<Size> _getSize(File file) async {
    final bytes = await file.readAsBytes();
    final c = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (img) => c.complete(img));
    final img = await c.future;
    return Size(img.width.toDouble(), img.height.toDouble());
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: serverUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('સર્વર URL સેટિંગ્સ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'એમ્યુલેટર: http://10.0.2.2:5000/api/scan-poster\n'
              'રિયલ ફોન: http://<PC-IP>:5000/api/scan-poster\n'
              'પીસી/ડેસ્કટોપ: http://127.0.0.1:5000/api/scan-poster',
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
                setState(() => serverUrl = newUrl);
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
    final XFile? xf = await _picker.pickImage(source: source, imageQuality: 85);
    if (xf == null) return;

    final file = File(xf.path);
    setState(() => _loading = true);

    try {
      final size = await _getSize(file);
      final req = http.MultipartRequest('POST', Uri.parse(serverUrl));
      req.files.add(await http.MultipartFile.fromPath('image', file.path));

      final streamedResponse = await req.send().timeout(const Duration(seconds: 30));
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
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.document_scanner, size: 80, color: Colors.indigo),
                  const SizedBox(height: 16),
                  const Text('ચૂંટણી પોસ્ટરનો ફોટો પાડો અથવા પસંદ કરો', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _pickAndUpload(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('કેમેરાથી સ્કેન કરો'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _pickAndUpload(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('ગેલેરીમાંથી પસંદ કરો'),
                  ),
                ],
              ),
      ),
    );
  }
}
