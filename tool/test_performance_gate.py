import tempfile
import copy
import json
import subprocess
import os
import importlib.util
import pathlib
import unittest

PATH=pathlib.Path(__file__).parent/'performance/gate_policy.py'
SPEC=importlib.util.spec_from_file_location('gate_policy',PATH)
import sys
policy=importlib.util.module_from_spec(SPEC);sys.modules[SPEC.name]=policy;SPEC.loader.exec_module(policy)
sys.path.insert(0,str(PATH.parent))
import run_gate

class PerformanceGateTests(unittest.TestCase):
    def test_diagnostic_timings_cannot_be_requested_as_release_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            output=pathlib.Path(directory)/'output'
            command=[sys.executable,str(PATH.parent/'run_gate.py')]
            for option in ['repo','dart','native-library','sqlite-library']:
                command.extend(['--'+option,str(pathlib.Path(directory)/option)])
            command.extend(['--output',str(output),'--diagnose-costs'])
            result=subprocess.run(command,text=True,capture_output=True,timeout=10)
            self.assertNotEqual(result.returncode,0)
            expected='requires --measure-only' if sys.platform.startswith('linux') else 'requires Linux'
            self.assertIn(expected,result.stderr)
            self.assertFalse(output.exists())
    def test_diagnostic_intervals_require_complete_exact_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            log=pathlib.Path(directory)/'observations.log'
            valid={'measurement':'broad-action','microseconds':9,'costs':{
                'complete':True,'reconciled':True,'totalUs':9,'coverageSumUs':9,
                'exclusiveCoverageUs':{'sqliteApi':3,'unclassified':6}}}
            log.write_text(json.dumps(valid)+'\n')
            self.assertEqual(run_gate.validate_cost_measurements(log),1)
            for key,value in [('complete',False),('totalUs',8),('coverageSumUs',8),
                              ('exclusiveCoverageUs',{'unclassified':8}),
                              ('exclusiveCoverageUs',{'sqliteApi':-1,'unclassified':10})]:
                invalid=copy.deepcopy(valid);invalid['costs'][key]=value
                log.write_text(json.dumps(invalid)+'\n')
                with self.assertRaisesRegex(RuntimeError,'diagnostic action costs'):
                    run_gate.validate_cost_measurements(log)
    def setUp(self):
        self.limits={'sha256':'sealed','warmups':2,'samples':5,'actionsBySize':{'dense-1':{'save':{'medianMs':100,'maxMs':150}}}}
        self.result={'correctnessPassed':True,'limitsSHA256':'sealed','size':'dense-1','observations':[{'action':'save','index':i,'warmup':i<2,'microseconds':100000} for i in range(7)]}
        self.noise={'kind':'observed-external-cpu-load','sampleWindowCovered':True,'windowSeconds':2,'cpuSomeStallMicrosecondsDelta':600000,'otherCpuMicrosecondsDelta':1100000,'ownWorkExcluded':True}
        self.binding={'source':'one','fixture':'two','limits':'three'}
    def evaluate(self):return policy.evaluate(self.result,self.limits)
    def test_boundary_is_inclusive(self):self.assertEqual(self.evaluate().status,'passed')
    def test_warmup_retained_but_excluded(self):
        self.result['observations'][0]['microseconds']=99999999
        self.assertEqual(self.evaluate().status,'passed');self.assertEqual(len(self.evaluate().summaries['save']['warmupSamplesMs']),2)
    def test_timing_excess_fails(self):
        for s in self.result['observations']:s['microseconds']=151000
        self.assertEqual(self.evaluate().status,'timing-failed')
    def test_single_maximum_excess_fails(self):
        self.result['observations'][-1]['microseconds']=150001;self.assertEqual(self.evaluate().status,'timing-failed')
    def test_missing_and_unknown_coverage_fail(self):
        self.result['observations']=[];self.assertEqual(self.evaluate().status,'correctness-failed')
        self.result['observations']=[{'action':'unknown','microseconds':0}];self.assertEqual(self.evaluate().status,'correctness-failed')
    def test_invalid_values_fail(self):
        for value in [-1,True,float('nan')]:
            self.result['observations'][0]['microseconds']=value;self.assertEqual(self.evaluate().status,'correctness-failed')
    def test_count_and_order_fail(self):
        self.result['observations'][-1]['index']=0;self.assertEqual(self.evaluate().status,'correctness-failed')
    def test_limits_binding_and_unknown_size_fail(self):
        self.result['limitsSHA256']='changed';self.assertEqual(self.evaluate().status,'correctness-failed')
        self.result['limitsSHA256']='sealed';self.result['size']='unknown';self.assertEqual(self.evaluate().status,'correctness-failed')
    def test_correctness_never_reruns(self):
        self.result['correctnessPassed']=False
        self.assertFalse(policy.may_rerun(self.evaluate(),0,self.noise,self.binding,self.binding))
    def test_extra_unclassified_sample_fails(self):
        self.result['observations'].append({'action':'save','index':7,'warmup':None,'microseconds':0})
        self.assertEqual(self.evaluate().status,'correctness-failed')
    def test_duplicate_sample_or_missing_warmup_fails(self):
        self.result['observations'][0]['warmup']=False
        self.assertEqual(self.evaluate().status,'correctness-failed')
    def test_warmups_cannot_be_swapped_with_measured_samples(self):
        self.result['observations'][0]['warmup']=False
        self.result['observations'][2]['warmup']=True
        self.assertEqual(self.evaluate().status,'correctness-failed')
    def test_reordered_or_boolean_indices_fail(self):
        self.result['observations'][0],self.result['observations'][1]=self.result['observations'][1],self.result['observations'][0]
        self.assertEqual(self.evaluate().status,'correctness-failed')
        self.result['observations'].sort(key=lambda x:x['index'])
        self.result['observations'][0]['index']=False
        self.assertEqual(self.evaluate().status,'correctness-failed')
    def test_nonfinite_or_nonpositive_limits_fail(self):
        for value in [float('nan'),float('inf'),-1,0,True]:
            self.limits['actionsBySize']['dense-1']['save']['medianMs']=value
            self.assertEqual(self.evaluate().status,'correctness-failed')
    def timing_failure(self):return policy.Evaluation('timing-failed',('save',),{})
    def test_one_noisy_timing_rerun(self):
        self.assertTrue(policy.may_rerun(self.timing_failure(),0,self.noise,self.binding,self.binding))
        self.assertFalse(policy.may_rerun(self.timing_failure(),1,self.noise,self.binding,self.binding))
    def test_changed_binding_never_reruns(self):
        self.assertFalse(policy.may_rerun(self.timing_failure(),0,self.noise,self.binding,{**self.binding,'source':'changed'}))
    def test_own_throttling_or_missing_noise_insufficient(self):
        for noise in [{},{'ownCpuThrottled':True},{**self.noise,'otherCpuMicrosecondsDelta':0},{**self.noise,'sampleWindowCovered':False}]:
            self.assertFalse(policy.may_rerun(self.timing_failure(),0,noise,self.binding,self.binding))

