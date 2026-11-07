import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

/// Initializes Flutter and starts the Status Saver application.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StatusSaverApp());
}

/// Configures the app-wide theme and opens the home screen.
class StatusSaverApp extends StatelessWidget {
  /// Creates the root application widget.
  const StatusSaverApp({super.key});

  /// Builds the root Material application widget.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Status Saver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF075E54),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF1F1F1F),
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

/// Displays a short success or error message above the current screen.
///
/// Set [isError] to true to use the error icon and color.
void showCustomSnackBar(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
        ],
      ),
      backgroundColor: isError ? Colors.redAccent : const Color(0xFF25D366), // Custom colors
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
      duration: const Duration(seconds: 2),
    ),
  );
}

/// Identifies the kind of media represented by a status.
enum StatusType {
  /// An image status.
  image,

  /// A video status.
  video,
}

/// Identifies which messaging app's statuses are being displayed.
enum AppType {
  /// The standard WhatsApp application.
  whatsapp,

  /// The WhatsApp Business application.
  whatsappBusiness,
}

/// Holds the file details required to display and save a status.
class StatusModel {
  /// The original file name.
  final String path;

  /// The local file path used to read the media.
  final String uri;

  /// Whether this status contains an image or a video.
  final StatusType type;

  /// Creates a status with its file name, location, and media type.
  StatusModel({
    required this.path,
    required this.uri,
    required this.type,
  });
}

/// Main screen for selecting an app and browsing its available statuses.
class HomeScreen extends StatefulWidget {
  /// Creates the home screen.
  const HomeScreen({super.key});

  /// Creates the mutable state that manages status loading and selection.
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Stores the home screen's selection, permission, and loading state.
class _HomeScreenState extends State<HomeScreen> {
  /// Connects Flutter to the Android folder-access and file operations.
  static const MethodChannel _safChannel = MethodChannel('com.sktechstudio.status_saver/saf');
  
  /// The messaging app whose statuses are currently selected.
  AppType _selectedApp = AppType.whatsapp;

  /// Whether a status list request is currently in progress.
  bool _isLoading = false;

  /// Whether the user has granted access to the selected app's status folder.
  bool _hasPermission = false;

  /// Status files currently available for the selected app.
  List<StatusModel> _allStatuses = [];

  /// Checks for a previously granted folder permission when the screen starts.
  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  /// Returns the saved-preference key used for the selected app's folder URI.
  String _getPrefKey(AppType appType) {
    return appType == AppType.whatsapp ? 'wa_tree_uri' : 'wab_tree_uri';
  }

  /// Restores the selected app's saved permission and loads its statuses.
  Future<void> _checkPermissionAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_getPrefKey(_selectedApp));
    
