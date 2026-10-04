import copy
import unittest
from attach_preview_assets import validate_draft, missing_assets

class DraftGate(unittest.TestCase):
    def setUp(self):
        self.meta={'id':41,'tag_name':'v2026.10.2-rc.1','target_commitish':'a'*40,'draft':True,'prerelease':True,'assets':[]}
        self.expected={'preview.apk':{'size':3,'digest':'sha256:'+'b'*64}}
    def test_exact_private_preview_is_admitted(self):
        validate_draft(self.meta,41,'v2026.10.2-rc.1','a'*40)
        self.assertEqual(missing_assets(self.meta['assets'],self.expected),['preview.apk'])
    def test_wrong_identity_or_public_or_stable_is_rejected(self):
        for key,value in [('id',42),('tag_name','v2026.10.1'),('target_commitish','c'*40),('draft',False),('prerelease',False)]:
            m=copy.deepcopy(self.meta);m[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):validate_draft(m,41,'v2026.10.2-rc.1','a'*40)
    def test_matching_partial_upload_is_retained(self):
        assets=[{'name':'preview.apk','state':'uploaded',**self.expected['preview.apk']}]
        self.assertEqual(missing_assets(assets,self.expected),[])
    def test_bad_or_extra_or_duplicate_assets_are_rejected(self):
        valid={'name':'preview.apk','state':'uploaded',**self.expected['preview.apk']}
        for bad in [[dict(valid,size=4)],[dict(valid,digest='sha256:'+'c'*64)],[dict(valid,state='starter')],[dict(valid,name='extra')],[valid,valid]]:
            with self.subTest(bad=bad),self.assertRaises(ValueError):missing_assets(bad,self.expected)