class RegisteredCoveragePreflightTests(unittest.TestCase):
    def setUp(self):
        self.coverage=json.loads((PATH.parent/'coverage-v1.json').read_text())
        self.limits=json.loads((PATH.parent/'limits-v1.json').read_text())
    def check(self):
        return policy.validate_registered_coverage(
            self.coverage,self.limits,run_gate.scaling_specs(self.limits))
    def test_committed_registry_matches_all_budgets_and_growth_rules(self):
        self.assertEqual(set(self.check()),set(self.coverage['storageApplicationActionIds']))
    def test_new_or_stale_registered_case_cannot_be_unbudgeted(self):
        self.coverage['storageApplicationActionIds'].append('unbudgeted.future.action')
        with self.assertRaisesRegex(ValueError,'coverage/budget'):self.check()
    def test_removed_registry_id_cannot_leave_stale_budgets(self):
        self.coverage['storageApplicationActionIds'].pop()
        with self.assertRaisesRegex(ValueError,'coverage/budget'):self.check()
    def test_duplicate_and_malformed_registry_ids_fail(self):
        original=copy.deepcopy(self.coverage)
        for value in [original['storageApplicationActionIds'][0],None,'',' trailing ']:
            with self.subTest(value=value):
                self.coverage=copy.deepcopy(original)
                self.coverage['storageApplicationActionIds'].append(value)
                with self.assertRaisesRegex(ValueError,'coverage IDs'):self.check()
    def test_missing_or_invalid_budget_in_any_shape_fails(self):
        for size in self.limits['actionsBySize']:
            original=copy.deepcopy(self.limits)
            action=self.coverage['storageApplicationActionIds'][0]
            with self.subTest(size=size,kind='missing'):
                del self.limits['actionsBySize'][size][action]
                with self.assertRaisesRegex(ValueError,'coverage/budget'):self.check()
            self.limits=copy.deepcopy(original)
            for value in [0,True,float('inf')]:
                with self.subTest(size=size,value=value):
                    self.limits['actionsBySize'][size][action]['maxMs']=value
                    with self.assertRaisesRegex(ValueError,'invalid budget'):self.check()
                self.limits=copy.deepcopy(original)
    def test_stale_id_in_either_growth_comparison_fails(self):
        comparisons=run_gate.scaling_specs(self.limits)
        for name in comparisons:
            modified=copy.deepcopy(comparisons)
            action=self.coverage['storageApplicationActionIds'][0]
            del modified[name]['rules'][action]
            with self.subTest(comparison=name):
                with self.assertRaisesRegex(ValueError,'coverage/growth'):
                    policy.validate_registered_coverage(self.coverage,self.limits,modified)
    @unittest.skipUnless(sys.platform.startswith('linux'),'Linux runner preflight')
    def test_stale_registry_fails_measure_only_before_source_fork_or_compiler(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);tools=root/'tools';tools.mkdir()
            for name in ['run_gate.py','gate_policy.py','reference_receipt.py','limits-v1.json']:
                (tools/name).write_bytes((PATH.parent/name).read_bytes())
            self.coverage['storageApplicationActionIds'].append('unbudgeted.future.action')
            (tools/'coverage-v1.json').write_text(json.dumps(self.coverage))
            output=root/'output'
            result=subprocess.run([sys.executable,str(tools/'run_gate.py'),
                '--repo',str(root/'unavailable-repo'),'--dart',str(root/'unavailable-dart'),
                '--native-library',str(root/'native'),'--sqlite-library',str(root/'sqlite'),
                '--output',str(output),'--measure-only'],capture_output=True,text=True,timeout=10)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('Registered performance coverage/budget IDs differ',result.stderr)
            self.assertFalse((output/'source').exists())
            self.assertFalse((output/'compile.log').exists())

