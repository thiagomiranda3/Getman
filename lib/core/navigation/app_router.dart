// go_router setup: a single '/' route rendering MainScreen. Room to grow as
// more routes are added.

import 'package:getman/features/home/presentation/screens/main_screen.dart';
import 'package:go_router/go_router.dart';

class AppRouter {
  static const String home = '/';

  final router = GoRouter(
    initialLocation: home,
    routes: [
      GoRoute(
        path: home,
        builder: (context, state) => const MainScreen(),
      ),
    ],
  );
}
