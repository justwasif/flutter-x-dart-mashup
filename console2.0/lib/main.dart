import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const HidGamepadApp());
}

class HidGamepadApp extends StatelessWidget {
  const HidGamepadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HID Gamepad',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2fbf71),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101416),
      ),
      home: const GamepadScreen(),
    );
  }
}

class GamepadScreen extends StatefulWidget {
  const GamepadScreen({super.key});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  static const _channel = MethodChannel('hid_gamepad');

  bool _supported = false;
  bool _registered = false;
  bool _connected = false;
  String? _hostName;
  String? _hostAddress;
  String? _message;
  List<BluetoothHost> _hosts = const [];

  int _buttons = 0;
  int _hat = 8;
  int _lx = 0;
  int _ly = 0;
  int _rx = 0;
  int _ry = 0;
  int _lastSentMs = 0;
  Timer? _deferredSend;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'status') {
        _applyStatus(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _deferredSend?.cancel();
    _sendNeutralReport();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    setState(() => _supported = supported);
    if (!supported) {
      setState(() {
        _message = 'Android 9+ with Bluetooth HID Device support is required.';
      });
      return;
    }
    await _channel.invokeMethod<bool>('requestPermissions');
    await _refreshStatus();
    await _refreshHosts();
  }

  Future<void> _start() async {
    try {
      final ok = await _channel.invokeMethod<bool>('start') ?? false;
      setState(() {
        _registered = ok || _registered;
        _message = ok
            ? 'HID mode active. Pair this phone from the desktop.'
            : 'Permission needed, then tap Start again.';
      });
      await _refreshStatus();
      await _refreshHosts();
    } on PlatformException catch (error) {
      setState(() => _message = error.message ?? error.code);
    }
  }

  Future<void> _stop() async {
    await _sendNeutralReport();
    await _channel.invokeMethod<bool>('stop');
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final status = await _channel.invokeMapMethod<String, dynamic>('status');
    if (status != null) _applyStatus(status);
  }

  Future<void> _refreshHosts() async {
    final devices =
        await _channel.invokeListMethod<dynamic>('devices') ?? const [];
    setState(() {
      _hosts = devices
          .map(
            (item) =>
                BluetoothHost.fromMap(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    });
  }

  Future<void> _connect(BluetoothHost host) async {
    try {
      final ok =
          await _channel.invokeMethod<bool>('connect', {
            'address': host.address,
          }) ??
          false;
      setState(
        () => _message = ok
            ? 'Connecting to ${host.name}...'
            : 'Could not connect to ${host.name}.',
      );
    } on PlatformException catch (error) {
      setState(() => _message = error.message ?? error.code);
    }
  }

  void _applyStatus(Map<String, dynamic> status) {
    if (!mounted) return;
    setState(() {
      _registered = status['registered'] == true;
      _connected = status['connected'] == true;
      _hostName = status['hostName'] as String?;
      _hostAddress = status['hostAddress'] as String?;
    });
  }

  void _setButton(int bit, bool pressed) {
    final mask = 1 << bit;
    final next = pressed ? (_buttons | mask) : (_buttons & ~mask);
    if (next == _buttons) return;
    _buttons = next;
    _sendReport();
  }

  void _setDpad({bool? up, bool? right, bool? down, bool? left}) {
    _dpad = _dpad.copyWith(up: up, right: right, down: down, left: left);
    _hat = _dpad.hat;
    _sendReport();
  }

  DpadState _dpad = const DpadState();

  void _setLeftStick(Offset value) {
    _lx = (value.dx * 127).round().clamp(-127, 127);
    _ly = (value.dy * 127).round().clamp(-127, 127);
    _sendReport();
  }

  void _setRightStick(Offset value) {
    _rx = (value.dx * 127).round().clamp(-127, 127);
    _ry = (value.dy * 127).round().clamp(-127, 127);
    _sendReport();
  }

  Future<void> _sendNeutralReport() async {
    _buttons = 0;
    _hat = 8;
    _lx = _ly = _rx = _ry = 0;
    await _channel.invokeMethod<bool>('sendReport', _report);
  }

  void _sendReport() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSentMs >= 8) {
      _lastSentMs = now;
      _channel.invokeMethod<bool>('sendReport', _report);
      return;
    }
    _deferredSend?.cancel();
    _deferredSend = Timer(Duration(milliseconds: 8 - (now - _lastSentMs)), () {
      _lastSentMs = DateTime.now().millisecondsSinceEpoch;
      _channel.invokeMethod<bool>('sendReport', _report);
    });
  }

  Map<String, int> get _report => {
    'buttons': _buttons,
    'hat': _hat,
    'lx': _lx,
    'ly': _ly,
    'rx': _rx,
    'ry': _ry,
  };

  @override
  Widget build(BuildContext context) {
    final status = _connected
        ? 'Connected: ${_hostName ?? _hostAddress ?? 'desktop'}'
        : _registered
        ? 'HID active'
        : 'Offline';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _TopBar(
                status: status,
                message: _message,
                supported: _supported,
                registered: _registered,
                onStart: _start,
                onStop: _stop,
                onOpenSettings: () =>
                    _channel.invokeMethod<bool>('openBluetoothSettings'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _LeftControls(
                        onStick: _setLeftStick,
                        onDpad: _setDpad,
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: _CenterPanel(
                        hosts: _hosts,
                        onRefresh: _refreshHosts,
                        onConnect: _connect,
                        onSelect: (pressed) => _setButton(8, pressed),
                        onStart: (pressed) => _setButton(9, pressed),
                      ),
                    ),
                    Expanded(
                      child: _RightControls(
                        onStick: _setRightStick,
                        onButton: _setButton,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.status,
    required this.message,
    required this.supported,
    required this.registered,
    required this.onStart,
    required this.onStop,
    required this.onOpenSettings,
  });

  final String status;
  final String? message;
  final bool supported;
  final bool registered;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.sports_esports, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(status, style: Theme.of(context).textTheme.titleMedium),
              if (message != null)
                Text(
                  message!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Bluetooth settings',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.bluetooth),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: supported ? (registered ? onStop : onStart) : null,
          icon: Icon(registered ? Icons.stop : Icons.play_arrow),
          label: Text(registered ? 'Stop' : 'Start'),
        ),
      ],
    );
  }
}