class RunnerReceiptTests(unittest.TestCase):
    def test_measurements_keep_explicit_warmups_and_startup_components(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=pathlib.Path(tmp)/'log'
            p.write_text('\n'.join(json.dumps(x) for x in [
                {'measurement':'broad-action','action':'save','index':0,'warmup':True,'microseconds':12},
                {'measurement':'broad-startup','index':-1,'freshProfile':True},
                {'measurement':'broad-startup','index':2,'warmup':False,'freshProfile':False,'totalUs':10,'historyUs':8,'taskAttachUs':1,'proofUs':2,'cacheRestoreUs':3},
                {'measurement':'broad-all-pass'}]))
            rows,complete=run_gate.measurements(p)
            self.assertTrue(complete);self.assertEqual(len(rows),6)
            self.assertTrue(rows[0]['warmup']);self.assertIn('startup.warm.proof',[x['action'] for x in rows])
    @unittest.skipUnless(sys.platform.startswith('linux'), 'Linux runner preflight')
    def test_unbound_limits_fail_before_compiler_or_fixture_execution(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);output=root/'output'
            command=[sys.executable,str(PATH.parent/'run_gate.py'),'--repo',str(root),
                     '--dart',str(root/'unavailable-dart'),'--native-library',str(root/'native'),
                     '--sqlite-library',str(root/'sqlite'),'--output',str(output),
                     '--expected-limits-sha256','not-the-versioned-limits-sha']
            result=subprocess.run(command,capture_output=True,text=True,timeout=10)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('limits are inactive or not workflow-bound',result.stderr)
            self.assertFalse((output/'compile.log').exists())
            self.assertFalse((output/'gate-result.json').exists())
    def test_release_resource_bounds_fail_closed(self):
        valid={'memory.max':str(6*1024**3),'memory.swap.max':'0','cpu.max':'200000 100000','pids.max':'128'}
        run_gate.require_release_bounds(valid)
        for key,value in [('memory.max','max'),('memory.swap.max','1'),('cpu.max','max 100000'),('cpu.max','300000 100000'),('pids.max','129')]:
            with self.assertRaises(RuntimeError):run_gate.require_release_bounds({**valid,key:value})
        with self.assertRaises(RuntimeError):run_gate.require_release_bounds({})
    def test_changed_binary_or_manifest_binding_never_accepts(self):
        original={'binary':'a','fixtures':{'small':'b'}}
        for current in [{'binary':'changed','fixtures':{'small':'b'}},{'binary':'a','fixtures':{'small':'changed'}}]:
            with self.assertRaises(RuntimeError):run_gate.require_binding(original,current)
        run_gate.require_binding(original,dict(original))
    def test_fixture_inventory_and_manifest_are_sealed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);workspace=root/'workspace';workspace.mkdir()
            data=workspace/'history';data.write_text('original')
            receipt={'workspace':str(workspace),'files':{'history':run_gate.digest(data)}}
            manifest=root/'fixture.json';run_gate.write_new(manifest,receipt)
            fixtures={'small':{'manifest':manifest,'receipt':receipt}}
            original=run_gate.fixture_binding(fixtures)
            extra=workspace/'unexpected';extra.write_text('extra')
            with self.assertRaises(RuntimeError):run_gate.fixture_binding(fixtures)
            extra.unlink();manifest.write_text('{}')
            with self.assertRaises(RuntimeError):run_gate.fixture_binding(fixtures)
    def test_missing_success_receipt_is_not_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=pathlib.Path(tmp)/'log';p.write_text('not json\n')
            self.assertEqual(run_gate.measurements(p),([],False))
    def test_output_receipt_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=pathlib.Path(tmp)/'receipt';run_gate.write_new(p,{'first':True})
            with self.assertRaises(FileExistsError):run_gate.write_new(p,{'second':True})
            self.assertEqual(json.loads(p.read_text()),{'first':True})

