"""Separately frozen before admission identity/work budget implementation."""
import unittest, base64
import test_contract as contract
import test_admission as admission
class Units(unittest.TestCase):
 setUp=contract.Contract.setUp
 def owner(self, units=10):
  seed=self.b.ok('seed',text='abc')['update']
  return self.b.ok('new',name='a',client=10,seed=seed,limits={'admissionUnits':units,'visibleUtf16':10000,'updateBytes':1048576})
 def test_U01_large_plaintext_inspect_rejected_preflight(self):
  r=self.b.request(op='inspect',update=admission.packet(content=admission.buf('x'*100001)))
  self.assertIn('admission',r.get('error',''))
 def test_U02_explicit_inspector_units(self):
  p=admission.packet(content=admission.buf('x'*20))
  self.assertIn('error',self.b.request(op='inspect',update=p,admissionUnits=19))
  self.assertEqual(self.b.ok('inspect',update=p,admissionUnits=20)['structActors'],[50])
 def test_U03_retained_deleted_identity_budget_preserves_undo(self):
  self.owner(5)
  self.b.ok('edit',name='a',index=0,delete=1,insert='L')
  self.b.ok('edit',name='a',index=0,delete=1,insert='M')
  before=self.b.ok('state',name='a')['update']
  self.assertIn('admission',self.b.request(op='edit',name='a',index=0,delete=1,insert='N').get('error',''))
  self.assertEqual(self.b.ok('state',name='a')['update'],before)
  self.b.ok('undo',name='a');self.assertEqual(self.b.ok('read',name='a')['text'],'Lbc')
 def test_U04_remote_combined_budget_atomic(self):
  self.owner(5);self.b.ok('edit',name='a',index=0,delete=1,insert='L')
  p=admission.packet(content=admission.buf('XYZ'))
  before=self.b.ok('state',name='a')['update']
  self.assertIn('admission',self.b.request(op='apply',name='a',update=p).get('error',''))
  self.assertEqual(before,self.b.ok('state',name='a')['update'])
 def test_U05_skips_and_delete_ranges_have_work_budget(self):
  p=base64.b64encode(bytes([1,1,50,0,10,11,0])).decode()
  self.assertIn('error',self.b.request(op='inspect',update=p,admissionUnits=10))
  p=base64.b64encode(bytes([0,1,50,2,0,1,2,1])).decode()
  self.assertIn('error',self.b.request(op='inspect',update=p,admissionUnits=1))
 def test_U06_restore_draft_inherit_and_validation(self):
  self.owner(4);self.b.ok('draft',name='d',source='a',client=30)
  self.b.ok('edit',name='d',index=0,delete=1,insert='L')
  self.assertIn('error',self.b.request(op='edit',name='d',index=0,delete=1,insert='M'))
  cp=self.b.ok('checkpoint',name='d')['checkpoint']
  self.assertIn('error',self.b.request(op='restore',name='r',client=40,checkpoint=cp,limits={'admissionUnits':3}))
  for v in [0,True,-1,8388609]:self.assertIn('error',self.b.request(op='inspect',update=admission.packet(),admissionUnits=v))
if __name__=='__main__':unittest.main(verbosity=2)
