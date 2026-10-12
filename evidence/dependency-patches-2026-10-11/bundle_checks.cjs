const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');

const awaiter = (self, args, ignored, generator) => new Promise((resolve, reject) => {
  const it = generator.apply(self, args || []);
  const advance = (method, value) => {
    let next;
    try { next = it[method](value); } catch (err) { reject(err); return; }
    if (next.done) resolve(next.value);
    else Promise.resolve(next.value).then(x => advance('next', x), x => advance('throw', x));
  };
  advance('next');
});

async function check(file) {
  const source = fs.readFileSync(file, 'utf8');
  const start = source.indexOf('class ArtifactHttpClient {');
  const end = source.indexOf('\nfunction internalArtifactTwirpClient', start);
  assert(start >= 0 && end > start);
  class UsageError extends Error { static isUsageErrorMessage() { return false; } }
  class NetworkError extends Error { static isNetworkErrorCode() { return false; } }
  const context = vm.createContext({
    artifact_twirp_client_awaiter: awaiter, UsageError, NetworkError,
    core_debug() {}, info() {}, maskSecretUrls() {}, getRuntimeToken() { return 'synthetic'; },
    getResultsServiceUrl() { return 'https://synthetic.invalid'; },
    lib_HttpClient: class {}, auth_BearerCredentialHandler: class {},
    HttpCodes: {TooManyRequests:429, BadGateway:502, GatewayTimeout:504,
      InternalServerError:500, ServiceUnavailable:503},
  });
  vm.runInContext(source.slice(start, end) + '\nthis.Client = ArtifactHttpClient;', context);
  const fresh = () => {
    const client = new context.Client('synthetic');
    client.waits = [];
    client.sleep = async ms => client.waits.push(ms);
    assert.equal(client.maxAttempts, 5);
    assert.equal(client.baseRetryIntervalMilliseconds, 8000);
    assert.equal(client.retryTimeoutMilliseconds, 120000);
    return client;
  };
  const response = (status, header) => ({message:{statusCode:status,headers:{'retry-after':header}},
    async readBody() { return '{}'; }});
  for (const [value, expected] of [[undefined,undefined],['0',undefined],['-1',undefined],
      ['Wed, 21 Oct 2026 07:28:00 GMT',undefined],['5',5],[' 6 ',6],[['3'],3]]) {
    assert.equal(fresh().getRetryAfterSeconds(response(429,value)),expected);
  }
  let client = fresh(), calls = 0;
  await client.retryableRequest(async () => response(++calls < 5 ? 429 : 200, '30'));
  assert.equal(calls,5);
  assert.deepEqual(client.waits,[30000,30000,30000,30000]);
  client = fresh(); calls = 0;
  await assert.rejects(client.retryableRequest(async () => {
    calls++; return response(429,'121');
  }), /exceed/);
  assert.equal(calls,1); assert.deepEqual(client.waits,[]);
  client = fresh(); calls = 0;
  await assert.rejects(client.retryableRequest(async () => {
    calls++; return response(429,'1');
  }), /5 attempts/);
  assert.equal(calls,5); assert.deepEqual(client.waits,[1000,1000,1000,1000]);
  client = fresh(); calls = 0;
  await client.retryableRequest(async () => response(++calls === 1 ? 429 : 200, 'invalid'));
  assert.deepEqual(client.waits,[8000]);
  const uaStart = source.indexOf('function getUserAgentWithOrchestrationId(');
  const uaEnd = source.indexOf('\n//# sourceMappingURL',uaStart);
  const uaContext = vm.createContext({process:{env:{ACTIONS_ORCHESTRATION_ID:' abc\r\n/東京 '}}});
  vm.runInContext(source.slice(uaStart,uaEnd), uaContext);
  const ua = uaContext.getUserAgentWithOrchestrationId('audit');
  assert.equal(ua,'audit actions_orchestration_id/abc_____');
  assert.equal(uaContext.getUserAgentWithOrchestrationId(ua),ua);
  if (file.includes('download')) {
    const jsonStart = source.indexOf('const noiseValue =');
    const jsonEnd = source.indexOf(';// CONCATENATED MODULE: ./node_modules/@octokit/request-error',jsonStart);
    const jsonContext = vm.createContext({});
    vm.runInContext(source.slice(jsonStart,jsonEnd) + '\nthis.parse = JSONParse; this.stringify = JSONStringify;',jsonContext);
    const parsed = jsonContext.parse('{"id":9007199254740993,"text":"9007199254740993n","small":3}');
    assert.equal(parsed.id,9007199254740993n);
    assert.equal(parsed.text,'9007199254740993n'); assert.equal(parsed.small,3);
    assert.equal(jsonContext.stringify(parsed),'{"id":9007199254740993,"text":"9007199254740993n","small":3}');
  } else {
    const filenameStart = source.indexOf('const filenameStar =');
    const filenameEnd = source.indexOf('core_debug(`Content-Type:',filenameStart);
    const filenameContext = vm.createContext({external_path_:path,
      contentDisposition:"attachment; filename=ascii.txt; filename*=UTF-8''..%2Fcaf%C3%A9%20%E6%9D%B1%E4%BA%AC.txt"});
    vm.runInContext('let fileName = "artifact";\n' + source.slice(filenameStart,filenameEnd) + '\nthis.result = fileName;',filenameContext);
    assert.equal(filenameContext.result,'café 東京.txt');
  }
  console.log(JSON.stringify({bundle:file,sha256:require('node:crypto').createHash('sha256').update(source).digest('hex'),
    result:'PASS',coverage:'actual extracted bundle: retry bounds/header parsing/UA; BigInt or UTF-8 basename'}));
}

(async () => {
  for (const file of process.argv.slice(2)) await check(file);
})().catch(error => { console.error(error); process.exitCode = 1; });
