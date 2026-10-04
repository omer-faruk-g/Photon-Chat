import 'dart:async';
import 'package:flutter/material.dart';
import '../app_lock.dart';
import '../i18n.dart';
import '../theme.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _type = 'pin';
  String _input = '';
  List<int> _pattern = [];
  String? _error;
  bool _loading = true;
  int _pinLen = 4;
  int _wrongTries = 0;
  DateTime? _lockedUntil;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    AppLock.getType().then((t) async {
      final len = await AppLock.getPinLength();
      if (mounted) setState(() { _type = t; _pinLen = len; _loading = false; });
    });
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  bool get _isLockedOut => _lockedUntil != null && _lockedUntil!.isAfter(DateTime.now());

  Future<void> _tryUnlock() async {
    if (_isLockedOut) return;
    final value = _type == 'pin' ? _input : _pattern.join('-');
    final ok = await AppLock.verify(value);
    if (!mounted) return;
    if (ok) {
      _wrongTries = 0;
      widget.onUnlocked();
    } else {
      _wrongTries++;
      if (_wrongTries >= 3) {
        // 30-second lockout after 3 wrong attempts, doubles each further failure.
        final extra = (_wrongTries - 3).clamp(0, 4);
        final seconds = 30 * (1 << extra);
        _lockedUntil = DateTime.now().add(Duration(seconds: seconds));
        _lockoutTimer?.cancel();
        _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) { t.cancel(); return; }
          if (!_isLockedOut) {
            t.cancel();
            setState(() { _error = null; });
          } else {
            setState(() {}); // tick countdown
          }
        });
      }
      setState(() {
        _error = _isLockedOut
            ? '${_wrongTries} ${AppLang.instance.t('wrongTriesPrefix')} ${_lockedUntil!.difference(DateTime.now()).inSeconds}${AppLang.instance.t('waitSecondsSuffix')}'
            : '${_type == 'pin' ? AppLang.instance.t('wrongPin') : AppLang.instance.t('wrongPattern')}. ${AppLang.instance.t('wrongRetry')}';
        _input = '';
        _pattern = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(backgroundColor: PhotonColors.bg, body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: PhotonColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _type == 'pin' ? _buildPinUI() : _buildPatternUI(),
          ),
        ),
      ),
    );
  }

  Widget _buildPinUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline, color: PhotonColors.accent, size: 48),
        const SizedBox(height: 16),
        Text(AppLang.instance.t('enterPin'), style: TextStyle(color: PhotonColors.text, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_error != null) Text(_error!, style: TextStyle(color: Colors.redAccent, fontSize: 12)),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_pinLen, (i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _input.length ? PhotonColors.accent : Colors.transparent,
              border: Border.all(color: PhotonColors.accent, width: 2),
            ),
          )),
        ),
        const SizedBox(height: 32),
        _buildNumpad(),
      ],
    );
  }

  Widget _buildNumpad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: keys.map((row) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row.map((k) {
          if (k.isEmpty) return const SizedBox(width: 72, height: 56);
          return GestureDetector(
            onTap: () {
              if (_isLockedOut) return;
              setState(() { _error = null; });
              if (k == '⌫') {
                if (_input.isNotEmpty) setState(() => _input = _input.substring(0, _input.length - 1));
              } else {
                if (_input.length < _pinLen) setState(() => _input += k);
                if (_input.length >= _pinLen) _tryUnlock();
              }
            },
            child: Container(
              width: 72,
              height: 56,
              alignment: Alignment.center,
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: PhotonColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PhotonColors.line),
              ),
              child: Text(k, style: TextStyle(color: PhotonColors.text, fontSize: 22, fontWeight: FontWeight.w500)),
            ),
          );
        }).toList(),
      )).toList(),
    );
  }

  Widget _buildPatternUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.pattern, color: PhotonColors.accent, size: 48),
        const SizedBox(height: 16),
        Text(AppLang.instance.t('drawPattern'), style: TextStyle(color: PhotonColors.text, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_error != null) Text(_error!, style: TextStyle(color: Colors.redAccent, fontSize: 12)),
        const SizedBox(height: 24),
        _PatternGrid(
          selected: _pattern,
          onComplete: (p) {
            if (_isLockedOut) return;
            setState(() { _pattern = p; _error = null; });
            _tryUnlock();
          },
        ),
      ],
    );
  }
}

class _PatternGrid extends StatefulWidget {
  final List<int> selected;
  final ValueChanged<List<int>> onComplete;
  const _PatternGrid({required this.selected, required this.onComplete});

  @override
  State<_PatternGrid> createState() => _PatternGridState();
}

class _PatternGridState extends State<_PatternGrid> {
  List<int> _current = [];
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    const size = 240.0;
    const dotSize = 40.0;
    const spacing = (size - dotSize * 3) / 2;

