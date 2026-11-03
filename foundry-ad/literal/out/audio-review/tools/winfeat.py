import sys,json,numpy as np,subprocess
SR=48000
def dec(p):
    r=subprocess.run(['ffmpeg','-v','error','-i',p,'-f','f32le','-ac','1','-ar',str(SR),'-'],capture_output=True); return np.frombuffer(r.stdout,np.float32)
p,j=sys.argv[1],sys.argv[2]
y=dec(p); d=json.load(open(j)); segs=d['segments'] if 'segments' in d else d['results']
rows=[]
for s in segs:
    if s['duration']>0.5 or s.get('cut'): continue
    a,b=int(s['start']*SR),int(s['end']*SR); w=y[a:b]
    spec=np.abs(np.fft.rfft(w*np.hanning(len(w)))); f=np.fft.rfftfreq(len(w),1/SR)
    cen=(spec*f).sum()/spec.sum(); low=spec[f<400].sum()/spec.sum()
    env=np.abs(w); pk=env.max(); 
    # time from peak to -30 dB
    ip=env.argmax(); k=np.where(np.convolve(env,np.ones(96)/96,'same')[ip:]<pk*0.03)[0]; dec30=(k[0]/SR) if len(k) else (len(w)-ip)/SR
    rows.append((s['start'],s['end'],s['z'],s['peak_dbfs'],s['head_db'],s['tail_db'],round(cen),round(low,2),round(dec30,3)))
rows.sort()
for r in rows: print('%.3f-%.3f z%+.1f pk%.1f head%.0f tail%.0f cen%d low%.2f dec%.3f'%r)
print(len(rows))
