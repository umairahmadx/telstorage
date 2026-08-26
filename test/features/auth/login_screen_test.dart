/*
 * File: login_screen_test.dart
 * Description: Widget tests validating LoginScreen focus flow, tap-to-dismiss keyboard, password validation, and error banner display.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/auth/presentation/screens/login/login_screen.dart';
import 'package:telstorage/features/auth/presentation/viewmodels/auth_view_model.dart';

class _FakeAuthBloc extends AuthBloc {
  _FakeAuthBloc({AuthState? initialState}) : super() {
    if (initialState != null) {
      emit(initialState);
    }
  }

  void emitState(AuthState state) => emit(state);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject(AuthBloc bloc) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: BlocProvider<AuthBloc>.value(
        value: bloc,
        child: const LoginScreen(),
      ),
    );
  }

  group('LoginScreen UI, Focus & Error Handling Tests', () {
    testWidgets('TC-01: Renders email, password fields and sign-in button',
        (tester) async {
      final bloc = _FakeAuthBloc(initialState: Unauthenticated());

      await tester.pumpWidget(buildSubject(bloc));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Sign in to your cloud drive'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('TC-02: Validates email and minimum password length',
        (tester) async {
      final bloc = _FakeAuthBloc(initialState: Unauthenticated());

      await tester.pumpWidget(buildSubject(bloc));
      await tester.pumpAndSettle();

      // Tap Sign in with empty fields
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);

      // Enter invalid email and short password (< 6 chars)
      await tester.enterText(
          find.byType(TextFormField).first, 'invalid-email');
      await tester.enterText(
          find.byType(TextFormField).last, '12345');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    });

    testWidgets('TC-03: Displays error banner and SnackBar on AuthError',
        (tester) async {
      final bloc = _FakeAuthBloc(initialState: Unauthenticated());

      await tester.pumpWidget(buildSubject(bloc));
      await tester.pumpAndSettle();

      // Emit AuthError state with incorrect password message
      bloc.emitState(AuthError('Incorrect password. Please try again.'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Incorrect password. Please try again.'), findsWidgets);

      // Typing clears error
      await tester.enterText(find.byType(TextFormField).first, 'a');
      await tester.pump();
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('TC-04: Tapping outside dismisses focus/keyboard',
        (tester) async {
      final bloc = _FakeAuthBloc(initialState: Unauthenticated());

      await tester.pumpWidget(buildSubject(bloc));
      await tester.pumpAndSettle();

      // Focus email input
      await tester.tap(find.byType(TextFormField).first);
      await tester.pumpAndSettle();
      expect(
        FocusScope.of(tester.element(find.byType(TextFormField).first)).hasFocus,
        isTrue,
      );

      // Tap outside on hero background
      await tester.tap(find.text('Welcome back'));
      await tester.pumpAndSettle();

      expect(
        FocusScope.of(tester.element(find.byType(TextFormField).first)).hasFocus,
        isFalse,
      );
    });
  });
}
