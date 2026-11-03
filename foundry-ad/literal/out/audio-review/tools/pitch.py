import sys,numpy as np,subprocess,warnings
warnings.filterwarnings('ignore')
SR=48000
N=['C','C#','D','D#','E','F','F#','G','G#','A','A#','B']
def dec(p):
    r=subprocess.run(['ffmpeg','-v','error','-i',p,'-f','f32le','-ac','1','-ar',str(SR),'-'],capture_output=True); return np.frombuffer(r.stdout,np.float32)
def name(f):
    m=69+12*np.log2(f/440); i=int(round(m)); return f"{N[i%12]}{i//12-1} {f:.1f}Hz ({(m-i)*100:+.0f}c)"
for p in sys.argv[1:]:
    y=dec(p); 
    pk=np.abs(y).argmax(); a=max(0,pk-int(0.01*SR)); seg=y[a+int(0.03*SR):a+int(0.03*SR)+int(0.6*SR)]
    if len(seg)<4096: seg=y[a:a+int(0.6*SR)]
    n=1<<int(np.ceil(np.log2(len(seg)*4))); S=np.abs(np.fft.rfft(seg*np.hanning(len(seg)),n)); f=np.fft.rfftfreq(n,1/SR)
    # strongest peaks between 100 and 3000 Hz
    ok=(f>100)&(f<3000); idx=np.argsort(-S*ok)[:60]
    peaks=[]
    for i in sorted(idx,key=lambda i:-S[i]):
        if all(abs(f[i]-q)>30 for q,_ in peaks): peaks.append((f[i],S[i]))
        if len(peaks)==4: break
    # decay: time after peak until envelope < -60 dB re peak (50ms rms)
    env=np.sqrt(np.convolve(y**2,np.ones(2400)/2400,'same')); pe=env[pk:]; 
    k=np.where(pe<env.max()*10**(-60/20))[0]; d60=(k[0]/SR) if len(k) else None
    k2=np.where(pe<env.max()*10**(-30/20))[0]; d30=(k2[0]/SR) if len(k2) else None
    print(p.split('/')[-1][:46], '| peaks:',', '.join(name(q) for q,_ in peaks[:3]),'| dur %.2f d30 %s d60 %s'%(len(y)/SR, None if d30 is None else round(d30,2), None if d60 is None else round(d60,2)))