class _LeftControls extends StatelessWidget {
  const _LeftControls({required this.onStick, required this.onDpad});

  final ValueChanged<Offset> onStick;
  final void Function({bool? up, bool? right, bool? down, bool? left}) onDpad;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        VirtualStick(label: 'L', onChanged: onStick),
        _Dpad(onChanged: onDpad),
      ],
    );
  }
}

class _RightControls extends StatelessWidget {
  const _RightControls({required this.onStick, required this.onButton});

  final ValueChanged<Offset> onStick;
  final void Function(int bit, bool pressed) onButton;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _FaceButtons(onButton: onButton),
        VirtualStick(label: 'R', onChanged: onStick),
      ],
    );
  }
}

class _CenterPanel extends StatelessWidget {
  const _CenterPanel({
    required this.hosts,
    required this.onRefresh,
    required this.onConnect,
    required this.onSelect,
    required this.onStart,
  });

  final List<BluetoothHost> hosts;
  final VoidCallback onRefresh;
  final ValueChanged<BluetoothHost> onConnect;
  final ValueChanged<bool> onSelect;
  final ValueChanged<bool> onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HoldButton(label: 'SELECT', onChanged: onSelect, compact: true),
            const SizedBox(width: 10),
            HoldButton(label: 'START', onChanged: onStart, compact: true),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xff171d20),
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Paired hosts')),
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: hosts.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                              'Pair the desktop in Android Bluetooth settings.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: hosts.length,
                          itemBuilder: (context, index) {
                            final host = hosts[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                host.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(host.address),
                              trailing: const Icon(Icons.cable),
                              onTap: () => onConnect(host),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class VirtualStick extends StatefulWidget {
  const VirtualStick({super.key, required this.label, required this.onChanged});

  final String label;
  final ValueChanged<Offset> onChanged;

  @override
  State<VirtualStick> createState() => _VirtualStickState();
}

class _VirtualStickState extends State<VirtualStick> {
  Offset _value = Offset.zero;

  void _update(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    var delta = (localPosition - center) / radius;
    if (delta.distance > 1) {
      delta = Offset.fromDirection(delta.direction, 1);
    }
    setState(() => _value = delta);
    widget.onChanged(delta);
  }

  void _release() {
    setState(() => _value = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 156,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => _update(details.localPosition, size),
            onPanUpdate: (details) => _update(details.localPosition, size),
            onPanEnd: (_) => _release(),
            onPanCancel: _release,
            child: CustomPaint(painter: _StickPainter(_value, widget.label)),
          );
        },
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  const _StickPainter(this.value, this.label);

  final Offset value;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final base = Paint()..color = const Color(0xff20282b);
    final ring = Paint()
      ..color = const Color(0xff526067)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final accent = Paint()..color = const Color(0xff2fbf71);
    final knob = center + value * (radius * 0.48);

    canvas.drawCircle(center, radius, base);
    canvas.drawCircle(center, radius - 1, ring);
    canvas.drawCircle(knob, radius * 0.38, accent);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xff101416),
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      knob - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _StickPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.label != label;
  }
}

