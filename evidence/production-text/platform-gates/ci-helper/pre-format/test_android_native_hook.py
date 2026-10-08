"""AGP9.1 generated JNI directory binding and explicit task-order contract."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class AndroidNativeHook(unittest.TestCase):
 def test_concrete_directory_and_explicit_producer_dependency(self):
  text=(ROOT/'android/app/build.gradle.kts').read_text()
  self.assertIn('jniLibs.srcDir(textEngineJni.get().asFile)',text)
  self.assertIn('tasks.named("preBuild") { dependsOn(buildTextEngine) }',text)
  self.assertIn('outputs.dir(textEngineJni)',text)
  self.assertIn('"--output-dir", textEngineJni.get().asFile.absolutePath',text)
  self.assertNotIn('jniLibs.srcDir(textEngineJni)',text)
  self.assertNotIn('android.sourceset.disallowProvider=false',(ROOT/'android/gradle.properties').read_text())
if __name__=='__main__':unittest.main()
