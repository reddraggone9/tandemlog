"""Pure isolated child environment: no app, desktop, native API or host mutation."""
from pathlib import Path
import runpy,unittest
CODE=runpy.run_path(str(Path(__file__).with_name("windows_widget_controller.py")),run_name="pure_child_env")
build=CODE["child_environment"]
class ChildEnvironmentTests(unittest.TestCase):
    def test_only_curated_values_and_owned_profile_reach_child(self):
        env=build(Path("bundle"),Path("bundle/native.dll"),Path("output"),Path("tmp"),Path("tmp/run"),"run",Path("public"),{"SystemRoot":"C:\\Windows","WINDIR":"C:\\Windows","GH_TOKEN":"secret","TANDEMLOG_PROFILE":"real-user-profile"})
        self.assertNotIn("GH_TOKEN",env)
        self.assertEqual(env["TANDEMLOG_PROFILE"],str(Path("tmp/run/profile")))
        self.assertEqual(env["TANDEMLOG_WINDOWS_WIDGET_FIXTURE"],str(Path("public")))
        self.assertEqual(env["TANDEMLOG_TEXT_LIBRARY"],str(Path("bundle/native.dll")))
        self.assertNotIn("FLUTTER_ENGINE_SWITCHES",env)
    def test_cost_trace_requires_explicit_controller_flag(self):
        args=(Path("bundle"),Path("dll"),Path("out"),Path("tmp"),Path("tmp/run"),"run",Path("fixture"),{"SystemRoot":"C:\\Windows","TANDEMLOG_WINDOWS_WIDGET_COSTS":"1"})
        self.assertNotIn("TANDEMLOG_WINDOWS_WIDGET_COSTS",build(*args))
        self.assertEqual(build(*args,cost_trace=True)["TANDEMLOG_WINDOWS_WIDGET_COSTS"],"1")
    def test_missing_system_root_refused_before_spawn(self):
        with self.assertRaisesRegex(RuntimeError,"SystemRoot missing"):
            build(Path("bundle"),Path("dll"),Path("out"),Path("tmp"),Path("tmp/run"),"run",Path("fixture"),{})
if __name__=="__main__":unittest.main()
