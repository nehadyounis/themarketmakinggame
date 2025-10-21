import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/lobby_screen.dart';
import 'screens/trading_terminal.dart';
import 'screens/exchange_console.dart';
import 'screens/leaderboard_screen.dart';

void main() {
  runApp(const ProviderScope(child: MMGApp()));
}

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LobbyScreen(),
    ),
    GoRoute(
      path: '/trading',
      builder: (context, state) => const TradingTerminal(),
    ),
    GoRoute(
      path: '/exchange',
      builder: (context, state) => const ExchangeConsole(),
    ),
    GoRoute(
      path: '/leaderboard',
      builder: (context, state) => const LeaderboardScreen(),
    ),
  ],
);

class MMGApp extends StatelessWidget {
  const MMGApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Market Making Game',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

