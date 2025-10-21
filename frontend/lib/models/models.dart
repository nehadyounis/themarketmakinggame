// Data models for the application

class Instrument {
  final int id;
  final String symbol;
  final String type; // SCALAR, CALL, PUT
  final int? referenceId;
  final double? strike;
  final double tickSize;
  final int lotSize;
  final double tickValue;
  
  Instrument({
    required this.id,
    required this.symbol,
    required this.type,
    this.referenceId,
    this.strike,
    required this.tickSize,
    required this.lotSize,
    required this.tickValue,
  });
  
  factory Instrument.fromJson(Map<String, dynamic> json) {
    return Instrument(
      id: json['id'] as int,
      symbol: json['symbol'] as String,
      type: json['type'] as String,
      referenceId: json['reference_id'] as int?,
      strike: (json['strike'] as num?)?.toDouble(),
      tickSize: (json['tick_size'] as num).toDouble(),
      lotSize: json['lot_size'] as int,
      tickValue: (json['tick_value'] as num).toDouble(),
    );
  }
}

class PriceLevel {
  final double price;
  final int size;
  
  PriceLevel(this.price, this.size);
  
  factory PriceLevel.fromList(List<dynamic> list) {
    return PriceLevel(
      (list[0] as num).toDouble(),
      (list[1] as num).toInt(),
    );
  }
}

class MarketData {
  final int instrumentId;
  final List<PriceLevel> bids;
  final List<PriceLevel> asks;
  final double? lastPrice;
  final double timestamp;
  
  MarketData({
    required this.instrumentId,
    required this.bids,
    required this.asks,
    this.lastPrice,
    required this.timestamp,
  });
  
  factory MarketData.fromJson(Map<String, dynamic> json) {
    return MarketData(
      instrumentId: json['inst'] as int,
      bids: (json['bids'] as List?)?.map((e) => PriceLevel.fromList(e)).toList() ?? [],
      asks: (json['asks'] as List?)?.map((e) => PriceLevel.fromList(e)).toList() ?? [],
      lastPrice: (json['last'] as num?)?.toDouble(),
      timestamp: (json['ts'] as num).toDouble(),
    );
  }
  
  double? get bestBid => bids.isNotEmpty ? bids.first.price : null;
  double? get bestAsk => asks.isNotEmpty ? asks.first.price : null;
  double? get midPrice {
    if (bestBid != null && bestAsk != null) {
      return (bestBid! + bestAsk!) / 2;
    }
    return null;
  }
}

class Position {
  final int instrumentId;
  final int qty;
  final double vwap;
  final double realizedPnl;
  final double unrealizedPnl;
  
  Position({
    required this.instrumentId,
    required this.qty,
    required this.vwap,
    required this.realizedPnl,
    required this.unrealizedPnl,
  });
  
  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      instrumentId: json['inst'] as int,
      qty: json['qty'] as int,
      vwap: (json['vwap'] as num).toDouble(),
      realizedPnl: (json['realized_pnl'] as num).toDouble(),
      unrealizedPnl: (json['unrealized_pnl'] as num).toDouble(),
    );
  }
  
  double get totalPnl => realizedPnl + unrealizedPnl;
}

class Order {
  final int orderId;
  final int instrumentId;
  final String side; // buy/sell
  final double price;
  final int qty;
  final int filledQty;
  final String status;
  final DateTime timestamp;
  
  Order({
    required this.orderId,
    required this.instrumentId,
    required this.side,
    required this.price,
    required this.qty,
    this.filledQty = 0,
    required this.status,
    required this.timestamp,
  });
}

class Fill {
  final int orderId;
  final int instrumentId;
  final String side;
  final double price;
  final int qty;
  final DateTime timestamp;
  
  Fill({
    required this.orderId,
    required this.instrumentId,
    required this.side,
    required this.price,
    required this.qty,
    required this.timestamp,
  });
  
  factory Fill.fromJson(Map<String, dynamic> json) {
    return Fill(
      orderId: json['order_id'] as int,
      instrumentId: json['inst'] as int,
      side: json['side'] as String,
      price: (json['price'] as num).toDouble(),
      qty: json['qty'] as int,
      timestamp: DateTime.now(),
    );
  }
}

class User {
  final int userId;
  final String name;
  final String role;
  final String resumeToken;
  
  User({
    required this.userId,
    required this.name,
    required this.role,
    required this.resumeToken,
  });
}