class PairedScalingTests(unittest.TestCase):
    def setUp(self):
        self.rules={'smallSize':'one','largeSize':'two','rules':{'save':{'maxMedianRatio':2,'medianAdditiveMs':10,'maxMaximumRatio':2.5,'maximumAdditiveMs':20}}}
        base={'syntheticOnly':True,'currentStateSHA256':'a'*64,'taskRows':10,'foodContainers':5,'initialPrefixSHA256':{str(i):'b'*64 for i in range(3)},'initialHistoricalRecords':1320,'growthHistoricalRecords':0,'actualPhysicalRecords':1325,'baseHistoricalRecords':1320,'growthKind':'none','initialTaskEffects':1000,'initialFoodEffects':320,'growthTaskEffects':0,'growthFoodEffects':0,'taskEffects':1005,'foodEffects':320}
        self.contracts={'one':base,'two':{**base,'growthHistoricalRecords':1320,'actualPhysicalRecords':2645,'baseHistoricalRecords':2640,'growthKind':'task','growthTaskEffects':1320,'taskEffects':2325}}
        self.summaries={'one':{'save':{'medianMs':100,'maxMs':120}},'two':{'save':{'medianMs':210,'maxMs':320}}}
    def test_invalid_scaling_limits_fail_closed(self):
        for value in [float('nan'),float('inf'),-1,True]:
            self.rules['rules']['save']['maxMedianRatio']=value
            self.assertEqual(policy.evaluate_scaling(self.summaries,self.rules,self.contracts).status,'correctness-failed')
    def test_ratio_plus_additive_boundary_passes(self):
        result=policy.evaluate_scaling(self.summaries,self.rules,self.contracts)
        self.assertEqual(result.status,'passed');self.assertEqual(result.summaries['save']['medianBoundMs'],210)
    def test_median_or_maximum_superlinear_growth_fails(self):
        for field,value in [('medianMs',211),('maxMs',321)]:
            original=self.summaries['two']['save'][field];self.summaries['two']['save'][field]=value
            self.assertEqual(policy.evaluate_scaling(self.summaries,self.rules,self.contracts).status,'timing-failed')
            self.summaries['two']['save'][field]=original
    def test_current_state_growth_is_not_history_only_scaling(self):
        for field,value in [('taskRows',11),('foodContainers',6),('currentStateSHA256','changed')]:
            original=self.contracts['two'][field];self.contracts['two'][field]=value
            self.assertEqual(policy.evaluate_scaling(self.summaries,self.rules,self.contracts).status,'correctness-failed')
            self.contracts['two'][field]=original
    def test_prefix_or_actual_record_growth_mismatch_fails(self):
        self.contracts['two']['initialPrefixSHA256']={};self.assertEqual(policy.evaluate_scaling(self.summaries,self.rules,self.contracts).status,'correctness-failed')
    def test_paired_action_coverage_is_exact(self):
        self.summaries['two']={};self.assertEqual(policy.evaluate_scaling(self.summaries,self.rules,self.contracts).status,'correctness-failed')

