import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/websocket_service.dart';
import '../providers/providers.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final _roomCodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _passcodeController = TextEditingController();
  bool _isCreating = false;
  bool _isJoining = false;
  
  @override
  void initState() {
    super.initState();
    
    // Connect to WebSocket on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ws = ref.read(webSocketProvider);
      if (!ws.isConnected) {
        // Default to localhost, can be configured
        ws.connect('ws://localhost:8000/ws');
      }
      
      // Listen for room created and join ack
      ws.messages.listen((msg) {
        if (msg['type'] == 'room_created') {
          final roomCode = msg['room_code'] as String;
          setState(() {
            _roomCodeController.text = roomCode;
            _isCreating = false;
          });
          
          // Auto-join as exchange after creating room
          ws.joinRoom(
            roomCode,
            _nameController.text,
            'exchange',
            passcode: _passcodeController.text.isEmpty ? null : _passcodeController.text,
          );
        } else if (msg['type'] == 'join_ack') {
          final role = msg['role'] as String;
          if (role == 'exchange') {
            context.go('/exchange');
          } else {
            context.go('/trading');
          }
        } else if (msg['type'] == 'error') {
          setState(() {
            _isCreating = false;
            _isJoining = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg['message'] ?? 'Error occurred')),
          );
        }
      });
    });
  }
  
  void _createRoom() {
    final ws = ref.read(webSocketProvider);
    
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }
    
    setState(() => _isCreating = true);
    
    // Create room first
    ws.createRoom(passcode: _passcodeController.text.isEmpty ? null : _passcodeController.text);
  }
  
  void _joinRoom() {
    final ws = ref.read(webSocketProvider);
    
    if (_roomCodeController.text.isEmpty || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter room code and name')),
      );
      return;
    }
    
    setState(() => _isJoining = true);
    
    // Join as trader (everyone who joins is a player)
    ws.joinRoom(
      _roomCodeController.text.toUpperCase(),
      _nameController.text,
      'trader',
      passcode: _passcodeController.text.isEmpty ? null : _passcodeController.text,
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(webSocketProvider);
    
    // Debug: Print connection state
    debugPrint('🔍 Lobby build - isConnected: ${ws.isConnected}');
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.1),
              Theme.of(context).colorScheme.secondary.withOpacity(0.1),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(
                            'Market Making Game',
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Real-time multiplayer trading simulation',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          
                          // Connection status
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                ws.isConnected ? Icons.circle : Icons.circle_outlined,
                                color: ws.isConnected ? Colors.green : Colors.red,
                                size: 12,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                ws.isConnected ? 'Connected to Server' : 'Connecting...',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Your Name',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                              hintText: 'Enter your display name',
                            ),
                            onChanged: (value) {
                              setState(() {});  // Trigger rebuild to enable/disable buttons
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Two columns for desktop, stacked for mobile
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 600;
                      
                      if (isMobile) {
                        return Column(
                          children: [
                            _buildHostCard(context, ws),
                            const SizedBox(height: 16),
                            _buildJoinCard(context, ws),
                          ],
                        );
                      }
                      
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildHostCard(context, ws)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildJoinCard(context, ws)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildHostCard(BuildContext context, WebSocketService ws) {
    return Card(
      elevation: 8,
      color: Colors.green.shade900.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.stars, color: Colors.green.shade400, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Host as Exchange',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade400,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Create a new game room and control the market:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '• List instruments\n• Adjust tick sizes\n• Monitor all traders\n• View real-time P&L',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            
            TextField(
              controller: _passcodeController,
              decoration: InputDecoration(
                labelText: 'Room Passcode (optional)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                filled: true,
                fillColor: Colors.black.withOpacity(0.2),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            
            FilledButton.icon(
              onPressed: ws.isConnected && !_isCreating && !_isJoining && _nameController.text.isNotEmpty 
                  ? _createRoom 
                  : null,
              icon: _isCreating 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_circle, size: 24),
              label: Text(
                _isCreating ? 'Creating Room...' : 'Create & Host Game',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                backgroundColor: Colors.green.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinCard(BuildContext context, WebSocketService ws) {
    return Card(
      elevation: 8,
      color: Colors.blue.shade900.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: Colors.blue.shade400, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Join as Trader',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade400,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Join an existing game room and trade:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '• View order books\n• Click to place orders\n• Manage positions\n• Track your P&L',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            
            TextField(
              controller: _roomCodeController,
              decoration: InputDecoration(
                labelText: 'Room Code',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.meeting_room),
                hintText: 'e.g., ABC123',
                filled: true,
                fillColor: Colors.black.withOpacity(0.2),
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: (value) {
                setState(() {});  // Trigger rebuild to enable/disable button
              },
              onSubmitted: (_) {
                if (_roomCodeController.text.isNotEmpty && _nameController.text.isNotEmpty) {
                  _joinRoom();
                }
              },
            ),
            const SizedBox(height: 16),
            
            FilledButton.icon(
              onPressed: ws.isConnected && !_isCreating && !_isJoining && 
                         _nameController.text.isNotEmpty && _roomCodeController.text.isNotEmpty
                  ? _joinRoom 
                  : null,
              icon: _isJoining
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.login, size: 24),
              label: Text(
                _isJoining ? 'Joining Room...' : 'Join Game as Trader',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                backgroundColor: Colors.blue.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _roomCodeController.dispose();
    _nameController.dispose();
    _passcodeController.dispose();
    super.dispose();
  }
}

