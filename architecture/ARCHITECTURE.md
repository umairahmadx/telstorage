# TelStorage architecture

## Current architecture

TelStorage is a Flutter app with feature-oriented folders. Most feature logic is presented through BLoC or Cubit state holders. Two media-player state holders use `ChangeNotifier`. Several files and folders still use the name `view_model`, but the project is not a uniform classic MVVM implementation: it is a mixed BLoC/Cubit and `ChangeNotifier` app.

The root app in `lib/app.dart` creates the app-wide `AuthBloc`, `UploadBloc`, `HomeCubit`, `TransferCubit`, and `BrowserBloc` with `MultiBlocProvider`. The player `ChangeNotifier`s are owned closer to their screens. Widgets dispatch BLoC events, call Cubit methods, or listen to `ChangeNotifier` state.

## Main layers

- `lib/core/` holds shared models, errors, utilities, app services, navigation, persistence helpers, and the composition root. `ServiceLocator` constructs and owns account-scoped services after login.
- `lib/features/<feature>/presentation/` holds screens, widgets, state holders, and feature-facing helpers. Several features are presentation-only today.
- `lib/features/storage/domain/` defines repository capabilities and two use cases. Its `data/` folder contains the `StorageRepository` implementation.
- `lib/shared/widgets/` holds cross-feature shell and reusable widget code. The mobile shell currently composes multiple feature screens.
- `lib/main.dart` initializes platform services and persistence; `lib/app.dart` composes the widget tree and app-wide state providers.

The common data path is:

```text
Screen / widget
  → Bloc, Cubit, or ChangeNotifier
  → repository contract or app service
  → Hive cache and/or remote service
  → state/event notification
  → rebuilt UI
```

`DomainEventBus`, Hive listenables, and queue notifiers are used for reactive updates. Uploads flow through `UploadBloc` and the transfer queue into `UploadService`; backup and incoming-share work reuse that queue.

## Existing architectural debt

- Twenty-four files under feature presentation currently call `ServiceLocator.instance` directly. This works, but it hides dependencies and makes state holders harder to isolate. The exact current users and reasons are tracked in `scripts/presentation_service_locator_allowlist.json`; new presentation files cannot add direct locator access.
- `HomeCubit` depends on concrete `StorageRepository`, and `BrowserFilterHelper` type-checks that concrete repository to access partition state. The storage contract exists, so these should eventually move to narrower contracts.
- `ServiceLocator` and `AppRouter` are composition roots with intentional core-to-feature references. Other core/shared crossings are recorded as exact edges in `scripts/architecture_allowlist.json`.
- Feature layering is incomplete and inconsistent. The guardrail preserves the current exceptions while blocking new violations; it does not claim the existing debt is resolved.

## Enforced rules

`scripts/architecture_guardrails.py` enforces these deterministic conventions:

1. `core` cannot import `features` or `shared`; `shared` cannot import `features`.
2. Feature dependencies point inward: domain cannot depend on data or presentation, data cannot depend on presentation, and presentation cannot depend on data, including across features.
3. A file named `*_view_model.dart` must declare a state holder based on `Bloc`, `Cubit`, or `ChangeNotifier`.
4. Feature presentation files cannot add new direct `ServiceLocator.instance` use. The 24 existing users are explicitly allowlisted for gradual migration.
5. Dart sources cannot contain unresolved merge-conflict markers.
6. Every allowlisted legacy edge must still exist. Remove exceptions when the code is migrated.

Run the checks with:

```sh
python scripts/architecture_guardrails.py
python -m unittest discover -s scripts -p 'test_*.py' -v
```

CI runs both before Flutter analysis and tests. Current debt is visible in the two allowlist files; passing the check means no new violations were introduced, not that every old exception has already been removed.