class AdditiveFoodScalingTests(PairedScalingTests):
    def setUp(self):
        super().setUp()
        self.rules['growthKind'] = 'food'
        self.contracts['two'].update(growthKind='food', growthTaskEffects=0,
                                     growthFoodEffects=1320, taskEffects=1005, foodEffects=1640)
    def test_wrong_module_or_missing_growth_claim_refuses(self):
        for field, value in [('growthKind', 'task'), ('growthKind', 'unknown'),
                             ('growthTaskEffects', 1), ('growthFoodEffects', 1319),
                             ('foodEffects', 1639), ('taskEffects', 1006),
                             ('growthFoodEffects', True)]:
            original = self.contracts['two'][field]
            self.contracts['two'][field] = value
            self.assertEqual(policy.evaluate_scaling(self.summaries,self.rules,self.contracts).status,
                             'correctness-failed', (field, value))
            self.contracts['two'][field] = original
        del self.contracts['two']['growthKind']
        self.assertEqual(policy.evaluate_scaling(self.summaries,self.rules,self.contracts).status,
                         'correctness-failed')
    def test_non_task_food_scaling_kind_refuses(self):
        self.rules['growthKind'] = 'other'
        self.assertEqual(policy.evaluate_scaling(self.summaries,self.rules,self.contracts).status,
                         'correctness-failed')

class AdditiveFixtureConfigTests(unittest.TestCase):
    def test_legacy_args_unchanged_and_food_arg_closed(self):
        for value in (60,1320,2640):
            self.assertEqual(run_gate.fixture_argument(value),str(value))
        self.assertEqual(run_gate.fixture_argument({'baseRecords':2640,'growthKind':'food'}),'food:2640')
        for value in (True,'2640',{'baseRecords':1320,'growthKind':'food'},
                      {'baseRecords':2640,'growthKind':'task'},
                      {'baseRecords':2640,'growthKind':'food','extra':True}):
            with self.assertRaises(RuntimeError):run_gate.fixture_argument(value)
    def test_original146_and_converted_metrics_and_both_legacy_shapes_retained(self):
        limits=json.loads((PATH.parent/'limits-v1.json').read_text())
        coverage=json.loads((PATH.parent/'coverage-v1.json').read_text())['storageApplicationActionIds']
        frozen=json.loads((PATH.parent/'original-action-ids-v1.json').read_text())['actions']
        self.assertEqual(len(frozen),146)
        self.assertTrue(set(frozen).issubset(coverage))
        self.assertEqual(len(coverage),232)
        for action in ('firstDerived.metadata.tags', 'firstDerived.metadata.tags.undo', 'firstCopied.metadata.complete', 'firstCopied.metadata.complete.undo', 'firstDerived.mixed.save', 'firstDerived.mixed.undo'):
            self.assertIn(action,coverage)
        for action in ("converted.food.paired.details.confirmedSave", "converted.food.paired.details.confirmedUndo"):
            self.assertIn(action,coverage)
        self.assertEqual(sum(action.startswith("cardinality500.") for action in coverage),33)
        for action in ("cardinality500.food.paired.details.save",
                       "cardinality500.food.add.1", "cardinality500.food.restore.3",
                       "cardinality500.food.view.inventory", "cardinality500.food.matched.search",
                       "cardinality500.refresh.food.unchanged"):
            self.assertIn(action,coverage)
        self.assertEqual(len(set(coverage)),len(coverage))
        confirmed = {'converted.food.paired.details.confirmedSave',
                     'converted.food.paired.details.confirmedUndo'}
        self.assertEqual(sum(action.startswith('converted.') and action not in confirmed
                             for action in coverage),45)
        self.assertTrue(confirmed.issubset(coverage))
        for action in ('converted.task.title.save','converted.task.title.undo',
                       'converted.task.complete.application','converted.task.delete',
                       'converted.task.bulkEdit.three','converted.checklist.add',
                       'converted.food.paired.details.save','converted.food.paired.details.undo'):
            self.assertIn(action,coverage)
        self.assertEqual(limits['historySizes']['dense-1'],1320)
        self.assertEqual(limits['historySizes']['dense-2'],2640)
        self.assertTrue(limits['releaseReady'])
        for values in limits['actionsBySize'].values():
            self.assertEqual(set(values),set(coverage))
        specs=run_gate.scaling_specs(limits)
        self.assertEqual(set(specs),{'task-own-history','food-own-history'})
        for spec in specs.values():self.assertEqual(set(spec['rules']),set(coverage))
        ordinary=lambda values:{k:v for k,v in values.items() if not k.startswith('startup.')}
        self.assertEqual(ordinary(limits['actionsBySize']['dense-food']),ordinary(limits['actionsBySize']['dense-2']))
        self.assertEqual(set(limits['actionsBySize']['dense-food']),set(limits['actionsBySize']['dense-2']))
        self.assertEqual(specs['food-own-history']['rules'],specs['task-own-history']['rules'])
        del limits['additionalPairedScaling']
        with self.assertRaises(RuntimeError):run_gate.scaling_specs(limits)
    def test_each_pair_large_size_needs_noise_and_no_second_retry(self):
        clean={'kind':'observed-external-cpu-load','sampleWindowCovered':True,
               'windowSeconds':2,'cpuSomeStallMicrosecondsDelta':600000,
               'otherCpuMicrosecondsDelta':1100000,'ownWorkExcluded':True}
        passed=policy.Evaluation('passed',(),{})
        failed=policy.Evaluation('timing-failed',('save',),{})
        decisions={n:passed for n in ('small','task','food')}
        pairs=[({'largeSize':'task'},failed),({'largeSize':'food'},failed)]
        executions={n:{'noise':dict(clean)} for n in decisions}
        binding={'all3fixtures':'sealed'}
        self.assertTrue(run_gate.may_rerun_all(decisions,pairs,0,executions,binding,binding))
        executions['food']['noise']={}
        self.assertFalse(run_gate.may_rerun_all(decisions,pairs,0,executions,binding,binding))
        executions['food']['noise']=dict(clean)
        decisions['small']=failed;executions['small']['noise']={}
        self.assertFalse(run_gate.may_rerun_all(decisions,pairs,0,executions,binding,binding))
        decisions['small']=passed
        self.assertFalse(run_gate.may_rerun_all(decisions,pairs,1,executions,binding,binding))
        self.assertFalse(run_gate.may_rerun_all(decisions,pairs,0,executions,binding,{'changed':True}))
        decisions['food']=policy.Evaluation('correctness-failed',('coverage',),{})
        self.assertFalse(run_gate.may_rerun_all(decisions,pairs,0,executions,binding,binding))
    def test_bad_pair_size_or_module_cannot_drop_food_comparison(self):
        limits=json.loads((PATH.parent/'limits-v1.json').read_text())
        for field,value in [('largeSize','dense-2'),('growthKind','task')]:
            original=limits['additionalPairedScaling']['food-own-history'][field]
            limits['additionalPairedScaling']['food-own-history'][field]=value
            with self.assertRaises(RuntimeError):run_gate.scaling_specs(limits)
            limits['additionalPairedScaling']['food-own-history'][field]=original

