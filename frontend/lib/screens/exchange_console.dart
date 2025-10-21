import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';

class ExchangeConsole extends ConsumerStatefulWidget {
  const ExchangeConsole({Key? key}) : super(key: key);

  @override
  ConsumerState<ExchangeConsole> createState() => _ExchangeConsoleState();
}

class _ExchangeConsoleState extends ConsumerState<ExchangeConsole> {
  int? _selectedInstrumentId;
  
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
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings),
            const SizedBox(width: 8),
            const Text('Exchange Console'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Room: ',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
                  ),
                  Text(
                    ws.roomCode ?? "",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: ws.roomCode ?? ""));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Room code ${ws.roomCode} copied to clipboard!'),
                          duration: const Duration(seconds: 2),
                          backgroundColor: Colors.green.shade700,
                        ),
                      );
                    },
                    child: const Icon(Icons.copy, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
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
      body: Column(
        children: [
          // Top section: Instruments and order books
          Expanded(
            flex: 2,
            child: Row(
              children: [
                // Left: Instrument list
                SizedBox(
                  width: 300,
                  child: Card(
                    margin: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Text(
                                'Instruments',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.add_circle),
                                onPressed: () => _showAddInstrumentDialog(),
                                tooltip: 'Add Instrument',
                                color: Colors.green,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ws.instruments.isEmpty
                              ? const Center(child: Text('No instruments'))
                              : ListView.builder(
                                  itemCount: ws.instruments.length,
                                  itemBuilder: (context, index) {
                                    final inst = ws.instruments[index];
                                    final isSelected = _selectedInstrumentId == inst.id;
                                    
                                    return ListTile(
                                      selected: isSelected,
                                      title: Text(inst.symbol),
                                      subtitle: Text(inst.type),
                                      trailing: Text('\$${inst.tickSize.toStringAsFixed(2)}'),
                                      onTap: () {
                                        setState(() {
                                          _selectedInstrumentId = inst.id;
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
                
                // Middle: Order book for selected instrument
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.all(8),
                    child: _selectedInstrumentId == null
                        ? const Center(child: Text('Select an instrument to view order book'))
                        : _buildOrderBookView(_selectedInstrumentId!),
                  ),
                ),
                
                // Right: Instrument controls
                SizedBox(
                  width: 280,
                  child: Card(
                    margin: const EdgeInsets.all(8),
                    child: _selectedInstrumentId == null
                        ? const Center(child: Text('Select an instrument'))
                        : _buildInstrumentControls(_selectedInstrumentId!),
                  ),
                ),
              ],
            ),
          ),
          
          // Bottom section: Trader monitor
          Expanded(
            flex: 1,
            child: Card(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.people, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Live Trader Monitor',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () => ws.exportData(),
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Export Data'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _buildTraderMonitor(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildOrderBookView(int instrumentId) {
    final ws = ref.watch(webSocketProvider);
    final instrument = ws.instruments.firstWhere((i) => i.id == instrumentId);
    final md = ws.marketData[instrumentId];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                instrument.symbol,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Order Book',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
              if (md != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Last: ', style: TextStyle(color: Colors.grey.shade600)),
                    Text(
                      md.lastPrice != null ? '\$${md.lastPrice!.toStringAsFixed(2)}' : '-',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(width: 24),
                    Text('Spread: ', style: TextStyle(color: Colors.grey.shade600)),
                    Text(
                      md.bestBid != null && md.bestAsk != null 
                          ? '\$${(md.bestAsk! - md.bestBid!).toStringAsFixed(2)}'
                          : '-',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: md == null || (md.bids.isEmpty && md.asks.isEmpty)
              ? const Center(child: Text('No orders in book'))
              : Row(
                  children: [
                    // Bids
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            color: Colors.green.withOpacity(0.2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text('Price', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('Size', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              reverse: true,
                              itemCount: md.bids.length,
                              itemBuilder: (context, index) {
                                final bid = md.bids[index];
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  color: index % 2 == 0 ? Colors.green.withOpacity(0.05) : null,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '\$${bid.price.toStringAsFixed(2)}',
                                        style: const TextStyle(color: Colors.green),
                                      ),
                                      Text('${bid.size}'),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    // Asks
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            color: Colors.red.withOpacity(0.2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text('Price', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('Size', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: md.asks.length,
                              itemBuilder: (context, index) {
                                final ask = md.asks[index];
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  color: index % 2 == 0 ? Colors.red.withOpacity(0.05) : null,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '\$${ask.price.toStringAsFixed(2)}',
                                        style: const TextStyle(color: Colors.red),
                                      ),
                                      Text('${ask.size}'),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
  
  Widget _buildInstrumentControls(int instrumentId) {
    final ws = ref.watch(webSocketProvider);
    final instrument = ws.instruments.firstWhere((i) => i.id == instrumentId);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Controls',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          
          // Tick size adjustment
          Card(
            color: Colors.blue.shade900.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tick Size',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current: \$${instrument.tickSize.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _showChangeTickSizeDialog(instrumentId, instrument.symbol, instrument.tickSize),
                    icon: const Icon(Icons.tune, size: 16),
                    label: const Text('Adjust'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Pull All Quotes
          OutlinedButton.icon(
            onPressed: () => _pullAllQuotes(instrumentId),
            icon: const Icon(Icons.clear_all),
            label: const Text('Pull All Quotes'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(12),
              foregroundColor: Colors.purple,
            ),
          ),
          const SizedBox(height: 8),
          
          // Halt
          OutlinedButton.icon(
            onPressed: () => _haltInstrument(instrumentId),
            icon: const Icon(Icons.pause_circle),
            label: const Text('Halt Trading'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(12),
              foregroundColor: Colors.orange,
            ),
          ),
          const SizedBox(height: 8),
          
          // Settle or Expire
          FilledButton.icon(
            onPressed: () => instrument.type == 'SCALAR' 
                ? _showSettleDialog(instrumentId, instrument.symbol)
                : _showExpireDialog(instrumentId, instrument.symbol, instrument.type),
            icon: Icon(instrument.type == 'SCALAR' ? Icons.gavel : Icons.timer_off),
            label: Text(instrument.type == 'SCALAR' ? 'Settle' : 'Expire'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(12),
            ),
          ),
          
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          
          Text(
            'Details',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text('Type: ${instrument.type}', style: const TextStyle(fontSize: 12)),
          if (instrument.strike != null)
            Text('Strike: \$${instrument.strike!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
          Text('Lot Size: ${instrument.lotSize}', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
  
  Widget _buildTraderMonitor() {
    // For now, showing a simplified view
    // TODO: Add real-time trader stats when backend broadcasts are implemented
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 48, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          Text(
            'Real-time trader monitoring',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Monitor all trader positions, P&L, and activity here',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              // Trigger leaderboard or stats view
            },
            icon: const Icon(Icons.leaderboard, size: 16),
            label: const Text('View Leaderboard'),
          ),
        ],
      ),
    );
  }
  
  void _showAddInstrumentDialog() {
    showDialog(
      context: context,
      builder: (context) => const AddInstrumentDialog(),
    );
  }
  
  void _showChangeTickSizeDialog(int instrumentId, String symbol, double currentTickSize) {
    final controller = TextEditingController(text: currentTickSize.toStringAsFixed(2));
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Adjust Tick Size: $symbol'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Changing tick size will affect order placement granularity.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'New Tick Size',
                prefixText: '\$',
                border: OutlineInputBorder(),
                hintText: '0.01',
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text(
              'Suggested values: 0.01, 0.05, 0.10, 0.25, 0.50, 1.00',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newTickSize = double.tryParse(controller.text);
              if (newTickSize != null && newTickSize > 0) {
                debugPrint('🔴 EXCHANGE: Updating tick size to $newTickSize for instrument $instrumentId');
                // Send update_tick_size message
                ref.read(webSocketProvider).send({
                  'op': 'update_tick_size',
                  'instrument_id': instrumentId,
                  'tick_size': newTickSize,
                });
                debugPrint('📤 Sent update_tick_size message: {op: update_tick_size, instrument_id: $instrumentId, tick_size: $newTickSize}');
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Tick size updating... all orders will be pulled')),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
  
  void _pullAllQuotes(int instrumentId) {
    final ws = ref.read(webSocketProvider);
    debugPrint('🔴 EXCHANGE: Pulling all quotes for instrument $instrumentId');
    ws.send({
      'op': 'pull_quotes',
      'inst': instrumentId,
    });
    debugPrint('📤 Sent pull_quotes message: {op: pull_quotes, inst: $instrumentId}');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All quotes pulled from the book')),
    );
  }
  
  void _haltInstrument(int instrumentId) {
    final ws = ref.read(webSocketProvider);
    ws.haltInstrument(instrumentId, true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Instrument halted')),
    );
  }
  
  void _showSettleDialog(int instrumentId, String symbol) {
    final controller = TextEditingController();
    final ws = ref.read(webSocketProvider);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Settle $symbol'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Settling the spot will also expire all related options.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Settlement Value',
                prefixText: '\$',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null) {
                ws.settleInstrument(instrumentId, value);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Settled $symbol at \$${value.toStringAsFixed(2)}')),
                );
              }
            },
            child: const Text('Settle'),
          ),
        ],
      ),
    );
  }
  
  void _showExpireDialog(int instrumentId, String symbol, String type) {
    final controller = TextEditingController();
    final ws = ref.read(webSocketProvider);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Expire $symbol'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Expiring a $type option. Enter the spot price at expiry:'),
            const SizedBox(height: 8),
            const Text(
              'ITM options will settle to one unit of the underlying.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Spot Price at Expiry',
                prefixText: '\$',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null) {
                // For options, we send expire_option message
                ws.send({
                  'op': 'expire_option',
                  'inst': instrumentId,
                  'spot_price': value,
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Expired $symbol at spot \$${value.toStringAsFixed(2)}')),
                );
              }
            },
            child: const Text('Expire'),
          ),
        ],
      ),
    );
  }
}

class AddInstrumentDialog extends ConsumerStatefulWidget {
  const AddInstrumentDialog({Key? key}) : super(key: key);

  @override
  ConsumerState<AddInstrumentDialog> createState() => _AddInstrumentDialogState();
}

class _AddInstrumentDialogState extends ConsumerState<AddInstrumentDialog> {
  final _symbolController = TextEditingController();
  final _strikeController = TextEditingController();
  final _tickSizeController = TextEditingController(text: '1.00');
  String _type = 'SCALAR';
  int? _referenceId;
  
  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(webSocketProvider);
    final scalars = ws.instruments.where((i) => i.type == 'SCALAR').toList();
    
    return AlertDialog(
      title: const Text('Add Instrument'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _symbolController,
              decoration: const InputDecoration(
                labelText: 'Symbol',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'SCALAR', child: Text('Scalar')),
                DropdownMenuItem(value: 'CALL', child: Text('Call Option')),
                DropdownMenuItem(value: 'PUT', child: Text('Put Option')),
              ],
              onChanged: (value) {
                setState(() {
                  _type = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            
            if (_type != 'SCALAR') ...[
              DropdownButtonFormField<int>(
                value: _referenceId,
                decoration: const InputDecoration(
                  labelText: 'Underlying',
                  border: OutlineInputBorder(),
                ),
                items: scalars.map((inst) {
                  return DropdownMenuItem(
                    value: inst.id,
                    child: Text(inst.symbol),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _referenceId = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _strikeController,
                decoration: const InputDecoration(
                  labelText: 'Strike Price',
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
            ],
            
            TextField(
              controller: _tickSizeController,
              decoration: const InputDecoration(
                labelText: 'Tick Size',
                prefixText: '\$',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_symbolController.text.isEmpty) return;
            if (_type != 'SCALAR' && (_referenceId == null || _strikeController.text.isEmpty)) {
              return;
            }
            
            ref.read(webSocketProvider).addInstrument(
              symbol: _symbolController.text,
              type: _type,
              referenceId: _referenceId,
              strike: _type != 'SCALAR' ? double.tryParse(_strikeController.text) : null,
              tickSize: double.tryParse(_tickSizeController.text) ?? 1.0,
            );
            
            Navigator.pop(context);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _symbolController.dispose();
    _strikeController.dispose();
    _tickSizeController.dispose();
    super.dispose();
  }
}

