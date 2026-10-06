"""Release metadata must fail closed before publishing."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        (self.root / "scripts").mkdir()
        source = pathlib.Path(__file__).resolve().parents[1]
        for name in ("check-release.sh", "release-notes.sh"):
            shutil.copy(source / name, self.root / "scripts" / name)
        (self.root / "VERSION").write_text("1.2.3\n")
        self.notes = self.root / ".github/releases/v1.2.3.md"
        self.notes.parent.mkdir(parents=True)
        self.notes.write_text("Release notes\n")

    def run_script(self, name, *args):
        return subprocess.run(["bash", str(self.root / "scripts" / name), *args],
                              cwd=self.root, capture_output=True, text=True)

    def test_current_version_and_tag(self):
        for args in ((), ("1.2.3",), ("v1.2.3",)):
            self.assertEqual(self.run_script("check-release.sh", *args).returncode, 0)
        result = self.run_script("release-notes.sh", "v1.2.3")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "Release notes\n")

    def test_mismatched_version_is_rejected_even_if_notes_exist(self):
        (self.notes.parent / "v1.2.4.md").write_text("Other notes")
        for name in ("check-release.sh", "release-notes.sh"):
            self.assertNotEqual(self.run_script(name, "v1.2.4").returncode, 0)

    def test_missing_notes_are_rejected(self):
        self.notes.unlink()
        self.assertNotEqual(self.run_script("check-release.sh").returncode, 0)
        self.assertNotEqual(self.run_script("release-notes.sh", "1.2.3").returncode, 0)

    def test_empty_notes_are_rejected(self):
        self.notes.write_text("")
        self.assertNotEqual(self.run_script("check-release.sh").returncode, 0)

    def test_invalid_version_is_rejected(self):
        (self.root / "VERSION").write_text("../invalid\n")
        self.assertNotEqual(self.run_script("check-release.sh").returncode, 0)
