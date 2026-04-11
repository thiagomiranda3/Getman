import 'package:go_router/go_router.dart';
import '../../features/home/presentation/screens/main_screen.dart';

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
