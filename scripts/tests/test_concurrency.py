import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("concurrency", pathlib.Path(__file__).parents[1] / "check-concurrency.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ConcurrencyDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.baseline = {"appWarningLimit": 1, "locations": {"Meno/App.swift:12": 1}}

    def testRepeatedCompilerEmissionsAndRenderedExcerptsCountOnce(self):
        line = "/runner/repo/Sources/Meno/App.swift:12:3: warning: sending value risks causing data races\n"
        core, app, errors = module.check(line * 3 + "  | warning: sending value risks causing data races\n", self.baseline)
        self.assertEqual((len(core), len(app), errors), (0, 1, []))

    def testNewLocationFailsEvenBelowTheWarningLimit(self):
        baseline = {"appWarningLimit": 10, "locations": self.baseline["locations"]}
        _, _, errors = module.check("/runner/repo/Sources/Meno/New.swift:15:1: warning: actor-isolated value\n", baseline)
        self.assertTrue(errors)

    def testCoreWarningFailsAndOrdinaryAppDeprecationDoesNotUseConcurrencyBudget(self):
        log = ("/runner/repo/Sources/MenoCore/Value.swift:1:2: warning: deprecated API\n"
               "/runner/repo/Sources/Meno/App.swift:20:1: warning: deprecated API\n")
        core, app, errors = module.check(log, self.baseline)
        self.assertEqual((len(core), len(app)), (1, 0))
        self.assertTrue(errors)

    def testAdditionalDiagnosticAtExistingLocationFails(self):
        log = ("Sources/Meno/App.swift:12:1: warning: non-Sendable value\n"
               "Sources/Meno/App.swift:12:1: warning: sending actor value\n")
        self.assertTrue(module.check(log, self.baseline)[2])
