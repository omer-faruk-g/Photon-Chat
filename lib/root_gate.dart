import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'fip.dart';
import 'local_store.dart';
import 'theme.dart';
import 'guide_screen.dart';
import 'server_setup_screen.dart';
import 'onboarding_screen.dart';
import 'screens/contacts_screen.dart';
import 'app_keys.dart';
import 'update_checker.dart';
import 'photon_api.dart';
import 'notification_service.dart';

class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => RootGateState();
}

class RootGateState extends State<RootGate> {
  bool _loading = true;
  bool _guideSeen = false;
  String? _myServerUrl;
  FipBlock? _identity;
  String _displayName = '';
  Timer? _notifTimer;
  Timer? _keepAliveTimer;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _notifTimer?.cancel();
    _keepAliveTimer?.cancel();
    super.dispose();
  }

  void _startNotifPolling() {
    if (!Platform.isAndroid) return;
    _notifTimer?.cancel();
    _notifTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final serverUrl = _myServerUrl;
      final fipId = _identity?.fipId;
      if (serverUrl == null || fipId == null) return;
      final notifs = await PhotonApi.getNotifications(serverUrl, fipId);
      for (final n in notifs) {
        final title = n['title'] as String? ?? '';
        final body = n['body'] as String? ?? '';
        if (title.isNotEmpty && body.isNotEmpty) {
          await NotificationService.show(title, body);
        }
      }
    });
  }

  void _startKeepAlive(String serverUrl) {
    _keepAliveTimer?.cancel();
    // İlk ping hemen
    PhotonApi.pingServer(serverUrl);
    // Sonra her 10 dakikada bir ping — Render sunucusu uyumasın
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      PhotonApi.pingServer(serverUrl);
    });
  }

  Future<void> _load() async {
    final serverUrl = await LocalStore.loadMyServerUrl();
    final identity = await LocalStore.loadIdentity();
    final name = await LocalStore.loadDisplayName();
    final guideSeen = await LocalStore.isGuideSeen();
    setState(() {
      _myServerUrl = serverUrl;
      _identity = identity;
      _displayName = name ?? '';
      _guideSeen = guideSeen;
      _loading = false;
    });
    if (serverUrl != null && identity != null) {
      _startNotifPolling();
      _startKeepAlive(serverUrl);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateChecker.check(context);
    });
  }

  void reload() { setState(() => _loading = true); _load(); }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: PhotonColors.bg,
        body: Center(child: Text('PHOTON CHAT…', style: TextStyle(color: PhotonColors.accent, fontFamily: 'monospace', fontSize: 12, letterSpacing: 1.2))),
      );
    }

    if (!_guideSeen) {
      return GuideScreen(onDone: () async {
        await LocalStore.markGuideSeen();
        setState(() => _guideSeen = true);
      });
    }

    if (_myServerUrl == null) {
      return ServerSetupScreen(onDone: (url) async {
        await LocalStore.saveMyServerUrl(url);
        _startKeepAlive(url);
        setState(() => _myServerUrl = url);
      });
    }

    if (_identity == null) {
      return OnboardingScreen(
        myServerUrl: _myServerUrl!,
        onCreated: (fip, name) => setState(() { _identity = fip; _displayName = name; }),
      );
    }

    return ContactsScreen(identity: _identity!, displayName: _displayName, myServerUrl: _myServerUrl!);
  }
}