@unittest.skipUnless(os.name=='posix','Standalone AOT runner targets Linux')
class SourceBindingTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=pathlib.Path(self.tmp.name)
        self.repo=self.root/'repo';(self.repo/'lib').mkdir(parents=True);(self.repo/'.dart_tool').mkdir()
        (self.repo/'pubspec.yaml').write_text('name: tandemlog\n');(self.repo/'pubspec.lock').write_text('packages: {}\n');(self.repo/'lib/main.dart').write_text("import 'dart:async';\n")
        (self.repo/'.dart_tool/package_config.json').write_text(json.dumps({'configVersion':2,'packages':[{'name':'tandemlog','rootUri':'../','packageUri':'lib/','languageVersion':'3.9'}]}))
        self.output=self.root/'output';self.output.mkdir();self.tools=self.root/'tools';self.tools.mkdir();(self.tools/'benchmark.dart').write_text("import 'package:tandemlog/main.dart';\n")
    def test_owned_fork_compiles_exact_source_no_shims(self):
        config,pins,seals,names=run_gate.create_owned_source_fork(self.repo,self.output)
        self.assertTrue(all(x['originalSHA256']==x['compiledSHA256'] and x['change']=='none' for x in seals.values()))
        self.assertEqual(json.loads(config.read_text())['packages'][0]['rootUri'],(self.output/'source').as_uri()+'/')
        self.assertEqual(len(run_gate.validate_project_imports(self.tools/'benchmark.dart',self.output/'source',names)),2)
    def test_absolute_owned_library_is_rebound_to_exact_fork(self):
        p=self.repo/'.dart_tool/package_config.json';c=json.loads(p.read_text());c['packages'][0]['packageUri']=(self.repo/'lib').as_uri()+'/';p.write_text(json.dumps(c))
        config,_,_,_=run_gate.create_owned_source_fork(self.repo,self.output)
        self.assertEqual(json.loads(config.read_text())['packages'][0]['packageUri'],'lib/')
    def test_correct_root_with_external_package_library_is_rejected(self):
        p=self.repo/'.dart_tool/package_config.json';c=json.loads(p.read_text());c['packages'][0]['packageUri']='../other-lib/';p.write_text(json.dumps(c))
        with self.assertRaises(RuntimeError):run_gate.create_owned_source_fork(self.repo,self.output)
    def test_dependency_package_library_escape_is_rejected(self):
        p=self.repo/'.dart_tool/package_config.json';c=json.loads(p.read_text())
        dependency=self.root/'dependency';dependency.mkdir()
        c['packages'].append({'name':'dep','rootUri':dependency.as_uri()+'/','packageUri':'../outside/'})
        p.write_text(json.dumps(c))
        with self.assertRaises(RuntimeError):run_gate.create_owned_source_fork(self.repo,self.output)
    def test_stale_external_package_source_is_rejected(self):
        p=self.repo/'.dart_tool/package_config.json';c=json.loads(p.read_text());c['packages'][0]['rootUri']='../other';p.write_text(json.dumps(c))
        with self.assertRaises(RuntimeError):run_gate.create_owned_source_fork(self.repo,self.output)
    def test_unapproved_flutter_import_is_rejected(self):
        (self.repo/'lib/main.dart').write_text("import 'package:flutter/foundation.dart';\n")
        _,_,_,names=run_gate.create_owned_source_fork(self.repo,self.output)
        with self.assertRaises(RuntimeError):run_gate.validate_project_imports(self.tools/'benchmark.dart',self.output/'source',names)
    def test_unexpected_relative_import_escape_is_rejected(self):
        (self.repo/'lib/main.dart').write_text("import '../../secret.dart';\n")
        _,_,_,names=run_gate.create_owned_source_fork(self.repo,self.output)
        with self.assertRaises(RuntimeError):run_gate.validate_project_imports(self.tools/'benchmark.dart',self.output/'source',names)
    def test_host_noise_subtracts_own_cpu(self):
        before={'pressure':0,'hostBusyTicks':100,'ticksPerSecond':100,'ownCpuMicroseconds':0}
        after={'pressure':300000,'hostBusyTicks':200,'ticksPerSecond':100,'ownCpuMicroseconds':400000}
        evidence=run_gate.noise_evidence(before,after,1);self.assertEqual(evidence['otherCpuMicrosecondsDelta'],600000);self.assertTrue(policy.external_noise_overlapped(evidence))
        after['ownCpuMicroseconds']=1000000;self.assertFalse(policy.external_noise_overlapped(run_gate.noise_evidence(before,after,1)))