class _Dpad extends StatelessWidget {
  const _Dpad({required this.onChanged});

  final void Function({bool? up, bool? right, bool? down, bool? left})
  onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            child: HoldIcon(
              icon: Icons.keyboard_arrow_up,
              onChanged: (v) => onChanged(up: v),
            ),
          ),
          Positioned(
            right: 0,
            child: HoldIcon(
              icon: Icons.keyboard_arrow_right,
              onChanged: (v) => onChanged(right: v),
            ),
          ),
          Positioned(
            bottom: 0,
            child: HoldIcon(
              icon: Icons.keyboard_arrow_down,
              onChanged: (v) => onChanged(down: v),
            ),
          ),
          Positioned(
            left: 0,
            child: HoldIcon(
              icon: Icons.keyboard_arrow_left,
              onChanged: (v) => onChanged(left: v),
            ),
          ),
          const SizedBox.square(
            dimension: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xff20282b),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceButtons extends StatelessWidget {
  const _FaceButtons({required this.onButton});

  final void Function(int bit, bool pressed) onButton;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            child: HoldButton(label: 'Y', onChanged: (v) => onButton(3, v)),
          ),
          Positioned(
            right: 0,
            child: HoldButton(label: 'B', onChanged: (v) => onButton(1, v)),
          ),
          Positioned(
            bottom: 0,
            child: HoldButton(label: 'A', onChanged: (v) => onButton(0, v)),
          ),
          Positioned(
            left: 0,
            child: HoldButton(label: 'X', onChanged: (v) => onButton(2, v)),
          ),
          Positioned(
            top: 58,
            left: 58,
            child: HoldButton(
              label: 'LB',
              onChanged: (v) => onButton(4, v),
              compact: true,
            ),
          ),
          Positioned(
            bottom: 58,
            right: 58,
            child: HoldButton(
              label: 'RB',
              onChanged: (v) => onButton(5, v),
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class HoldIcon extends StatelessWidget {
  const HoldIcon({super.key, required this.icon, required this.onChanged});

  final IconData icon;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _HoldSurface(
      onChanged: onChanged,
      size: 58,
      child: Icon(icon, size: 34),
    );
  }
}

class HoldButton extends StatelessWidget {
  const HoldButton({
    super.key,
    required this.label,
    required this.onChanged,
    this.compact = false,
  });

  final String label;
  final ValueChanged<bool> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _HoldSurface(
      onChanged: onChanged,
      size: compact ? 54 : 66,
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 13 : 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _HoldSurface extends StatefulWidget {
  const _HoldSurface({
    required this.onChanged,
    required this.size,
    required this.child,
  });

  final ValueChanged<bool> onChanged;
  final double size;
  final Widget child;

  @override
  State<_HoldSurface> createState() => _HoldSurfaceState();
}

class _HoldSurfaceState extends State<_HoldSurface> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    widget.onChanged(pressed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xff2fbf71) : const Color(0xff20282b),
          shape: BoxShape.circle,
          border: Border.all(
            color: _pressed ? const Color(0xffa8f0c6) : Colors.white12,
          ),
          boxShadow: _pressed
              ? [
                  BoxShadow(
                    color: const Color(0xff2fbf71).withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

class DpadState {
  const DpadState({
    this.up = false,
    this.right = false,
    this.down = false,
    this.left = false,
  });

  final bool up;
  final bool right;
  final bool down;
  final bool left;

  int get hat {
    if (up && right) return 1;
    if (right && down) return 3;
    if (down && left) return 5;
    if (left && up) return 7;
    if (up) return 0;
    if (right) return 2;
    if (down) return 4;
    if (left) return 6;
    return 8;
  }

  DpadState copyWith({bool? up, bool? right, bool? down, bool? left}) {
    return DpadState(
      up: up ?? this.up,
      right: right ?? this.right,
      down: down ?? this.down,
      left: left ?? this.left,
    );
  }
}

class BluetoothHost {
  const BluetoothHost({required this.name, required this.address});

  final String name;
  final String address;

  factory BluetoothHost.fromMap(Map<String, dynamic> map) {
    return BluetoothHost(
      name: map['name'] as String? ?? 'Unknown device',
      address: map['address'] as String? ?? '',
    );
  }
}
