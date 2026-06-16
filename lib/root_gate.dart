import 'package:flutter/material.dart';
import 'fip.dart';
import 'local_store.dart';
import 'theme.dart';
import 'guide_screen.dart';
import 'server_setup_screen.dart';
import 'onboarding_screen.dart';
import 'screens/contacts_screen.dart';
import 'app_keys.dart';

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

  @override
  void initState() { super.initState(); _load(); }

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
  }

  void reload() { setState(() => _loading = true); _load(); }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: KnkColors.bg,
        body: Center(child: Text('PHOTON CHAT…', style: TextStyle(color: KnkColors.accent, fontFamily: 'monospace', fontSize: 12, letterSpacing: 1.2))),
      );
    }

    if (!_guideSeen) {
      return GuideScreen(onDone: () async {
        await LocalStore.markGuideSeen();
        setState(() => _guideSeen = true);
      });
    }

    if (_myServerUrl == null) {
      return ServerSetupScreen(onDone: (url) => setState(() => _myServerUrl = url));
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
