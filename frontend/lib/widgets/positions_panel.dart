import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class PositionsPanel extends ConsumerWidget {
  const PositionsPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(webSocketProvider);
    
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Positions section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                        'Positions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        'Total PnL: \$${ws.totalPnl.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: ws.totalPnl >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ws.positions.isEmpty
                      ? const Center(
                          child: Text('No positions'),
                        )
                      : ListView.builder(
                          itemCount: ws.positions.length,
                          itemBuilder: (context, index) {
                            final pos = ws.positions[index];
                            final instrument = ws.instruments.firstWhere(
                              (i) => i.id == pos.instrumentId,
                              orElse: () => throw Exception('Instrument not found'),
                            );
                            
                            return ListTile(
                              title: Text(instrument.symbol),
                              subtitle: Text(
                                'Qty: ${pos.qty} @ \$${pos.vwap.toStringAsFixed(2)}',
                              ),
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '\$${pos.totalPnl.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: pos.totalPnl >= 0 ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (pos.unrealizedPnl != 0)
                                    Text(
                                      'U: \$${pos.unrealizedPnl.toStringAsFixed(2)}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Quick actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Quick Actions',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ws.getPositions();
                          ws.getPnL();
                        },
                        child: const Text('Refresh'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => ws.cancelAll(),
                        child: const Text('Cancel All'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

