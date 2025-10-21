import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/websocket_service.dart';

final webSocketProvider = ChangeNotifierProvider<WebSocketService>((ref) {
  return WebSocketService();
});

