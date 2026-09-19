/*
 * File: mobile_shell_file_picker_reproduction_test.dart
 * Description: Verification test confirming zero-copy DeviceFilePickerSheet integration and concurrency mutex locking.
 */

import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/core/utils/storage_permission_helper.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'package:telstorage/features/downloads/presentation/screens/downloads/viewmodel/downloads_view_model.dart';
import 'package:telstorage/features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_file_picker_helper.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_view_model.dart';
import 'package:telstorage/shared/widgets/device_file_picker_sheet.dart';
import 'package:telstorage/shared/widgets/mobile_shell.dart';
import 'package:telstorage/shared/widgets/mobile_shell/mobile_bottom_nav.dart';

class MockThrowingFilePicker extends FilePicker {
  int totalCalls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus p1)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    totalCalls++;
    return null;
  }

  @override
  Future<bool?> clearTemporaryFiles() async => true;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => null;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => null;
}

class FakeBrowserBloc extends Cubit<BrowserState> implements BrowserBloc {
  FakeBrowserBloc() : super(BrowserState());
  @override
  void add(BrowserEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUploadBloc extends Cubit<UploadState> implements UploadBloc {
  final List<UploadTask> enqueuedTasks = [];
  FakeUploadBloc() : super(UploadIdle());

  @override
  void add(UploadEvent event) {
    if (event is AddUploads) {
      enqueuedTasks.addAll(event.tasks);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHomeCubit extends Cubit<HomeState> implements HomeCubit {
  FakeHomeCubit() : super(HomeState());
  @override
  Future<void> initialize() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTransferCubit extends Cubit<TransferState> implements TransferCubit {
  FakeTransferCubit() : super(TransferState());
  @override
  Future<void> initialize() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockThrowingFilePicker mockPicker;
  late FakeBrowserBloc browserBloc;
  late FakeUploadBloc uploadBloc;
  late FakeHomeCubit homeCubit;
  late FakeTransferCubit transferCubit;

  setUp(() {
    StoragePermissionHelper.permissionOverrideForTesting = true;
    mockPicker = MockThrowingFilePicker();
    FilePicker.platform = mockPicker;
    browserBloc = FakeBrowserBloc();
    uploadBloc = FakeUploadBloc();
    homeCubit = FakeHomeCubit();
    transferCubit = FakeTransferCubit();

    ServiceLocator.instance.setInitializedForTesting(true);
  });

  tearDown(() {
    StoragePermissionHelper.permissionOverrideForTesting = null;
    ServiceLocator.instance.setInitializedForTesting(false);
  });

  Widget buildTestWidget() {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<BrowserBloc>.value(value: browserBloc),
          BlocProvider<UploadBloc>.value(value: uploadBloc),
          BlocProvider<HomeCubit>.value(value: homeCubit),
          BlocProvider<TransferCubit>.value(value: transferCubit),
        ],
        child: const Scaffold(
          body: MobileShell(),
        ),
      ),
    );
  }

  testWidgets(
      'Upload Files uses in-app DeviceFilePickerSheet directly and bypasses FilePicker.pickFiles',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Open add menu
    tester.widget<MobileNavBar>(find.byType(MobileNavBar)).onTap(2);
    await tester.pumpAndSettle();

    // Tap "Upload Files" action item
    await tester.tap(find.text('Upload Files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify DeviceFilePickerSheet is displayed
    expect(find.byType(DeviceFilePickerSheet), findsOneWidget,
        reason: 'DeviceFilePickerSheet should be opened directly');

    // Verify third-party FilePicker.platform.pickFiles is NEVER called
    expect(mockPicker.totalCalls, 0,
        reason: 'External FilePicker.pickFiles should not be invoked');

    // Tap Close button on the sheet
    await tester.tap(find.byIcon(AppIcons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Sheet should be dismissed
    expect(find.byType(DeviceFilePickerSheet), findsNothing);
    expect(UploadFilePickerHelper.isPicking, isFalse);
  });

  testWidgets(
      'Re-entrancy mutex lock prevents concurrent file picker sheet invocations',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // First tap on add menu
    tester.widget<MobileNavBar>(find.byType(MobileNavBar)).onTap(2);
    await tester.pumpAndSettle();

    // Tap "Upload Files" - opens DeviceFilePickerSheet
    await tester.tap(find.text('Upload Files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // While sheet is open, isPicking is true
    expect(UploadFilePickerHelper.isPicking, isTrue);

    // Attempting a second pickAndUploadFiles call while isPicking is true exits immediately
    final buildContext = tester.element(find.byType(MobileShell));
    await UploadFilePickerHelper.pickAndUploadFiles(
      context: buildContext,
      folderId: null,
      uploadBloc: uploadBloc,
    );

    // Still exactly one sheet open, no crashes
    expect(find.byType(DeviceFilePickerSheet), findsOneWidget);

    // Dismiss sheet
    await tester.tap(find.byIcon(AppIcons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Mutex lock is properly released
    expect(UploadFilePickerHelper.isPicking, isFalse);
  });
}