    if (uri != null && uri.isNotEmpty) {
      setState(() => _hasPermission = true);
      _loadStatuses();
    } else {
      setState(() {
        _hasPermission = false;
        _allStatuses = [];
      });
    }
  }

  /// Opens Android's folder picker for the selected app's status directory.
  Future<void> _requestPermission() async {
    try {
      final String initialPath = _selectedApp == AppType.whatsapp
          ? 'Android%2Fmedia%2Fcom.whatsapp%2FWhatsApp%2FMedia%2F.Statuses'
          : 'Android%2Fmedia%2Fcom.whatsapp.w4b%2FWhatsApp%20Business%2FMedia%2F.Statuses';

      final String? selectedUri = await _safChannel.invokeMethod<String>(
        'openDirectory',
        {'initialPath': initialPath},
      );

      if (selectedUri != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_getPrefKey(_selectedApp), selectedUri);
        setState(() => _hasPermission = true);
        _loadStatuses();
      }
    } catch (e) {
      if (mounted) showCustomSnackBar(context, 'Failed to get permission', isError: true);
    }
  }

  /// Reads the selected folder through Android and keeps supported media files.
  Future<void> _loadStatuses() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final treeUri = prefs.getString(_getPrefKey(_selectedApp));

    if (treeUri == null || treeUri.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final List<dynamic>? files = await _safChannel.invokeMethod<List<dynamic>>(
        'getFilesFromUri',
        {'uri': treeUri},
      );

      if (files != null) {
        List<StatusModel> statuses = [];
        for (var file in files) {
          final map = Map<String, dynamic>.from(file);
          final String name = map['name'] ?? '';
          final String fileUri = map['uri'] ?? '';

          if (name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png')) {
            statuses.add(StatusModel(path: name, uri: fileUri, type: StatusType.image));
          } else if (name.endsWith('.mp4') || name.endsWith('.mkv')) {
            statuses.add(StatusModel(path: name, uri: fileUri, type: StatusType.video));
          }
        }
        setState(() => _allStatuses = statuses);
      }
    } catch (e) {
      setState(() => _allStatuses = []);
      if (mounted) showCustomSnackBar(context, 'Error loading statuses', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Changes the selected messaging app and loads its saved folder and statuses.
  void _switchAppType(AppType appType) {
    if (_selectedApp != appType) {
      setState(() {
        _selectedApp = appType;
      });
      _checkPermissionAndLoad();
    }
  }

  /// Builds the app bar, permission/status content, drawer, and app selector.
  @override
  Widget build(BuildContext context) {
    final titleName = _selectedApp == AppType.whatsapp ? 'WhatsApp' : 'WA Business';

    return Scaffold(
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: const Text('Status Saver', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF075E54),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _hasPermission ? _loadStatuses : null,
          )
        ],
      ),
      body: !_hasPermission
          ? _buildPermissionDeniedView(titleName)
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildStatusGrid(_allStatuses), // Combined grid for images & videos
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedApp == AppType.whatsapp ? 0 : 1,
        onTap: (index) {
          _switchAppType(index == 0 ? AppType.whatsapp : AppType.whatsappBusiness);
        },
        backgroundColor: const Color(0xFF1F1F1F),
        selectedItemColor: const Color(0xFF25D366),
        unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'WhatsApp'),
          BottomNavigationBarItem(icon: Icon(Icons.business_center), label: 'WA Business'),
        ],
      ),
    );
  }

  /// Opens a URL in an external application and reports launch failures.
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) showCustomSnackBar(context, 'Could not launch URL', isError: true);
    }
  }

  /// Opens the system share sheet with the app's store link.
  void _shareApp() {
    Share.share('Check out Status Saver to easily save WhatsApp statuses! Download here: https://play.google.com/store/apps/details?id=com.sktechstudio.status_saver');
  }

  /// Builds the navigation drawer with policy, sharing, and app information links.
  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF075E54)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Icon(Icons.download_for_offline_rounded, size: 48, color: Colors.white),
                SizedBox(height: 12),
                Text(
                  'Status Saver',
                  style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Developed by SKTechStudio',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            onTap: () {
              Navigator.pop(context);
              _launchURL('https://sktechstudio.blogspot.com/p/privacy-policy-status-save.html');
            },
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms & Condition'),
            onTap: () {
              Navigator.pop(context);
              _launchURL('https://sktechstudio.blogspot.com/p/terms-conditions-status-saver.html');
            },
          ),
          ListTile(
            leading: const Icon(Icons.warning_amber_rounded),
            title: const Text('Disclaimer'),
            onTap: () {
              Navigator.pop(context);
              _launchURL('https://sktechstudio.blogspot.com/p/disclaimer-status-saver.html');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.star_rate_rounded),
            title: const Text('Rate us'),
            onTap: () {
              Navigator.pop(context);
              _launchURL('https://play.google.com/store/apps/details?id=com.sktechstudio.status_saver');
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_rounded),
            title: const Text('Share app'),
            onTap: () {
              Navigator.pop(context);
              _shareApp();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Shows instructions and a button when folder access has not been granted.
  Widget _buildPermissionDeniedView(String title) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_shared, size: 70, color: Color(0xFF075E54)),
            const SizedBox(height: 16),
            Text(
              'Permission Needed for $title',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Please grant folder access to media statuses directory.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _requestPermission,
              child: const Text('Grant Folder Access', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// Creates a cached thumbnail for a video and returns its local file path.
  ///
  /// Returns null if thumbnail generation fails.
  Future<String?> _getVideoThumbnail(String videoUri) async {
    try {
      final plugin = FcNativeVideoThumbnail();
      final tempDir = await getTemporaryDirectory();
      final fileName = 'thumb_${videoUri.hashCode}.jpg';
      final destPath = '${tempDir.path}/$fileName';

      if (await File(destPath).exists()) return destPath;

      final success = await plugin.saveThumbnailToFile(
        srcFile: videoUri,
        destFile: destPath,
        width: 300,
        height: 300,
        format: 'jpeg',
        srcFileUri: true,
      );
      return success ? destPath : null;
    } catch (_) {
      return null;
    }
  }

  /// Builds the media grid, including an empty state when no files are available.
  Widget _buildStatusGrid(List<StatusModel> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.perm_media_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No status available', style: TextStyle(color: Colors.grey)),
            TextButton(
              onPressed: _loadStatuses,
              child: const Text('Refresh', style: TextStyle(color: Color(0xFF25D366))),
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStatuses,
      color: const Color(0xFF25D366),
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.8,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];

          return GestureDetector(
            onTap: () {
              if (item.type == StatusType.image) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ViewImageScreen(status: item)));
              } else {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ViewVideoScreen(status: item)));
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.type == StatusType.image
                      ? Image.file(
                          File(item.uri),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade900,
                            child: const Icon(Icons.broken_image, color: Colors.white54),
                          ),
                        )
                      : FutureBuilder<String?>(
                          future: _getVideoThumbnail(item.uri),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                              return Image.file(File(snapshot.data!), fit: BoxFit.cover);
                            }
                            return Container(
                              color: Colors.black26,
                              child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF25D366))),
                            );
                          },
                        ),
                  if (item.type == StatusType.video)
                    const Center(
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.black45,
                        child: Icon(Icons.play_arrow, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Copies a status file into the app's Pictures/StatusSaver gallery folder.
///
/// Returns true when Android reports that the copy succeeded.
Future<bool> _saveMediaToGallery(String sourceUri, String fileName) async {
  try {
    final Directory? extDir = await getExternalStorageDirectory();
    if (extDir == null) return false;

    final String targetDirPath = '${extDir.parent.parent.parent.parent.path}/Pictures/StatusSaver';
    final Directory targetDir = Directory(targetDirPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final String targetFilePath = '$targetDirPath/$fileName';
    final bool success = await const MethodChannel('com.sktechstudio.status_saver/saf').invokeMethod('saveFile', {
      'sourceUri': sourceUri,
      'targetPath': targetFilePath,
    }) ?? false;

    return success;
  } catch (e) {
    return false;
  }
}

/// Displays an image status and provides an option to save it.
class ViewImageScreen extends StatelessWidget {
  /// The image status displayed by this screen.
  final StatusModel status;

  /// Creates the image viewer for [status].
  const ViewImageScreen({super.key, required this.status});

  /// Saves the image and shows the result while the screen is still available.
  void _save(BuildContext context) async {
    final success = await _saveMediaToGallery(status.uri, status.path);
    if (!context.mounted) return;
    
    if (success) {
      showCustomSnackBar(context, 'Saved to Pictures/StatusSaver');
    } else {
      showCustomSnackBar(context, 'Failed to save image', isError: true);
    }
  }

  /// Builds a zoomable image viewer with a save action.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.download_rounded), onPressed: () => _save(context)),
        ],
      ),
      body: Center(
        child: InteractiveViewer(child: Image.file(File(status.uri))),
      ),
    );
  }
}

