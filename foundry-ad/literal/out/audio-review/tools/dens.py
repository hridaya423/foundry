import sys,glob,numpy as np,librosa,subprocess,warnings
warnings.filterwarnings('ignore')
SR=22050
def dec(p):
    r=subprocess.run(['ffmpeg','-v','error','-i',p,'-f','f32le','-ac','1','-ar',str(SR),'-'],capture_output=True); return np.frombuffer(r.stdout,np.float32)
W=float(sys.argv[1]); files=sys.argv[2:]
rows=[]
for p in files:
    y=dec(p)
    if len(y)<W*SR: continue
    on=librosa.onset.onset_detect(y=y,sr=SR,units='time',backtrack=False,delta=0.06,wait=2,hop_length=128)
    hop=int(0.05*SR); rms=np.sqrt(np.convolve(y**2,np.ones(hop)/hop,'same'))
    best=None
    for t0 in np.arange(0,len(y)/SR-W+0.01,0.1):
        n=((on>=t0)&(on<t0+W)).sum()
        a,b=int(t0*SR),int((t0+W)*SR); lvl=20*np.log10(np.sqrt(np.mean(y[a:b]**2))+1e-9); pk=20*np.log10(np.abs(y[a:b]).max()+1e-9)
        edge=20*np.log10(np.sqrt(np.mean(y[a:a+int(.03*SR)]**2))+1e-9); edge2=20*np.log10(np.sqrt(np.mean(y[b-int(.05*SR):b]**2))+1e-9)
        sc=n
        if best is None or sc>best[0]: best=(sc,round(t0,1),round(lvl,1),round(pk,1),round(edge,1),round(edge2,1))
    rows.append((best[0]/W,p.split('/')[-1][:46],len(y)/SR,best))
rows.sort(reverse=True)
for r in rows[:14]: print(f"{r[1]:46} dur{r[2]:6.1f}  best {W}s window: start {r[3][1]}s, {r[3][0]} onsets ({r[0]:.1f}/s), rms {r[3][2]} pk {r[3][3]}, head {r[3][4]} tail {r[3][5]} dBFS")
