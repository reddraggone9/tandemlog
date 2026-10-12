import pathlib,os,json,subprocess,ssl,http.server,socketserver,threading,hashlib,datetime,zipfile,io
assert os.getuid()==1002
p=pathlib.Path('/home/nibbler/gradle-security-audit-20261012/policy-qualification');root=p/'regression-v6';assert not root.exists();root.mkdir(mode=0o700)
java=pathlib.Path('/home/nibbler/java/jdk-21.0.12.1+1-jre');gradle='/home/nibbler/gradle-security-audit-20261012/gradle-9.4.1/bin/gradle';policy=(p/'repository-policy.init.gradle').read_text();requests=[]
subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(root/'key.pem'),'-out',str(root/'cert.pem'),'-days','1','-subj','/CN=localhost','-addext','subjectAltName=IP:127.0.0.1,DNS:localhost'],check=True,capture_output=True)
subprocess.run([str(java/'bin/keytool'),'-importcert','-noprompt','-alias','fixture-only','-file',str(root/'cert.pem'),'-keystore',str(root/'fixture-trust.jks'),'-storepass','synthetic-fixture'],check=True,capture_output=True)
jar=io.BytesIO()
with zipfile.ZipFile(jar,'w') as z:z.writestr('SYNTHETIC_ONLY.txt','Harmless fallback sentinel; never installed or executed as app code.\n')
pluginSource=root/'SyntheticPlugin.groovy';pluginSource.write_text("import org.gradle.api.Plugin\nclass SyntheticPlugin implements Plugin<Object> { void apply(Object target) { println 'SYNTHETIC_PLUGIN_APPLIED' } }\n");classes=root/'classes';classes.mkdir();cp=':'.join(str(x) for x in pathlib.Path(gradle).parent.parent.glob('lib/*.jar'));subprocess.run([str(java/'bin/java'),'-cp',cp,'org.codehaus.groovy.tools.FileSystemCompiler','-classpath',cp,'-d',str(classes),str(pluginSource)],check=True,capture_output=True)
pluginJar=io.BytesIO()
with zipfile.ZipFile(pluginJar,'w') as z:
 for f in classes.glob('*.class'):z.write(f,f.name)
 z.writestr('META-INF/gradle-plugins/com.android.synthetic.properties','implementation-class=SyntheticPlugin\n')
class BadTLS(socketserver.BaseRequestHandler):
 def handle(self):requests.append({'server':'failed-tls','case':case});self.request.close()