/// Displays a video status and provides an option to save it.
class ViewVideoScreen extends StatefulWidget {
  /// The video status displayed by this screen.
  final StatusModel status;

  /// Creates the video viewer for [status].
  const ViewVideoScreen({super.key, required this.status});

  /// Creates the state that manages the native video player.
  @override
  State<ViewVideoScreen> createState() => _ViewVideoScreenState();
}

/// Manages the native video player's lifecycle and save action.
class _ViewVideoScreenState extends State<ViewVideoScreen> {
  /// Controller used to initialize, load, and dispose the native player.
  late NativeVideoPlayerController _controller;

  /// Creates the video controller and starts player initialization.
  @override
  void initState() {
    super.initState();
    _controller = NativeVideoPlayerController(
      id: widget.status.uri.hashCode,
      autoPlay: true,
    );
    _initVideoPlayer();
  }

  /// Initializes the native player and loads the selected video file.
  Future<void> _initVideoPlayer() async {
    await _controller.initialize();
    await _controller.load(url: widget.status.uri);
  }

  /// Releases the native player resources when this screen is removed.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Saves the video and shows the result if this screen is still mounted.
  void _save() async {
    final success = await _saveMediaToGallery(widget.status.uri, widget.status.path);
    if (!mounted) return;

    if (success) {
      showCustomSnackBar(context, 'Saved to Pictures/StatusSaver');
    } else {
      showCustomSnackBar(context, 'Failed to save video', isError: true);
    }
  }

  /// Builds the video player with a save action in the app bar.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.download_rounded), onPressed: _save),
        ],
      ),
      body: Center(
        child: NativeVideoPlayer(
          controller: _controller,
        ),
      ),
    );
  }
}

/// Shows the app name, version, description, and developer information.
class AboutScreen extends StatelessWidget {
  /// Creates the About screen.
  const AboutScreen({super.key});

  /// Builds the app information screen.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: const Color(0xFF075E54),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.download_for_offline_rounded, size: 80, color: Color(0xFF25D366)),
            ),
            const SizedBox(height: 24),
            const Text('Status Saver', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Version 1.0.0', style: TextStyle(fontSize: 14, color: Colors.white70)),
            ),
            const SizedBox(height: 32),
            const Text(
              'Easily view and save image & video statuses from WhatsApp and WhatsApp Business directly to your device gallery without quality loss.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.5, color: Colors.white70),
            ),
            const Spacer(),
            const Divider(color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'Developed by SKTechStudio',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            const Text(
              '© 2026 SKTechStudio. All Rights Reserved.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}