@unittest.skipUnless(sys.platform.startswith('linux'), 'Linux CI wrapper')
class CIWrapperTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=pathlib.Path(self.tmp.name);bin_dir=self.root/'bin';bin_dir.mkdir()
        self.args=self.root/'arguments.json'
        for name,body in {
            'flutter':'#!/bin/sh\nexit 99\n',
            'timeout':'#!/bin/sh\nshift 3\nexec "$@"\n',
            'sudo':"""#!/usr/bin/python3
import json,os,sys
from pathlib import Path
args=sys.argv[1:]
if args[0]=='-n':args=args[1:]
if args[0]=='systemd-run':
 Path(os.environ['FAKE_ARGUMENTS']).write_text(json.dumps(args))
 sys.exit(int(os.environ.get('FAKE_SERVICE_EXIT','0')))
if args[:2]==['systemctl','stop']:sys.exit(0)
if args[:2]==['systemctl','show']:
 mode=os.environ.get('FAKE_MANAGER','absent')
 if mode=='unavailable':sys.exit(1)
 if mode=='empty':sys.exit(0)
 print('LoadState='+('loaded' if mode=='live' else 'not-found'))
 print('ActiveState='+('active' if mode=='live' else 'inactive'))
 print('MainPID='+('123' if mode=='live' else '0'))
 sys.exit(0)
sys.exit(98)
"""
        }.items():
            f=bin_dir/name;f.write_text(body);f.chmod(0o700)
        (self.root/'.dart_tool/lib').mkdir(parents=True)
        (self.root/'.dart_tool/lib/libsqlite3.so').write_bytes(b'fake prerequisite only')
        native=self.root/'native';native.write_bytes(b'fake prerequisite only')
        self.env={**os.environ,'PATH':str(bin_dir)+':'+os.defpath,
                  'RUNNER_TEMP':str(self.root),'GITHUB_RUN_ID':'wrapper-test',
                  'GITHUB_RUN_ATTEMPT':'1','TANDEMLOG_TEXT_LIBRARY':str(native),
                  'FAKE_ARGUMENTS':str(self.args)}
    def run_wrapper(self,*mode,**env):
        return subprocess.run(['bash',str(PATH.parent/'run_ci.sh'),'sealed',*mode],
                              cwd=self.root,env={**self.env,**env},
                              capture_output=True,text=True,timeout=10)
    def test_explicit_calibration_forwarding_and_resource_caps(self):
        result=self.run_wrapper('--measure-only')
        self.assertEqual(result.returncode,0,result.stderr)
        args=json.loads(self.args.read_text())
        for value in ['--property=MemoryMax=6G','--property=MemorySwapMax=0',
                      '--property=CPUQuota=200%','--property=TasksMax=128',
                      '--property=RuntimeMaxSec=3300','--property=KillMode=control-group']:
            self.assertIn(value,args)
        self.assertEqual(args[-1],'--measure-only')
        self.assertIn('load=not-found state=inactive pid=0',result.stdout)
    def test_enforcing_path_has_no_calibration_flag(self):
        result=self.run_wrapper()
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertNotIn('--measure-only',json.loads(self.args.read_text()))
    def test_hosted_advisory_preserves_caps_and_is_explicit(self):
        result=self.run_wrapper('--hosted-advisory')
        self.assertEqual(result.returncode,0,result.stderr)
        args=json.loads(self.args.read_text())
        self.assertEqual(args[-1],'--hosted-advisory')
        self.assertNotIn('--measure-only',args)
        self.assertIn('--property=MemorySwapMax=0',args)
    def test_unverified_or_live_cleanup_fails(self):
        for mode in ['unavailable','empty','live']:
            result=self.run_wrapper(FAKE_MANAGER=mode)
            self.assertNotEqual(result.returncode,0,mode)
    def test_original_failure_survives_cleanup_failure(self):
        result=self.run_wrapper(FAKE_SERVICE_EXIT='42',FAKE_MANAGER='unavailable')
        self.assertEqual(result.returncode,42)
    def test_unknown_mode_is_rejected_before_service_start(self):
        result=self.run_wrapper('--not-a-mode')
        self.assertEqual(result.returncode,2)
        self.assertFalse(self.args.exists())



