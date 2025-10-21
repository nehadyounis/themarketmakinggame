import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class OrderEntryDialog extends ConsumerStatefulWidget {
  final int instrumentId;
  final double initialPrice;
  final String initialSide;
  
  const OrderEntryDialog({
    Key? key,
    required this.instrumentId,
    required this.initialPrice,
    required this.initialSide,
  }) : super(key: key);

  @override
  ConsumerState<OrderEntryDialog> createState() => _OrderEntryDialogState();
}

class _OrderEntryDialogState extends ConsumerState<OrderEntryDialog> {
  late TextEditingController _priceController;
  late TextEditingController _qtyController;
  late String _side;
  String _tif = 'GFD';
  bool _postOnly = false;
  
  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.initialPrice.toStringAsFixed(2),
    );
    _qtyController = TextEditingController(text: '10');
    _side = widget.initialSide;
  }
  
  @override
  Widget build(BuildContext context) {
    final ws = ref.read(webSocketProvider);
    final instrument = ws.instruments.firstWhere(
      (i) => i.id == widget.instrumentId,
    );
    
    return AlertDialog(
      title: Text('New Order - ${instrument.symbol}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Side selector
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'buy',
                label: Text('Buy'),
                icon: Icon(Icons.arrow_upward, color: Colors.green),
              ),
              ButtonSegment(
                value: 'sell',
                label: Text('Sell'),
                icon: Icon(Icons.arrow_downward, color: Colors.red),
              ),
            ],
            selected: {_side},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() {
                _side = newSelection.first;
              });
            },
          ),
          const SizedBox(height: 16),
          
          // Price
          TextField(
            controller: _priceController,
            decoration: const InputDecoration(
              labelText: 'Price',
              prefixText: '\$',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          
          // Quantity
          TextField(
            controller: _qtyController,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          
          // TIF
          DropdownButtonFormField<String>(
            value: _tif,
            decoration: const InputDecoration(
              labelText: 'Time in Force',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'GFD', child: Text('Good for Day')),
              DropdownMenuItem(value: 'IOC', child: Text('Immediate or Cancel')),
            ],
            onChanged: (value) {
              setState(() {
                _tif = value!;
              });
            },
          ),
          const SizedBox(height: 16),
          
          // Post-only
          CheckboxListTile(
            value: _postOnly,
            onChanged: (value) {
              setState(() {
                _postOnly = value ?? false;
              });
            },
            title: const Text('Post-Only'),
            subtitle: const Text('Reject if order would match immediately'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
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
            final price = double.tryParse(_priceController.text);
            final qty = int.tryParse(_qtyController.text);
            
            if (price != null && qty != null && qty > 0) {
              ws.submitOrder(
                instrumentId: widget.instrumentId,
                side: _side,
                price: price,
                qty: qty,
                tif: _tif,
                postOnly: _postOnly,
              );
              Navigator.pop(context);
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: _side == 'buy' ? Colors.green : Colors.red,
          ),
          child: Text(_side == 'buy' ? 'Buy' : 'Sell'),
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }
}

