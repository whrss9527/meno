import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "app-intents.py"
spec = importlib.util.spec_from_file_location("app_intents", SCRIPT)
intents = importlib.util.module_from_spec(spec)
spec.loader.exec_module(intents)


class AppIntentMetadataTests(unittest.TestCase):
    def fixture(self):
        return {"actions": {name: {"openAppWhenRun": True, "parameters": [{"name": parameter, "isOptional": False}]}
                            for name, parameter in intents.EXPECTED.items()},
                "autoShortcuts": [{"actionIdentifier": name, "phraseTemplates": ["phrase"]} for name in intents.EXPECTED]}

    def testActualMetadataBoundaryRejectsMissingActionsParametersAndShortcuts(self):
        valid = self.fixture()
        malformed = []
        for action in intents.EXPECTED:
            item = copy.deepcopy(valid)
            del item["actions"][action]
            malformed.append(item)
            item = copy.deepcopy(valid)
            item["actions"][action]["parameters"][0]["isOptional"] = True
            malformed.append(item)
            item = copy.deepcopy(valid)
            item["actions"][action]["openAppWhenRun"] = False
            malformed.append(item)
        malformed.append({**valid, "autoShortcuts": []})
        with tempfile.TemporaryDirectory() as folder:
            metadata = Path(folder)
            (metadata / "version.json").write_text("{}")
            for item in malformed:
                (metadata / "extract.actionsdata").write_text(json.dumps(item))
                with self.assertRaises((ValueError, KeyError)):
                    intents.inspect(metadata)
            (metadata / "extract.actionsdata").write_text(json.dumps(valid))
            self.assertEqual(intents.inspect(metadata), valid)

    def testPackagingCliFailsWhenCompiledMetadataIsAbsent(self):
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run(["python3", str(SCRIPT), "check", folder], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("metadata failed", result.stderr)

    def testUnknownXcodeCannotSelectAGuessedProtocolContract(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(intents.subprocess, "check_output", return_value="Xcode 27.0\nBuild version unknown\n"):
            with self.assertRaisesRegex(ValueError, "Validate"):
                intents.configure(Path(folder))

    def testBothVerifiedCompilerContractsRetainRequiredIntentAndEntityProtocols(self):
        for major, count in [(16, 13), (26, 17)]:
            contract = intents.ROOT / f"scripts/fixtures/app-intents-protocols/xcode{major}.json"
            names = json.loads(contract.read_text())
            self.assertEqual(len(names), count)
            self.assertTrue({"AppIntent", "AppEntity", "EntityQuery", "AppShortcutsProvider"} <= set(names))
