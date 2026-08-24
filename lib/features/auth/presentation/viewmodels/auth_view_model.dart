/// File: auth_view_model.dart
/// Description: Authentication ViewModel (Bloc) managing session state, login, and logout.
library;

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/service_locator.dart';

// ── Events ────────────────────────────────────────────────────────────────────

/// Base abstract event for authentication actions.
sealed class AuthEvent {}

/// Event triggered on initial app startup to check existing credentials.
class AppStarted extends AuthEvent {}

/// Event triggered when user submits email and password credentials.
class LoginRequested extends AuthEvent {
  /// User email address.
  final String email;

  /// User password.
  final String password;

  /// Constructs a login request event.
  LoginRequested(this.email, this.password);
}

/// Event triggered when user logs out.
class LogoutRequested extends AuthEvent {}

// ── States ────────────────────────────────────────────────────────────────────

/// Base abstract state for authentication flow.
sealed class AuthState {}

/// Initial state prior to session check.
class AuthInitial extends AuthState {}

/// State indicating an in-progress authentication operation.
class AuthLoading extends AuthState {}

/// State representing an active authenticated session.
class Authenticated extends AuthState {
  /// The authenticated user's email.
  final String email;

  /// Constructs authenticated state.
  Authenticated(this.email);
}

/// State representing an unauthenticated session.
class Unauthenticated extends AuthState {}

/// State representing an authentication error.
class AuthError extends AuthState {
  /// User-facing error message.
  final String message;

  /// Constructs authentication error state.
  AuthError(this.message);
}

// ── ViewModel (Bloc) ──────────────────────────────────────────────────────────

/// ViewModel managing authentication business logic and states.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  /// Internal auth service singleton reference.
  final AuthService _authService = AuthService.instance;

  /// Initializes AuthBloc with default initial state and handlers.
  AuthBloc() : super(AuthInitial()) {
    on<AppStarted>(_onAppStarted);
    on<LoginRequested>(_onLoginRequested);
    on<LogoutRequested>(_onLogoutRequested);
  }

  /// Handles AppStarted event by verifying cached session.
  Future<void> _onAppStarted(AppStarted event, Emitter<AuthState> emit) async {
    final loggedIn = await _authService.isLoggedIn();
    if (loggedIn) {
      try {
        await ServiceLocator.instance.init();
        final email = await _authService.getEmail() ?? 'user';
        emit(Authenticated(email));
      } catch (e) {
        emit(Unauthenticated());
      }
    } else {
      emit(Unauthenticated());
    }
  }

  /// Handles user login request.
  Future<void> _onLoginRequested(
      LoginRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    final result = await _authService.login(event.email, event.password);
    if (result['success'] == true) {
      try {
        await ServiceLocator.instance.init();
        emit(Authenticated(event.email));
      } catch (e) {
        emit(AuthError('Failed to initialize services: $e'));
      }
    } else {
      emit(AuthError(result['message'] ?? 'Login failed'));
    }
  }

  /// Handles user logout request.
  Future<void> _onLogoutRequested(
      LogoutRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    await _authService.logout();
    emit(Unauthenticated());
  }
}

/// Type alias aligning AuthBloc with MVVM nomenclature.
typedef AuthViewModel = AuthBloc;