    return GestureDetector(
      onPanStart: (d) {
        setState(() { _current = []; _dragging = true; });
        _checkHit(d.localPosition, size, dotSize, spacing);
      },
      onPanUpdate: (d) => _checkHit(d.localPosition, size, dotSize, spacing),
      onPanEnd: (_) {
        _dragging = false;
        if (_current.length >= 3) {
          widget.onComplete(List.from(_current));
        }
        setState(() => _current = []);
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: List.generate(9, (i) {
            final row = i ~/ 3;
            final col = i % 3;
            final x = col * (dotSize + spacing);
            final y = row * (dotSize + spacing);
            final active = _current.contains(i);
            return Positioned(
              left: x,
              top: y,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? PhotonColors.accent.withValues(alpha: 0.3) : Colors.transparent,
                  border: Border.all(color: active ? PhotonColors.accent : PhotonColors.textDim, width: 2),
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? PhotonColors.accent : PhotonColors.textDim,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  void _checkHit(Offset pos, double size, double dotSize, double spacing) {
    for (int i = 0; i < 9; i++) {
      final row = i ~/ 3;
      final col = i % 3;
      final cx = col * (dotSize + spacing) + dotSize / 2;
      final cy = row * (dotSize + spacing) + dotSize / 2;
      if ((pos - Offset(cx, cy)).distance < dotSize * 0.7 && !_current.contains(i)) {
        setState(() => _current.add(i));
        break;
      }
    }
  }
}

class SetLockScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SetLockScreen({super.key, required this.onDone});

  @override
  State<SetLockScreen> createState() => _SetLockScreenState();
}

class _SetLockScreenState extends State<SetLockScreen> {
  String _type = 'pin';
  String _pin = '';
  String? _confirmPin;
  List<int> _pattern = [];
  List<int>? _confirmPattern;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhotonColors.bg,
      appBar: AppBar(
        backgroundColor: PhotonColors.bg,
        leading: IconButton(icon: Icon(Icons.close, color: PhotonColors.text), onPressed: () => Navigator.pop(context)),
        title: Text(AppLang.instance.t('setLock'), style: TextStyle(color: PhotonColors.text, fontSize: 16)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _buildTypeChip('pin', 'PIN'),
              const SizedBox(width: 12),
              _buildTypeChip('pattern', 'Desen'),
            ]),
            const SizedBox(height: 32),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              const SizedBox(height: 12),
            ],
            if (_type == 'pin') _buildPinSetup() else _buildPatternSetup(),
          ]),
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type, String label) {
    final active = _type == type;
    return GestureDetector(
      onTap: () => setState(() { _type = type; _pin = ''; _confirmPin = null; _pattern = []; _confirmPattern = null; _error = null; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: active ? PhotonColors.accent : PhotonColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? PhotonColors.accent : PhotonColors.line),
        ),
        child: Text(label, style: TextStyle(color: active ? const Color(0xFF06251A) : PhotonColors.text, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildPinSetup() {
    final isConfirm = _confirmPin != null;
    return Column(children: [
      Text(isConfirm ? AppLang.instance.t('confirmPin') : AppLang.instance.t('newPinEnter'), style: TextStyle(color: PhotonColors.text, fontSize: 14)),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate((_pin.length + 1) < 4 ? 4 : ((_pin.length + 1) > 6 ? 6 : _pin.length + 1), (i) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < _pin.length ? PhotonColors.accent : Colors.transparent,
            border: Border.all(color: PhotonColors.accent, width: 2),
          ),
        )),
      ),
      const SizedBox(height: 24),
      _buildSetupNumpad(),
    ]);
  }

  Widget _buildSetupNumpad() {
    final keys = [['1','2','3'],['4','5','6'],['7','8','9'],['','0','⌫']];
    return Column(
      children: [
        ...keys.map((row) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((k) {
            if (k.isEmpty) return const SizedBox(width: 72, height: 56);
            return GestureDetector(
              onTap: () {
                setState(() => _error = null);
                if (k == '⌫') {
                  if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
                } else if (_pin.length < 6) {
                  setState(() => _pin += k);
                }
              },
              child: Container(
                width: 72, height: 56,
                alignment: Alignment.center,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: PhotonColors.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: PhotonColors.line)),
                child: Text(k, style: TextStyle(color: PhotonColors.text, fontSize: 22, fontWeight: FontWeight.w500)),
              ),
            );
          }).toList(),
        )),
        const SizedBox(height: 16),
        if (_pin.length >= 4)
          GestureDetector(
            onTap: _onPinSubmit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              decoration: BoxDecoration(color: PhotonColors.accent, borderRadius: BorderRadius.circular(8)),
              child: Text(AppLang.instance.t('confirm'), style: TextStyle(color: const Color(0xFF06251A), fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  void _onPinSubmit() {
    if (_confirmPin == null) {
      setState(() { _confirmPin = _pin; _pin = ''; });
    } else {
      if (_pin == _confirmPin) {
        AppLock.enable('pin', _pin).then((_) {
          if (!mounted) return;
          widget.onDone();
          Navigator.pop(context);
        });
      } else {
        setState(() { _error = AppLang.instance.t('pinsDontMatch'); _pin = ''; _confirmPin = null; });
      }
    }
  }

  Widget _buildPatternSetup() {
    final isConfirm = _confirmPattern != null;
    return Column(children: [
      Text(isConfirm ? AppLang.instance.t('confirmPattern') : AppLang.instance.t('newPatternDraw'), style: TextStyle(color: PhotonColors.text, fontSize: 14)),
      const SizedBox(height: 24),
      _PatternGrid(
        selected: _pattern,
        onComplete: (p) {
          if (_confirmPattern == null) {
            setState(() { _confirmPattern = p; _pattern = []; });
          } else {
            if (p.join('-') == _confirmPattern!.join('-')) {
              AppLock.enable('pattern', p.join('-')).then((_) {
                if (!mounted) return;
                widget.onDone();
                Navigator.pop(context);
              });
            } else {
              setState(() { _error = AppLang.instance.t('patternsDontMatch'); _confirmPattern = null; _pattern = []; });
            }
          }
        },
      ),
    ]);
  }
}
