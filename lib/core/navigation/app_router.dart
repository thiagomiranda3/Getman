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
