import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../models/models.dart';

class PriceLadder extends ConsumerStatefulWidget {
  final int instrumentId;
  final Function(double price, bool isBid)? onPriceClick;
  
  const PriceLadder({
    Key? key,
    required this.instrumentId,
    this.onPriceClick,
  }) : super(key: key);

  @override
  ConsumerState<PriceLadder> createState() => _PriceLadderState();
}

class _PriceLadderState extends ConsumerState<PriceLadder> {
  static const int _visibleLevels = 40;
  double? _lockedCenterPrice;
  double? _lastTickSize;
  bool _hasInitializedCenter = false;
  
  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(webSocketProvider);
    final instrument = ws.instruments.firstWhere((i) => i.id == widget.instrumentId);
    final md = ws.marketData[widget.instrumentId];
    
    if (_lastTickSize != null && _lastTickSize != instrument.tickSize) {
      _lockedCenterPrice = null;
      _hasInitializedCenter = false;
    }
    _lastTickSize = instrument.tickSize;
    
    // Generate price levels
    final levels = _generatePriceLevels(md, instrument.tickSize);
    
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  instrument.symbol,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(instrument.type),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Spacer(),
                if (md?.lastPrice != null)
                  Text(
                    'Last: \$${md!.lastPrice!.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
              ],
            ),
          ),
          
          // Column headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Text(
                    'My Bids',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.green.shade300),
                  ),
                ),
                const SizedBox(width: 2),
                const Expanded(
                  flex: 2,
                  child: Text('Bid', textAlign: TextAlign.center),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  flex: 2,
                  child: Text('Price', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  flex: 2,
                  child: Text('Ask', textAlign: TextAlign.center),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: 1,
                  child: Text(
                    'My Asks',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.red.shade300),
                  ),
                ),
              ],
            ),
          ),
          
          // Price ladder
          Expanded(
            child: ListView.builder(
              itemCount: levels.length,
              itemBuilder: (context, index) {
                final priceAtThisRow = levels[index];
                final level = priceAtThisRow;
                final bidSize = _getSizeAtLevel(md?.bids, priceAtThisRow);
                final askSize = _getSizeAtLevel(md?.asks, priceAtThisRow);
                final isBestBid = md?.bestBid == level;
                final isBestAsk = md?.bestAsk == level;
                
                final myOrders = ws.orders.where((o) => 
                  o.instrumentId == widget.instrumentId && 
                  o.status == 'active' &&
                  (o.price - priceAtThisRow).abs() < 0.001
                ).toList();
                
                final myBidSize = myOrders
                    .where((o) => o.side == 'buy')
                    .fold<int>(0, (sum, o) => sum + (o.qty - o.filledQty));
                
                final myAskSize = myOrders
                    .where((o) => o.side == 'sell')
                    .fold<int>(0, (sum, o) => sum + (o.qty - o.filledQty));
                
                return Container(
                  key: ValueKey('price_row_${priceAtThisRow.toStringAsFixed(2)}'),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBestBid
                        ? Colors.green.withOpacity(0.1)
                        : isBestAsk
                            ? Colors.red.withOpacity(0.1)
                            : null,
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // My Bids - show MY buy orders at this level
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          alignment: Alignment.center,
                          child: Text(
                            myBidSize > 0 ? '$myBidSize' : '',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade300,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 2),
                      
                      // Bid size - clickable (LEFT SIDE = PLACE BUY ORDER)
                      Expanded(
                        flex: 2,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              // Capture the price at the moment of click from the row variable
                              debugPrint('🟢 BUY CLICKED:');
                              debugPrint('   Displayed text should show: \$${priceAtThisRow.toStringAsFixed(2)}');
                              debugPrint('   Sending price: \$${priceAtThisRow.toStringAsFixed(6)}');
                              debugPrint('   If these don\'t match what you SEE, there\'s a render bug!');
                              widget.onPriceClick?.call(priceAtThisRow, false);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                              alignment: Alignment.centerRight,
                              decoration: bidSize > 0 ? BoxDecoration(
                                color: Colors.green.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(2),
                              ) : null,
                              child: bidSize > 0 ? Text(
                                '$bidSize',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ) : null,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 4),
                      
                      // Price - non-clickable display
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          decoration: BoxDecoration(
                            color: isBestBid || isBestAsk
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '\$${level.toStringAsFixed(2)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: isBestBid || isBestAsk
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 4),
                      
                      // Ask size - clickable (RIGHT SIDE = PLACE SELL ORDER)
                      Expanded(
                        flex: 2,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              // Capture the price at the moment of click from the row variable
                              debugPrint('🔴 SELL CLICKED:');
                              debugPrint('   Displayed text should show: \$${priceAtThisRow.toStringAsFixed(2)}');
                              debugPrint('   Sending price: \$${priceAtThisRow.toStringAsFixed(6)}');
                              debugPrint('   If these don\'t match what you SEE, there\'s a render bug!');
                              widget.onPriceClick?.call(priceAtThisRow, true);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                              alignment: Alignment.centerLeft,
                              decoration: askSize > 0 ? BoxDecoration(
                                color: Colors.red.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(2),
                              ) : null,
                              child: askSize > 0 ? Text(
                                '$askSize',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ) : null,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 2),
                      
                      // My Asks - show MY sell orders at this level
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          alignment: Alignment.center,
                          child: Text(
                            myAskSize > 0 ? '$myAskSize' : '',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade300,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  double _roundToTick(double price, double tickSize) {
    return (price / tickSize).round() * tickSize;
  }
  
  List<double> _generatePriceLevels(MarketData? md, double tickSize) {
    double roundPrice(double p) => _roundToTick(p, tickSize);
    
    double? marketCenter;
    if (md != null && md.bestBid != null && md.bestAsk != null) {
      marketCenter = (md.bestBid! + md.bestAsk!) / 2;
    } else if (md != null && md.bestBid != null) {
      marketCenter = md.bestBid!;
    } else if (md != null && md.bestAsk != null) {
      marketCenter = md.bestAsk!;
    } else if (md != null && md.lastPrice != null) {
      marketCenter = md.lastPrice!;
    }
    
    final halfLevels = _visibleLevels ~/ 2;
    final minCenter = (halfLevels * tickSize) + tickSize;
    
    double centerPrice;
    if (!_hasInitializedCenter && marketCenter != null) {
      centerPrice = marketCenter < minCenter ? minCenter : marketCenter;
      _lockedCenterPrice = centerPrice;
      _hasInitializedCenter = true;
    } else if (_lockedCenterPrice == null) {
      centerPrice = 100.0 < minCenter ? minCenter : 100.0;
      _lockedCenterPrice = centerPrice;
    } else {
      centerPrice = _lockedCenterPrice!;
    }
    
    final List<double> levels = [];
    for (int i = halfLevels; i >= -halfLevels; i--) {
      final price = roundPrice(centerPrice + (i * tickSize));
      levels.add(price);
    }
    
    return levels;
  }
  
  int _getSizeAtLevel(List<PriceLevel>? levels, double price) {
    if (levels == null) return 0;
    
    for (final level in levels) {
      if ((level.price - price).abs() < 0.001) {
        return level.size;
      }
    }
    return 0;
  }
}

