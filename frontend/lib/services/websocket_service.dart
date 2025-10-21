import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _marketDataController = StreamController<MarketData>.broadcast();
  final _fillController = StreamController<Fill>.broadcast();
  
  bool _isConnected = false;
  User? _currentUser;
  String? _roomCode;
  
  final Map<int, Instrument> _instruments = {};
  final Map<int, MarketData> _marketData = {};
  final Map<int, Position> _positions = {};
  final Map<int, Order> _orders = {}; // order_id -> Order
  double _totalPnl = 0.0;
  
  bool get isConnected => _isConnected;
  User? get currentUser => _currentUser;
  String? get roomCode => _roomCode;
  List<Instrument> get instruments => _instruments.values.toList();
  Map<int, MarketData> get marketData => _marketData;
  List<Position> get positions => _positions.values.toList();
  List<Order> get orders => _orders.values.toList();
  double get totalPnl => _totalPnl;
  
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<MarketData> get marketDataStream => _marketDataController.stream;
  Stream<Fill> get fillStream => _fillController.stream;
  
  void connect(String url) {
    try {
      debugPrint('🔌 Connecting to WebSocket: $url');
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;
      notifyListeners();
      debugPrint('✅ WebSocket connected, notifying listeners');
      
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          _handleMessage(data);
        },
        onDone: () {
          debugPrint('❌ WebSocket connection closed');
          _isConnected = false;
          notifyListeners();
        },
        onError: (error) {
          debugPrint('❌ WebSocket error: $error');
          _isConnected = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('❌ Connection error: $e');
      _isConnected = false;
      notifyListeners();
    }
  }
  
  void _handleMessage(Map<String, dynamic> data) {
    _messageController.add(data);
    
    final type = data['type'] as String?;
    
    switch (type) {
      case 'join_ack':
        _currentUser = User(
          userId: data['user_id'] as int,
          name: '',
          role: data['role'] as String,
          resumeToken: data['resume_token'] as String,
        );
        _roomCode = data['room_code'] as String;
        
        // Load instruments
        final instList = data['instruments'] as List?;
        if (instList != null) {
          for (final inst in instList) {
            final instrument = Instrument.fromJson(inst);
            _instruments[instrument.id] = instrument;
          }
        }
        notifyListeners();
        break;
        
      case 'instrument_added':
        final instrument = Instrument.fromJson(data['instrument']);
        _instruments[instrument.id] = instrument;
        notifyListeners();
        break;
        
      case 'md_inc':
        final md = MarketData.fromJson(data);
        _marketData[md.instrumentId] = md;
        _marketDataController.add(md);
        notifyListeners();
        break;
        
      case 'fill':
        final fill = Fill.fromJson(data);
        _fillController.add(fill);
        
        // Update or remove the filled order
        final orderId = fill.orderId;
        if (_orders.containsKey(orderId)) {
          final order = _orders[orderId]!;
          final newFilledQty = order.filledQty + fill.qty;
          
          if (newFilledQty >= order.qty) {
            // Fully filled - remove from orders
            _orders.remove(orderId);
            debugPrint('🗑️ Order $orderId fully filled, removed from My Bids/Asks');
          } else {
            // Partially filled - update
            _orders[orderId] = Order(
              orderId: order.orderId,
              instrumentId: order.instrumentId,
              side: order.side,
              price: order.price,
              qty: order.qty,
              filledQty: newFilledQty,
              status: order.status,
              timestamp: order.timestamp,
            );
            debugPrint('📊 Order $orderId partially filled: $newFilledQty/${order.qty}');
          }
        }
        
        notifyListeners();
        break;
        
      case 'positions':
        _positions.clear();
        final posList = data['positions'] as List;
        for (final pos in posList) {
          final position = Position.fromJson(pos);
          _positions[position.instrumentId] = position;
        }
        notifyListeners();
        break;
        
      case 'pnl':
        _totalPnl = (data['pnl'] as num).toDouble();
        notifyListeners();
        break;
        
      case 'order_ack':
        // Order was accepted - replace temp order with real one
        final realOrderId = data['order_id'] as int;
        final instId = data['inst'] as int;
        final side = data['side'] as String;
        final price = (data['price'] as num).toDouble();
        
        // Find and update the temp order - match by inst, side, AND price
        final tempOrders = _orders.entries.where((e) => 
          e.value.instrumentId == instId && 
          e.value.side == side &&
          (e.value.price - price).abs() < 0.001 &&
          e.value.status == 'pending'
        ).toList();
        
        if (tempOrders.isNotEmpty) {
          final tempEntry = tempOrders.first;
          final tempOrder = tempEntry.value;
          
          // Remove temp order
          _orders.remove(tempEntry.key);
          
          // Add real order
          _orders[realOrderId] = Order(
            orderId: realOrderId,
            instrumentId: tempOrder.instrumentId,
            side: tempOrder.side,
            price: tempOrder.price,
            qty: tempOrder.qty,
            filledQty: 0,
            status: 'active',
            timestamp: tempOrder.timestamp,
          );
          
          debugPrint('✅ Order ACK: $realOrderId $side @\$${price.toStringAsFixed(2)} (replaced temp ${tempEntry.key})');
          notifyListeners();
        } else {
          debugPrint('⚠️ Order ACK: No matching temp order found for $side @\$${price.toStringAsFixed(2)}');
        }
        break;
        
      case 'cancel_ack':
        // Remove cancelled order
        final orderId = data['order_id'] as int;
        _orders.remove(orderId);
        notifyListeners();
        break;
        
      case 'cancel_all_ack':
        // Remove all orders
        _orders.clear();
        notifyListeners();
        break;
        
      case 'cancel_inst_ack':
        // Remove all orders for a specific instrument
        final instId = data['inst'] as int;
        _orders.removeWhere((orderId, order) => order.instrumentId == instId);
        debugPrint('📝 Cancelled ${data['cancelled']} orders for instrument $instId');
        notifyListeners();
        break;
        
      case 'quotes_pulled':
        final instId = data['inst'] as int;
        _orders.removeWhere((orderId, order) => order.instrumentId == instId);
        notifyListeners();
        break;
        
      case 'tick_size_updated':
        final instId = data['instrument_id'] as int;
        final newTickSize = (data['tick_size'] as num).toDouble();
        
        final inst = _instruments[instId];
        if (inst != null) {
          _instruments[instId] = Instrument(
            id: inst.id,
            symbol: inst.symbol,
            type: inst.type,
            tickSize: newTickSize,
            lotSize: inst.lotSize,
            tickValue: inst.tickValue,
          );
          
          _orders.removeWhere((orderId, order) => order.instrumentId == instId);
          notifyListeners();
        }
        break;
        
      case 'error':
        debugPrint('Server error: ${data['message']}');
        break;
    }
  }
  
  void send(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }
  
  void createRoom({String? passcode}) {
    send({
      'op': 'create_room',
      'passcode': passcode,
    });
  }
  
  void joinRoom(String roomCode, String name, String role, {String? passcode}) {
    send({
      'op': 'join',
      'room': roomCode,
      'name': name,
      'role': role,
      'passcode': passcode,
    });
  }
  
  void ping() {
    send({
      'op': 'ping',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  void addInstrument({
    required String symbol,
    required String type,
    int? referenceId,
    double? strike,
    double tickSize = 0.01,
    int lotSize = 1,
    double tickValue = 1.0,
  }) {
    send({
      'op': 'add_instrument',
      'symbol': symbol,
      'type': type,
      'reference_id': referenceId,
      'strike': strike,
      'tick_size': tickSize,
      'lot_size': lotSize,
      'tick_value': tickValue,
    });
  }
  
  void submitOrder({
    required int instrumentId,
    required String side,
    required double price,
    required int qty,
    String tif = 'GFD',
    bool postOnly = false,
  }) {
    debugPrint('📤 WebSocket: Sending order_new');
    debugPrint('   inst: $instrumentId');
    debugPrint('   side: $side');
    debugPrint('   price: $price');
    debugPrint('   qty: $qty');
    
    // Create a pending order optimistically (will be replaced by server ack)
    final tempOrderId = DateTime.now().millisecondsSinceEpoch; // Temporary ID
    final order = Order(
      orderId: tempOrderId,
      instrumentId: instrumentId,
      side: side,
      price: price,
      qty: qty,
      filledQty: 0,
      status: 'pending',
      timestamp: DateTime.now(),
    );
    _orders[tempOrderId] = order;
    notifyListeners();
    
    send({
      'op': 'order_new',
      'inst': instrumentId,
      'side': side,
      'price': price,
      'qty': qty,
      'tif': tif,
      'post_only': postOnly,
    });
  }
  
  void cancelOrder(int orderId) {
    send({
      'op': 'cancel',
      'order_id': orderId,
    });
  }
  
  void cancelAll() {
    send({
      'op': 'cancel_all',
    });
  }
  
  void settleInstrument(int instrumentId, double value) {
    send({
      'op': 'settle',
      'inst': instrumentId,
      'value': value,
    });
  }
  
  void haltInstrument(int instrumentId, bool halted) {
    send({
      'op': 'halt',
      'inst': instrumentId,
      'on': halted,
    });
  }
  
  void getSnapshot(int instrumentId) {
    send({
      'op': 'get_snapshot',
      'inst': instrumentId,
    });
  }
  
  void getPositions() {
    send({
      'op': 'get_positions',
    });
  }
  
  void getPnL() {
    send({
      'op': 'get_pnl',
    });
  }
  
  void exportData() {
    send({
      'op': 'export_data',
    });
  }
  
  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    _currentUser = null;
    _roomCode = null;
    _instruments.clear();
    _marketData.clear();
    _positions.clear();
    notifyListeners();
  }
  
  @override
  void dispose() {
    _channel?.sink.close();
    _messageController.close();
    _marketDataController.close();
    _fillController.close();
    super.dispose();
  }
}

