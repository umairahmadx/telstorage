"""Unit tests for the deterministic import-boundary rules."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from architecture_guardrails import _violates_boundary, inspect_architecture


class ArchitectureGuardrailsTest(unittest.TestCase):
    def test_core_cannot_depend_on_feature_or_shared_code(self) -> None:
        self.assertTrue(
            _violates_boundary(
                "core/services/example.dart", "features/upload/presentation/page.dart"
            )
        )
        self.assertTrue(
            _violates_boundary("core/services/example.dart", "shared/widgets/button.dart")
        )

    def test_shared_cannot_depend_on_features(self) -> None:
        self.assertTrue(
            _violates_boundary(
                "shared/widgets/example.dart", "features/browser/presentation/page.dart"
            )
        )

    def test_feature_layers_point_inward(self) -> None:
        self.assertTrue(
            _violates_boundary(
                "features/upload/presentation/page.dart",
                "features/upload/data/repository.dart",
            )
        )
        self.assertTrue(
            _violates_boundary(
                "features/upload/domain/model.dart",
                "features/upload/presentation/page.dart",
            )
        )
        self.assertFalse(
            _violates_boundary(
                "features/upload/presentation/page.dart",
                "features/upload/domain/usecase.dart",
            )
        )
        self.assertTrue(
            _violates_boundary(
                "features/home/presentation/viewmodel.dart",
                "features/storage/data/repository.dart",
            )
        )

    def test_unlisted_boundary_import_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            (root / "lib/core").mkdir(parents=True)
            (root / "lib/features/upload/presentation").mkdir(parents=True)
            (root / "scripts/architecture_allowlist.json").write_text("{}", encoding="utf-8")
            (root / "scripts/presentation_service_locator_allowlist.json").write_text("{}", encoding="utf-8")
            (root / "lib/core/example.dart").write_text(
                "import 'package:telstorage/features/upload/presentation/page.dart';\n",
                encoding="utf-8",
            )
            (root / "lib/features/upload/presentation/page.dart").write_text(
                "class Page {}\n", encoding="utf-8"
            )

            violations, stale = inspect_architecture(root)

        self.assertEqual(stale, [])
        self.assertEqual(len(violations), 1)
        self.assertIn("forbidden architecture dependency", violations[0])

    def test_unresolved_merge_markers_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            (root / "lib/core").mkdir(parents=True)
            (root / "scripts/architecture_allowlist.json").write_text("{}", encoding="utf-8")
            (root / "scripts/presentation_service_locator_allowlist.json").write_text("{}", encoding="utf-8")
            (root / "lib/core/example.dart").write_text(
                "<<<<<<< current\n=======\n>>>>>>> incoming\n", encoding="utf-8"
            )

            violations, stale = inspect_architecture(root)

        self.assertEqual(stale, [])
        self.assertEqual(len(violations), 3)
        self.assertTrue(all("unresolved merge marker" in item for item in violations))

    def test_new_presentation_service_locator_use_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            presentation = root / "lib/features/upload/presentation"
            presentation.mkdir(parents=True)
            (root / "scripts/architecture_allowlist.json").write_text("{}", encoding="utf-8")
            (root / "scripts/presentation_service_locator_allowlist.json").write_text("{}", encoding="utf-8")
            (presentation / "page.dart").write_text(
                "final service = ServiceLocator.instance;\n", encoding="utf-8"
            )

            violations, stale = inspect_architecture(root)

        self.assertEqual(stale, [])
        self.assertEqual(len(violations), 1)
        self.assertIn("new direct ServiceLocator.instance", violations[0])

    def test_view_model_filename_requires_supported_state_holder(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            viewmodels = root / "lib/features/upload/presentation"
            viewmodels.mkdir(parents=True)
            (root / "scripts/architecture_allowlist.json").write_text("{}", encoding="utf-8")
            (root / "scripts/presentation_service_locator_allowlist.json").write_text("{}", encoding="utf-8")
            (viewmodels / "upload_view_model.dart").write_text(
                "class UploadViewModel {}\n", encoding="utf-8"
            )

            violations, stale = inspect_architecture(root)

        self.assertEqual(stale, [])
        self.assertEqual(len(violations), 1)
        self.assertIn("must declare a Bloc, Cubit, or ChangeNotifier", violations[0])


if __name__ == "__main__":
    unittest.main()
