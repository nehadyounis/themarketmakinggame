import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../widgets/price_ladder.dart';
import '../widgets/positions_panel.dart';

class TradingTerminal extends ConsumerStatefulWidget {
  const TradingTerminal({Key? key}) : super(key: key);

  @override
  ConsumerState<TradingTerminal> createState() => _TradingTerminalState();
}

class _TradingTerminalState extends ConsumerState<TradingTerminal> {
  int? _selectedInstrument;
  final FocusNode _keyboardFocus = FocusNode();
  final Set<int> _seenInstruments = {};
  
  @override
  void initState() {
    super.initState();
    
    // Request keyboard focus for hotkeys
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocus.requestFocus();
    });
    
    // Listen for instrument_added messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ws = ref.read(webSocketProvider);
      ws.messages.listen((msg) {
        if (msg['type'] == 'instrument_added') {
          final instData = msg['instrument'] as Map<String, dynamic>;
          final instId = instData['id'] as int;
          final symbol = instData['symbol'] as String;
          
          // Show market opening modal for new instruments
          if (!_seenInstruments.contains(instId)) {
            _seenInstruments.add(instId);
            
            // Delay slightly to ensure market data is loaded
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                _showMarketOpeningDialog(instId, symbol);
              }
            });
          }
        }
      });
    });
  }
  
  void _handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    
    final ws = ref.read(webSocketProvider);
    
    // Cancel all orders on ESC
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      ws.cancelAll();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(webSocketProvider);
    
    if (!ws.isConnected || ws.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/');
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return KeyboardListener(
      focusNode: _keyboardFocus,
      onKeyEvent: _handleKeyPress,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.trending_up),
              const SizedBox(width: 8),
              const Text('Trading Terminal'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ws.roomCode ?? "",
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: ws.roomCode ?? ""));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Room code ${ws.roomCode} copied!'),
                            duration: const Duration(seconds: 1),
                            backgroundColor: Colors.green.shade700,
                          ),
                        );
                      },
                      child: const Icon(Icons.copy, size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'PnL: \$${ws.totalPnl.toStringAsFixed(2)}',
                style: TextStyle(
                  color: ws.totalPnl >= 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.clear_all, size: 20),
              label: const Text('Pull My Orders'),
              onPressed: () => ws.cancelAll(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.leaderboard),
              onPressed: () => context.go('/leaderboard'),
              tooltip: 'Leaderboard',
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () {
                ws.disconnect();
                context.go('/');
              },
              tooltip: 'Leave',
            ),
          ],
        ),
        body: ws.instruments.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_empty, size: 64),
                    SizedBox(height: 16),
                    Text('Waiting for exchange to add instruments...'),
                  ],
                ),
              )
            : Row(
                children: [
                  // Left sidebar - Instrument list
                  SizedBox(
                    width: 250,
                    child: Card(
                      margin: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Instruments',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.builder(
                              itemCount: ws.instruments.length,
                              itemBuilder: (context, index) {
                                final inst = ws.instruments[index];
                                final md = ws.marketData[inst.id];
                                final isSelected = _selectedInstrument == inst.id;
                                
                                return ListTile(
                                  selected: isSelected,
                                  title: Text(inst.symbol),
                                  subtitle: Text(inst.type),
                                  trailing: md != null
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${md.bestBid?.toStringAsFixed(2) ?? "-"} / ${md.bestAsk?.toStringAsFixed(2) ?? "-"}',
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                            if (md.lastPrice != null)
                                              Text(
                                                'Last: ${md.lastPrice!.toStringAsFixed(2)}',
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                          ],
                                        )
                                      : const Text('-'),
                                  onTap: () {
                                    setState(() {
                                      _selectedInstrument = inst.id;
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Center - Price ladder
                  Expanded(
                    flex: 2,
                    child: _selectedInstrument != null
                        ? Column(
                            children: [
                              // Instrument-specific controls
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[900],
                                  border: Border(
                                    bottom: BorderSide(color: Colors.grey[800]!),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      ws.instruments
                                          .firstWhere((i) => i.id == _selectedInstrument)
                                          .symbol,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        // Get all my orders for this instrument
                                        final myOrders = ws.orders
                                            .where((o) => o.instrumentId == _selectedInstrument)
                                            .map((o) => o.orderId)
                                            .toList();
                                        
                                        if (myOrders.isEmpty) {
                                          // Just call cancel_all as fallback
                                          ws.cancelAll();
                                        } else {
                                          // Send cancel_inst message with order IDs
                                          ws.send({
                                            'op': 'cancel_inst',
                                            'inst': _selectedInstrument,
                                            'order_ids': myOrders,
                                          });
                                        }
                                      },
                                      icon: const Icon(Icons.clear_all, size: 16),
                                      label: const Text('Pull My Quotes'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange[700],
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: PriceLadder(
                                  instrumentId: _selectedInstrument!,
                                  onPriceClick: (price, isSell) {
                                    // isSell=true means right side (ASK), isSell=false means left side (BID)
                                    _placeQuickOrder(price, isSell ? 'sell' : 'buy');
                                  },
                                ),
                              ),
                            ],
                          )
                        : const Center(
                            child: Text('Select an instrument'),
                          ),
                  ),
                  
                  // Right sidebar - Positions and orders
                  SizedBox(
                    width: 350,
                    child: PositionsPanel(),
                  ),
                ],
              ),
      ),
    );
  }
  
  void _placeQuickOrder(double price, String side) {
    if (_selectedInstrument == null) return;
    
    final ws = ref.read(webSocketProvider);
    final instrument = ws.instruments.firstWhere((i) => i.id == _selectedInstrument);
    
    // Round price to tick size to avoid floating point issues
    final tickSize = instrument.tickSize;
    final roundedPrice = (price / tickSize).round() * tickSize;
    
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🔴 QUICK ORDER PLACEMENT:');
    debugPrint('   Side: ${side.toUpperCase()}');
    debugPrint('   Price received: \$${price.toStringAsFixed(6)}');
    debugPrint('   Price rounded: \$${roundedPrice.toStringAsFixed(6)}');
    debugPrint('   Instrument: ${instrument.symbol} (ID: $_selectedInstrument)');
    debugPrint('   Tick Size: ${instrument.tickSize}');
    debugPrint('   Lot Size: ${instrument.lotSize}');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    // Place limit order for 1 lot
    ws.submitOrder(
      instrumentId: _selectedInstrument!,
      side: side,
      price: roundedPrice,
      qty: instrument.lotSize,
      tif: 'GFD',  // Good for day only
      postOnly: false,
    );
    
    // No snackbar feedback - keep UI clean
  }
  
  void _showMarketOpeningDialog(int instrumentId, String symbol) {
    final bidController = TextEditingController();
    final askController = TextEditingController();
    final qtyController = TextEditingController(text: '10');
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.rocket_launch, color: Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Open the Market'),
                  Text(
                    symbol,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This instrument has no orders yet. Be the first to provide liquidity by placing an initial bid and ask!',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bidController,
                      decoration: InputDecoration(
                        labelText: 'Bid Price',
                        prefixText: '\$',
                        border: const OutlineInputBorder(),
                        hintText: '99.00',
                        filled: true,
                        fillColor: Colors.green.withOpacity(0.1),
                      ),
                      keyboardType: TextInputType.number,
                      autofocus: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: askController,
                      decoration: InputDecoration(
                        labelText: 'Ask Price',
                        prefixText: '\$',
                        border: const OutlineInputBorder(),
                        hintText: '101.00',
                        filled: true,
                        fillColor: Colors.red.withOpacity(0.1),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyController,
                decoration: const InputDecoration(
                  labelText: 'Quantity (each side)',
                  border: OutlineInputBorder(),
                  hintText: '10',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Text(
                'This will place two orders: BUY at bid price and SELL at ask price.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip'),
          ),
          FilledButton.icon(
            onPressed: () {
              final bidPrice = double.tryParse(bidController.text);
              final askPrice = double.tryParse(askController.text);
              final qty = int.tryParse(qtyController.text);
              
              if (bidPrice != null && askPrice != null && qty != null && qty > 0) {
                if (bidPrice >= askPrice) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bid must be lower than ask')),
                  );
                  return;
                }
                
                final ws = ref.read(webSocketProvider);
                
                // Place bid (buy order)
                ws.submitOrder(
                  instrumentId: instrumentId,
                  side: 'buy',
                  price: bidPrice,
                  qty: qty,
                  tif: 'GFD',
                  postOnly: true,
                );
                
                // Place ask (sell order)
                ws.submitOrder(
                  instrumentId: instrumentId,
                  side: 'sell',
                  price: askPrice,
                  qty: qty,
                  tif: 'GFD',
                  postOnly: true,
                );
                
                Navigator.pop(context);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Market opened for $symbol!'),
                    backgroundColor: Colors.green.shade700,
                  ),
                );
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Open Market'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }
}

