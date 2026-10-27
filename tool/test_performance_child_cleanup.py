"""Real short-process controls only: no compiler, benchmark, root or subreaper."""
import json
import tempfile
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parent/'performance'))
import run_gate
from run_gate import wait_group_absent

@unittest.skipUnless(sys.platform.startswith('linux'),'Actual Linux process-group controls')
class GroupCleanupControls(unittest.TestCase):
    def child(self, code, stdin=subprocess.DEVNULL):
        p=subprocess.Popen([sys.executable,'-B','-c',code],stdin=stdin,
            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
        self.addCleanup(self.stop,p)
        return p
    def stop(self,p):
        if p.poll() is None:
            try:os.killpg(p.pid,signal.SIGKILL)
            except ProcessLookupError:pass
        p.wait(timeout=2)
        if p.stdin is not None:p.stdin.close()
    def record(self,name,e):
        print(json.dumps({'controlOnly':True,'case':name,'evidence':e}),flush=True)
    def test_group_disappears_only_after_real_process_is_reaped(self):
        p=self.child('import sys;sys.stdin.buffer.read(1)',stdin=subprocess.PIPE)
        os.killpg(p.pid,0) # Original immediate-absence predicate would refuse.
        evidence={};problems=[]
        def reap_after_observation():
            try:
                until=time.monotonic()+2
                while 'firstResidual' not in evidence:
                    if time.monotonic()>=until:raise RuntimeError('No initial residual witness')
                    time.sleep(.001)
                p.stdin.write(b'x');p.stdin.flush();p.wait(timeout=1)
            except BaseException as error:problems.append(repr(error))
        worker=threading.Thread(target=reap_after_observation);worker.start()
        try:wait_group_absent(p.pid,time.monotonic()+2,evidence)
        finally:worker.join(timeout=2)
        self.assertFalse(worker.is_alive());self.assertEqual(problems,[])
        self.assertTrue(evidence['absent']);self.assertEqual(p.returncode,0)
        self.assertTrue(any(m['pid']==p.pid for m in evidence['firstResidual']['members']))
        self.record('exists-then-exits-and-reaps',evidence)
    def test_persistent_zombie_is_not_ignored(self):
        p=self.child('pass');until=time.monotonic()+1
        while True:
            # Deliberately do not poll/wait: preserve an actual waitable zombie.
            state=(Path('/proc')/str(p.pid)/'stat').read_text().rsplit(')',1)[1].split()[0]
            if state=='Z':break
            self.assertLess(time.monotonic(),until);time.sleep(.001)
        evidence={}
        with self.assertRaisesRegex(RuntimeError,'Owned process group remains'):
            wait_group_absent(p.pid,time.monotonic()+.05,evidence)
        self.assertFalse(evidence['absent'])
        self.assertTrue(any(m['pid']==p.pid and m['state']=='Z' for m in evidence['firstResidual']['members']))
        self.assertEqual(p.wait(timeout=1),0)
        with self.assertRaises(ProcessLookupError):os.killpg(p.pid,0)
        self.record('zombie-refused-until-real-wait',evidence)
    def test_persistent_live_group_remains_failed(self):
        p=self.child('import time;time.sleep(3)');evidence={}
        with self.assertRaisesRegex(RuntimeError,'Owned process group remains'):
            wait_group_absent(p.pid,time.monotonic()+.05,evidence)
        self.assertFalse(evidence['absent']);self.assertIsNone(p.poll())
        self.assertTrue(any(m['pid']==p.pid and m['state']!='Z' for m in evidence['firstResidual']['members']))
        self.record('live-residue-refused',evidence)
    def test_original_deadline_is_not_extended_even_for_absent_group(self):
        p=self.child('pass');p.wait(timeout=1);evidence={};deadline=time.monotonic()-.01
        with self.assertRaisesRegex(RuntimeError,'Original stage/batch deadline'):
            wait_group_absent(p.pid,deadline,evidence)
        self.assertTrue(evidence['absent']);self.assertLessEqual(evidence['waitDeadlineMonotonic'],deadline)
        self.record('original-deadline-refused',evidence)

class RunChildControls(unittest.TestCase):
    @unittest.skipUnless(sys.platform.startswith('linux'),'Actual Linux process-group controls')
    def test_normal_driver_receipt_requires_group_absence(self):
        with tempfile.TemporaryDirectory() as folder:
            log=Path(folder)/'child.log'
            with patch.object(run_gate,'stop_owned_group',wraps=run_gate.stop_owned_group) as stop:
                result=run_gate.run_child([sys.executable,'-B','-c','print("finite child")'],log,{'PATH':'/usr/bin:/bin'},2)
                stop.assert_not_called()  # Already reaped: never signal its old group ID.
            self.assertTrue(result['childAbsent']);self.assertTrue(result['childGroupAbsent'])
            self.assertTrue(json.loads(Path(str(log)+'.cleanup.json').read_text())['childGroupAbsent'])
    @unittest.skipUnless(sys.platform.startswith('linux'),'Actual Linux process-group controls')
    def test_timeout_preserves_primary_failure_and_owned_child_cleanup(self):
        with tempfile.TemporaryDirectory() as folder:
            log=Path(folder)/'child.log'
            with self.assertRaises(subprocess.TimeoutExpired):
                run_gate.run_child([sys.executable,'-B','-c','import time;print("partial",flush=True);time.sleep(3)'],log,{'PATH':'/usr/bin:/bin'},1)
            receipt=json.loads(Path(str(log)+'.cleanup.json').read_text())
            self.assertIn('TimeoutExpired',receipt['primaryError']);self.assertIn('partial',log.read_text())
            with self.assertRaises(ProcessLookupError):os.killpg(receipt['leaderIdentity']['pid'],0)

    @unittest.skipUnless(sys.platform.startswith('linux'),'Actual Linux process-group controls')
    def test_changed_leader_identity_refuses_signal_and_preserves_timeout(self):
        children=[];popen=subprocess.Popen;stop=run_gate.stop_owned_group
        def spawn(*args,**kwargs):
            child=popen(*args,**kwargs);children.append(child);return child
        real_read=Path.read_text;reads={}
        def changed_leader(path,*args,**kwargs):
            value=real_read(path,*args,**kwargs)
            if children and path==Path('/proc')/str(children[0].pid)/'stat':
                reads[str(path)]=reads.get(str(path),0)+1
                if reads[str(path)]>=2:
                    prefix,fields=value.rsplit(')',1);parts=fields.split();parts[19]=str(int(parts[19])+1)
                    return prefix+') '+' '.join(parts)
            return value
        try:
            with tempfile.TemporaryDirectory() as folder, patch.object(run_gate.subprocess,'Popen',side_effect=spawn), \
                 patch.object(run_gate,'group_members',return_value={'complete':False,'members':[]}), \
                 patch.object(Path,'read_text',changed_leader), \
                 patch.object(run_gate,'stop_owned_group',wraps=stop) as callback:
                log=Path(folder)/'child.log'
                with self.assertRaises(subprocess.TimeoutExpired):
                    run_gate.run_child([sys.executable,'-B','-c','import time;time.sleep(3)'],log,{'PATH':'/usr/bin:/bin'},.1)
                callback.assert_not_called()
                receipt=json.loads(Path(str(log)+'.cleanup.json').read_text())
                self.assertIn('TimeoutExpired',receipt['primaryError'])
                self.assertIn('Original leader identity changed',receipt['cleanupError'])
        finally:
            for child in children:stop(child)  # Test owns this original, still-unreaped child.

if __name__=='__main__':unittest.main(verbosity=2)
