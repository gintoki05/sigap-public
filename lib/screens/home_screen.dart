import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import 'assistant_screen.dart';
import 'education_screen.dart';
import '../viewmodels/assistant_view_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final AssistantViewModel _assistantViewModel = AssistantViewModel(
    inputMode: 'chat',
  );
  String _assistantInputMode = 'chat';
  int _assistantLaunchToken = 0;

  @override
  void initState() {
    super.initState();
    _assistantViewModel.initialize();
  }

  @override
  void dispose() {
    _assistantViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AssistantViewModel>.value(
      value: _assistantViewModel,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _HomeTab(onOpenAssistant: _openAssistant),
            AssistantScreen(
              initialInputMode: _assistantInputMode,
              launchRequestToken: _assistantLaunchToken,
            ),
            const EducationScreen(),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
            ),
          ),
          child: SafeArea(
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  _NavItem(
                    icon: Icons.home,
                    label: 'HOME',
                    selected: _currentIndex == 0,
                    onTap: () => setState(() => _currentIndex = 0),
                  ),
                  _NavItem(
                    icon: Icons.smart_toy_outlined,
                    label: 'AI ASSISTANT',
                    selected: _currentIndex == 1,
                    onTap: () => setState(() => _currentIndex = 1),
                  ),
                  _NavItem(
                    icon: Icons.school_outlined,
                    label: 'EDUCATION',
                    selected: _currentIndex == 2,
                    onTap: () => setState(() => _currentIndex = 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openAssistant({String inputMode = 'chat'}) {
    final shouldStartFreshInput =
        _assistantViewModel.messages.isEmpty &&
        !_assistantViewModel.isGeneratingResponse &&
        !_assistantViewModel.isRecordingVoice;

    setState(() {
      if (shouldStartFreshInput) {
        _assistantInputMode = inputMode;
        _assistantViewModel.setInputMode(inputMode);
        _assistantLaunchToken++;
      }
      _currentIndex = 1;
    });
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.navy : const Color(0xFF888888);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({required this.onOpenAssistant});

  final void Function({String inputMode}) onOpenAssistant;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  // --- Connectivity ---
  bool _isOnline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySub;

  // --- GPS ---
  bool _gpsActive = false;
  StreamSubscription<ServiceStatus>? _locationServiceSub;
  double? _latitude;
  double? _longitude;
  String? _locationName;
  bool _isFetchingLocation = false;

  // --- Date ---
  String _formattedDate = '';

  static const _dayNames = [
    'Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'
  ];
  static const _monthNames = [
    '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  String _formatDate(DateTime d) {
    return '${_dayNames[d.weekday % 7]}, ${d.day} ${_monthNames[d.month]} ${d.year}';
  }

  @override
  void initState() {
    super.initState();
    _formattedDate = _formatDate(DateTime.now());
    _initConnectivity();
    _initGps();
  }

  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _updateConnectivity(results);
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(_updateConnectivity);
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final online = results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
    if (mounted) setState(() => _isOnline = online);
  }

  Future<void> _initGps() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    final granted = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    
    if (mounted) setState(() => _gpsActive = serviceEnabled && granted);

    if (serviceEnabled && granted) {
      await _refreshCoordinates();
    }

    _locationServiceSub = Geolocator.getServiceStatusStream().listen((status) async {
      final isEnabled = status == ServiceStatus.enabled;
      final currentPermission = await Geolocator.checkPermission();
      final currentGranted = currentPermission == LocationPermission.always ||
          currentPermission == LocationPermission.whileInUse;
          
      if (mounted) {
        setState(() => _gpsActive = isEnabled && currentGranted);
      }

      if (isEnabled && currentGranted) {
        await _refreshCoordinates();
      } else if (mounted) {
        setState(() {
          _latitude = null;
          _longitude = null;
          _locationName = null;
        });
      }
    });
  }

  Future<void> _refreshCoordinates() async {
    if (_isFetchingLocation) return;
    
    if (mounted) {
      setState(() {
        _isFetchingLocation = true;
      });
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isFetchingLocation = false);
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _isFetchingLocation = false);
      await Geolocator.openAppSettings();
      return;
    }

    final granted = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    if (!granted) {
      if (mounted) setState(() => _isFetchingLocation = false);
      return;
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() {
          _latitude = lastKnown.latitude;
          _longitude = lastKnown.longitude;
        });
      }
    } catch (_) {
      // Abaikan fallback last known position jika belum tersedia.
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        setState(() {
          _latitude = pos.latitude;
          _longitude = pos.longitude;
        });
        _updateLocationName(pos.latitude, pos.longitude);
      }
    } catch (_) {
      // Jika posisi live belum didapat, biarkan last known position tetap tampil.
      if (_latitude != null && _longitude != null) {
        _updateLocationName(_latitude!, _longitude!);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingLocation = false;
        });
      }
    }
  }

  Future<void> _updateLocationName(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final name = [place.subLocality, place.locality, place.administrativeArea]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        if (mounted) {
          setState(() {
            _locationName = name.isNotEmpty ? name : place.name;
          });
        }
      }
    } catch (e) {
      // Ignore reverse geocoding errors, we still have coordinates
    }
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _locationServiceSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [

          // ── Konten utama scrollable ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  // ── Logo + nama app ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/logo/logo-sigap-transparant.png',
                        width: 42,
                        height: 42,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'SIGAP',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your Emergency Companion',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textGrey,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── Status badges ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _initGps,
                        child: _StatusBadge(
                          icon: _gpsActive ? Icons.location_on : Icons.location_off,
                          label: 'GPS',
                          color: _gpsActive
                              ? const Color(0xFF2ECC71)
                              : const Color(0xFFAAAAAA),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusBadge(
                        icon: _isOnline ? Icons.wifi : Icons.wifi_off,
                        label: _isOnline ? 'ONLINE' : 'OFFLINE',
                        color: _isOnline
                            ? const Color(0xFF2ECC71)
                            : const Color(0xFF4A90D9),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // ── Tanggal + Koordinat ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFEEEEEE),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 11,
                              color: AppColors.textGrey,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _formattedDate,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFE8E8E8),
                          ),
                        ),
                        GestureDetector(
                          onTap: _isFetchingLocation ? null : _refreshCoordinates,
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Icon(
                                  _isFetchingLocation ? Icons.schedule : Icons.my_location,
                                  size: 13,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _isFetchingLocation
                                      ? 'Mencari lokasi...'
                                      : (_latitude != null
                                          ? (_locationName ?? '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}')
                                          : 'Cari lokasi saya'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _latitude == null ? AppColors.navy : AppColors.textGrey,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Chat bubble greeting ──
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Avatar SIGAP
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.asset(
                              'assets/logo/logo-sigap-transparant.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Bubble
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDDE8F5),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(18),
                                topRight: Radius.circular(18),
                                bottomRight: Radius.circular(18),
                                bottomLeft: Radius.circular(4),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.navy.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Text(
                              'Halo! Saya SIGAP.\nSaya bisa membantu panduan pertolongan pertama. Ceritakan apa yang terjadi.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textDark,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Pertanyaan CTA ──
                  const Text(
                    'Bagaimana Anda ingin\nmenjelaskan situasinya?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Tiga tombol aksi ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ActionButton(
                        icon: Icons.chat_bubble_rounded,
                        label: 'Chat',
                        color: const Color(0xFF4A90D9),
                        onTap: () => widget.onOpenAssistant(inputMode: 'chat'),
                      ),
                      const SizedBox(width: 20),
                      _ActionButton(
                        icon: Icons.mic_rounded,
                        label: 'Suara',
                        color: AppColors.red,
                        onTap: () => widget.onOpenAssistant(inputMode: 'voice'),
                        isPrimary: true,
                      ),
                      const SizedBox(width: 20),
                      _ActionButton(
                        icon: Icons.camera_alt_rounded,
                        label: 'Foto',
                        color: const Color(0xFF4A90D9),
                        onTap: () => widget.onOpenAssistant(inputMode: 'photo'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Info tambahan singkat ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.navy.withValues(alpha: 0.04),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.navy.withValues(alpha: 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.offline_bolt_rounded,
                            color: AppColors.red,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Berjalan 100% offline',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navy,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Panduan P3K tersedia tanpa koneksi internet setelah model terpasang.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textGrey,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final double iconContainerSize = isPrimary ? 80 : 64;
    final double iconSize = isPrimary ? 36 : 28;
    final double fontSize = isPrimary ? 15 : 13;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: iconContainerSize,
            height: iconContainerSize,
            decoration: BoxDecoration(
              color: isPrimary ? color : color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              boxShadow: isPrimary
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: isPrimary ? Colors.white : color,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight:
                  isPrimary ? FontWeight.w700 : FontWeight.w600,
              color: isPrimary ? color : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