class CalibratedInitialLimitTests(unittest.TestCase):
    def test_initial_policy_is_bound_to_workflow_and_keeps_ui_separate(self):
        import hashlib
        path=PATH.parent/'limits-v1.json'
        limits=json.loads(path.read_text())
        workflow=(PATH.parents[2]/'.github/workflows/validate.yml').read_text()
        self.assertIn('limits_sha="'+hashlib.sha256(path.read_bytes()).hexdigest()+'"',workflow)
        self.assertTrue(limits['releaseReady'])
        self.assertFalse(limits['calibration']['actualUIAccepted'])
        self.assertFalse(limits['calibration']['policyOnlyReevaluationIsFreshEnforcingRun'])
    def test_ordinary_target_and_both_tight_pairs_keep_all_actions(self):
        limits=json.loads((PATH.parent/'limits-v1.json').read_text())
        for values in limits['actionsBySize'].values():
            ordinary={k:v for k,v in values.items() if not k.startswith('startup.')}
            self.assertEqual(len(ordinary),224)
            self.assertEqual(len(values)-len(ordinary),8)
            for bound in ordinary.values():
                self.assertLessEqual(bound['medianMs'],bound['maxMs'])
                self.assertLessEqual(bound['maxMs'],100)
        for spec in run_gate.scaling_specs(limits).values():
            for action,rule in spec['rules'].items():
                startup=action.startswith('startup.')
                self.assertEqual(rule['medianAdditiveMs'],100 if startup else 3)
                self.assertEqual(rule['maximumAdditiveMs'],200 if startup else 5)
                self.assertEqual(rule['maxMedianRatio'],2.25 if startup else 1.25)
                self.assertEqual(rule['maxMaximumRatio'],2.5 if startup else 1.4)

if __name__=='__main__':unittest.main()
