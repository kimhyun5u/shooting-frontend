import 'package:flutter/material.dart';
import 'package:frontend/src/screens/home_screen.dart';
import 'package:frontend/src/screens/room_screen.dart';
import 'package:go_router/go_router.dart';

final GoRouter router = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const HomeScreen();
      },
      routes: <RouteBase>[
        GoRoute(
          path: 'rooms/:roomID',
          builder: (BuildContext context, GoRouterState state) {
            return RoomScreen(
              roomID: state.pathParameters['roomID'],
            );
          },
        ),
      ],
    ),
  ],
);
