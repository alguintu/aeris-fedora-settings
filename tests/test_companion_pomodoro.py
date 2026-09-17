"""End-to-end connected phone contract against isolated real Tomat and Rust API.
Build the Rust binaries first; set AERIS_TEST_TOMAT to the installed fork.
No requests use the user's live socket, state, or companion listener.
"""
import json, os, pathlib, shutil, socket, subprocess, tempfile, time, unittest
import urllib.request, urllib.error
ROOT=pathlib.Path(__file__).resolve().parents[1]
class CompanionPomodoro(unittest.TestCase):
 def test_shared_timer_and_durable_explicit_sets(self):
  tomat=os.environ.get('AERIS_TEST_TOMAT')
  if not tomat:self.skipTest('Set AERIS_TEST_TOMAT for isolated real-daemon test')
  with tempfile.TemporaryDirectory(prefix='aeris-pomo-test-') as tmp:
   home=pathlib.Path(tmp);notes=home/'notes';notes.mkdir();state=home/'state';runtime=home/'runtime';runtime.mkdir(mode=0o700)
   shutil.copy(ROOT/'tomat/workout-templates/Upper body.md',notes/'Upper.md')
   token=home/'token';token.write_text('a'*64);token.chmod(0o600)
   with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
   env=dict(os.environ,TOMAT_RUNTIME_DIR=str(runtime),TOMAT_TESTING='1',TOMAT_CONFIG=str(ROOT/'tests/fixtures/tomat-silent.toml'),AERIS_TOMAT_TEMPLATE_DIR=str(notes),AERIS_TOMAT_STATE_DIR=str(state),AERIS_COMPANION_TOKEN_FILE=str(token),AERIS_COMPANION_PORT=str(port),AERIS_ALLOW_POWEROFF='0')
   processes=[]
   def spawn(args):
    p=subprocess.Popen(args,env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);processes.append(p);return p
   def call(path='/v1/status',body=None,auth=True,**headers):
    data=None if body is None else json.dumps(body).encode()
    h={'Authorization':'Bearer '+'a'*64} if auth else {}
    if data is not None:h['Content-Type']='application/json'
    h.update(headers)
    try:r=urllib.request.urlopen(urllib.request.Request(f'http://127.0.0.1:{port}'+path,data=data,headers=h),timeout=5)
    except urllib.error.HTTPError as e:r=e
    return r.status,json.load(r)
   def status():
    code,body=call();self.assertEqual(code,200)
    return body.get('services',{}).get('tomat',{}).get('payload',{})
   def wait_status(predicate):
    deadline=time.monotonic()+6
    while time.monotonic()<deadline:
     try:
      data=status()
      if data.get('ok') and predicate(data):return data
     except (OSError,AssertionError):pass
     time.sleep(.05)
    self.fail('Isolated timer status did not become ready')
   def cmd(action,timer,id=None):
    code,body=call('/v1/tomat',{'action':action,'revision':timer['revision'],**({'id':id} if id else {})})
    self.assertEqual(code,200,body);return body['timer']
   try:
    spawn([tomat,'daemon','run'])
    api=spawn([str(ROOT/'quickshell/aeris-backend/target/debug/aeris-companion')])
    timer=wait_status(lambda t:t['phase']=='Idle');self.assertEqual(timer['workout']['total'],6)
    self.assertEqual(call('/v1/tomat',{'action':'reset','revision':timer['revision']},auth=False)[0],401)
    self.assertEqual(call('/v1/tomat',{'action':'reset','revision':timer['revision']},Origin='https://example.org')[0],403)
    self.assertEqual(call('/v1/tomat',{'action':'reset','revision':timer['revision'],'exec':'bad'})[0],409)
    timer=cmd('start',timer);self.assertEqual(timer['activeId'],'strength-upper')
    old=timer;timer=cmd('pause',timer)
    self.assertEqual(call('/v1/tomat',{'action':'skip','revision':old['revision']})[0],409)
    timer=cmd('resume',timer);timer=cmd('skip',timer);self.assertEqual(timer['phase'],'Break')
    self.assertEqual(timer['workout']['completed'],0,'A phase change completed sets')
    day=timer['workout']
    record={'request_id':'fixture-write-1','day_id':day['id'],'expected_revision':0,'block_id':'floor-press','set':1,'result':{'status':'done','reps':10,'right_reps':None,'load_kg':6,'rir':3}}
    code,saved=call('/v1/workout/set',record);self.assertEqual(code,200,saved)
    code,retry=call('/v1/workout/set',record);self.assertEqual(code,200);self.assertEqual(saved,retry)
    code,conflict=call('/v1/workout/set',dict(record,request_id='stale-write',set=2));self.assertEqual(code,409)
    shared=json.loads(subprocess.check_output([str(ROOT/'quickshell/aeris-backend/target/debug/aeris-dashboard-backend'),'tomat','status'],env=env))
    self.assertEqual(shared['workout']['completed'],1,'Desktop adapter does not see phone log')
    timer=cmd('reset',timer);self.assertEqual(timer['workout']['completed'],1)
    timer=cmd('start',timer);self.assertEqual(timer['workout']['completed'],1)
    api.terminate();api.wait(timeout=5);spawn([str(ROOT/'quickshell/aeris-backend/target/debug/aeris-companion')])
    timer=wait_status(lambda t:t['workout']['completed']==1)
    self.assertEqual(timer['workout']['logs']['floor-press:1']['reps'],10)
    # Starting a new run never duplicates or clears the day's completed set.
    files=list((state/'workouts').glob('*.json'));self.assertEqual(len(files),1)
   finally:
    for p in reversed(processes):
     if p.poll() is None:p.terminate()
     try:p.wait(timeout=5)
     except subprocess.TimeoutExpired:p.kill();p.wait()
if __name__=='__main__':unittest.main()