class Good(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_HEAD(self):self.respond(False)
 def do_GET(self):self.respond(True)
 def respond(self,body):
  requests.append({'server':'later-repository','case':case,'path':self.path});n=self.path.rsplit('/',1)[-1]
  if n.endswith('.pom'):
   parts=self.path.strip('/').split('/');group='.'.join(parts[1:-3]);artifact=parts[-3];version=parts[-2];marker=artifact.endswith('.gradle.plugin');dependencies='<packaging>pom</packaging><dependencies><dependency><groupId>com.android.synthetic</groupId><artifactId>fixture-plugin</artifactId><version>1</version></dependency></dependencies>' if marker else '';data=('<project><modelVersion>4.0.0</modelVersion><groupId>'+group+'</groupId><artifactId>'+artifact+'</artifactId><version>'+version+'</version>'+dependencies+'</project>').encode();code=200
  elif n.endswith('.jar'):data=pluginJar.getvalue() if n.startswith('fixture-plugin-') else jar.getvalue();code=200
  else:data=b'';code=404
  self.send_response(code);self.send_header('Content-Length',str(len(data)));self.end_headers()
  if body:self.wfile.write(data)
bad=socketserver.ThreadingTCPServer(('127.0.0.1',0),BadTLS);good=http.server.ThreadingHTTPServer(('127.0.0.1',0),Good);ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.load_cert_chain(root/'cert.pem',root/'key.pem');good.socket=ctx.wrap_socket(good.socket,server_side=True)
for server in [bad,good]:threading.Thread(target=server.serve_forever,daemon=True).start()
badurl='https://127.0.0.1:'+str(bad.server_address[1]);goodurl='https://127.0.0.1:'+str(good.server_address[1]);testpolicy=policy
for url,alias in [('https://dl.google.com/dl/android/maven2',badurl),('https://repo.maven.apache.org/maven2',goodurl+'/central'),('https://plugins.gradle.org/m2',goodurl+'/portal'),('https://storage.googleapis.com/download.flutter.io',goodurl+'/flutter')]:
 needle="case '"+url+"':";assert testpolicy.count(needle)==1;testpolicy=testpolicy.replace(needle,"case '"+alias+"':\n        "+needle)
for needle,alias in [("case 'https://dl.google.com/dl/android/maven2':",goodurl+'/google'),("case 'https://repo.maven.apache.org/maven2':",badurl+'/central')]:testpolicy=testpolicy.replace(needle,"case '"+alias+"':\n        "+needle)
repo="maven { url='"+badurl+"' }; maven { url='"+goodurl+"/central' }"
resolve="configurations.create('probe'); dependencies.add('probe','com.android.synthetic:poison:1'); tasks.register('resolveProbe') { doLast { println 'SYNTHETIC_RESOLVED '+configurations.probe.files*.name } }\n"
results=[];case='setup'
def run(name,scope,protected,expected_success):
 global case
 case=name;d=root/name;d.mkdir();home=d/'gradle-home';home.mkdir();init=home/'init.d';init.mkdir()
 if protected:(init/'policy.gradle').write_text(testpolicy)
 settings="rootProject.name='synthetic-policy';\n";build=resolve;task='resolveProbe'
 if scope=='project':build='repositories { '+repo+' };\n'+build
 elif scope=='settings-repositories':settings+='dependencyResolutionManagement { repositories { '+repo+' } };\n'
 elif scope=='detached':build='repositories { '+repo+' }; tasks.register(\'resolveProbe\') { doLast { println configurations.detachedConfiguration(dependencies.create(\'com.android.synthetic:poison:1\')).files*.name } }\n'
 elif scope in ['settings-buildscript','project-buildscript']:
  header="buildscript { repositories { "+repo+" }; dependencies { classpath 'com.android.synthetic:poison:1' } };\n"
  if scope=='settings-buildscript':settings=header+settings
  else:build=header+"tasks.register('resolveProbe') { doLast { println 'SYNTHETIC_BUILDSCRIPT_OK' } }\n"
 elif scope=='included':
  settings+="includeBuild('included');\n";build="tasks.register('resolveProbe') { dependsOn gradle.includedBuild('included').task(':resolveProbe') }\n";inc=d/'included';inc.mkdir();(inc/'settings.gradle').write_text("rootProject.name='included'\n");(inc/'build.gradle').write_text('repositories { '+repo+' };\n'+resolve)
 elif scope=='late-url':
  build="def changed = repositories.maven { url='https://repo.maven.apache.org/maven2' }; changed.url='"+goodurl+"/unexpected';\n"+resolve
 elif scope=='unknown':build="repositories { maven { url='"+goodurl+"/unexpected' } };\n"+resolve
 elif scope=='central-success':build='repositories { '+repo+' };\n'+resolve.replace('com.android.synthetic:poison:1','org.example.synthetic:poison:1')
 elif scope=='late-added':build='afterEvaluate { repositories { '+repo+' } };\n'+resolve
 elif scope=='late-content-widening':build="def g = repositories.maven { url='"+goodurl+"/google' }; g.content { includeGroup('org.example.synthetic') }; repositories.maven { url='"+badurl+"/central' };\n"+resolve.replace('com.android.synthetic:poison:1','org.example.synthetic:poison:1')
 elif scope=='late-artifact-urls':build="def g = repositories.maven { url='https://repo.maven.apache.org/maven2' }; g.artifactUrls('"+goodurl+"/unexpected');\n"+resolve
 elif scope=='artifact-urls':build="repositories { maven { url='https://repo.maven.apache.org/maven2'; artifactUrls('"+goodurl+"/unexpected') } };\n"+resolve
 elif scope=='readd-url':build="def g = repositories.maven { url='https://repo.maven.apache.org/maven2' }; repositories.remove(g); g.url='https://dl.google.com/dl/android/maven2'; repositories.add(g);\n"+resolve
 elif scope=='insecure-flag':build="repositories { maven { url='https://repo.maven.apache.org/maven2'; allowInsecureProtocol=true } };\n"+resolve
 elif scope=='flat-directory':build="repositories { flatDir { dirs '.' } };\n"+resolve
 elif scope=='google-plugin-success':
  settings="pluginManagement { repositories { clear(); maven { url='"+goodurl+"/google' } } };\n"+settings;build="plugins { id 'com.android.synthetic' version '1' }; tasks.register('resolveProbe') { doLast { println 'GOOD_GOOGLE_PLUGIN_OK' } }\n"
 elif scope=='annotations-success':build='repositories { '+repo+' };\n'+resolve.replace('com.android.synthetic:poison:1','com.google.android:annotations:4.1.1.4')
 elif scope in ['annotations-fallback','annotations-widening']:
  build="repositories.maven { url='"+badurl+"/central' }; def g = repositories.maven { url='"+goodurl+"/google' };\n"+("g.content { includeVersion('com.google.android','annotations','4.1.1.4') };\n" if scope=='annotations-widening' else '')+resolve.replace('com.android.synthetic:poison:1','com.google.android:annotations:4.1.1.4')
 elif scope in ['annotations-other-version','annotations-other-module']:
  coordinate='com.google.android:annotations:4.1.1.5' if scope=='annotations-other-version' else 'com.google.android:other-module:4.1.1.4'
  build="repositories.maven { url='"+goodurl+"/central' }; repositories.maven { url='"+badurl+"' };\n"+resolve.replace('com.android.synthetic:poison:1',coordinate)
 elif scope in ['settings-plugin','project-plugin']:
  settings="pluginManagement { repositories { clear(); "+repo+" } };\n"+settings
  plugin="plugins { id 'com.android.synthetic' version '1' };\n"
  if scope=='settings-plugin':settings=settings.replace("rootProject.name='synthetic-policy';",plugin+"rootProject.name='synthetic-policy';")
  else:build=plugin+"tasks.register('resolveProbe') { doLast { println 'PROJECT_PLUGIN_OK' } }\n"
  if scope=='settings-plugin':build="tasks.register('resolveProbe') { doLast { println 'SETTINGS_PLUGIN_OK' } }\n"
 (d/'settings.gradle').write_text(settings);(d/'build.gradle').write_text(build);before=len(requests);env=dict(os.environ,JAVA_HOME=str(java),PATH=str(java/'bin')+':/usr/bin:/bin',GRADLE_USER_HOME=str(home));cmd=[gradle,'--no-daemon','--max-workers=2','-Dorg.gradle.jvmargs=-Xmx1g','-Djavax.net.ssl.trustStore='+str(root/'fixture-trust.jks'),'-Djavax.net.ssl.trustStorePassword=synthetic-fixture',task]
 result=subprocess.run(cmd,cwd=d,env=env,capture_output=True,text=True,timeout=60);log=result.stdout+result.stderr;(d/'build.log').write_text(log);traffic=requests[before:];later=[x for x in traffic if x['server']=='later-repository'];ok=(result.returncode==0)==expected_success
 if protected and not expected_success:ok=ok and not later
 if protected and not expected_success and scope not in ['late-url','unknown','late-artifact-urls','artifact-urls','readd-url','insecure-flag','flat-directory']:ok=ok and any(x in log for x in ['SSL','handshake','Could not resolve','not found'])
 if not protected:ok=ok and bool(later)
 row={'case':name,'scope':scope,'protected':protected,'exitCode':result.returncode,'expectedSuccess':expected_success,'laterRepositoryRequests':len(later),'failedTlsConnections':len(traffic)-len(later),'passed':ok,'logSha256':hashlib.sha256(log.encode()).hexdigest()};results.append(row);print(json.dumps(row),flush=True)
 if not ok:print(log[-5000:],flush=True);raise AssertionError(name)
try:
 run('protected-central-success','central-success',True,True)
 run('protected-google-plugin-success','google-plugin-success',True,True)
 for scope in ['settings-plugin','project-plugin']:
  run('baseline-'+scope,scope,False,True)
  run('protected-'+scope,scope,True,False)
 run('protected-late-added','late-added',True,False)
 for scope in ['project','settings-repositories','settings-buildscript','project-buildscript','detached','included','late-url','unknown','late-content-widening','late-artifact-urls','artifact-urls','readd-url','insecure-flag','flat-directory']:run('protected-'+scope,scope,True,False)
 run('protected-annotations-success','annotations-success',True,True)
 run('baseline-annotations-fallback','annotations-fallback',False,True)
 for scope in ['annotations-fallback','annotations-widening','annotations-other-version','annotations-other-module']:run('protected-'+scope,scope,True,False)
finally:
 for server in [bad,good]:server.shutdown();server.server_close()
 (root/'request-receipt.json').write_text(json.dumps(requests,indent=2)+'\n');(root/'results.json').write_text(json.dumps({'atUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'productionPolicySha256':hashlib.sha256(policy.encode()).hexdigest(),'testOnlyChange':'Exact loopback HTTPS aliases added to endpoint switch; no filter or lifecycle changes; dedicated fixture certificate truststore, no external TLS bypass','gradleVersion':'9.4.1','ownerCredentialsUsed':False,'results':results},indent=2)+'\n')
