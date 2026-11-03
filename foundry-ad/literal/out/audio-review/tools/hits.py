import sys,numpy as np,subprocess,scipy.signal as ss
SR=48000
def dec(p):
    r=subprocess.run(['ffmpeg','-v','error','-i',p,'-f','f32le','-ac','1','-ar',str(SR),'-'],capture_output=True); return np.frombuffer(r.stdout,np.float32)
def db(x): return 20*np.log10(max(float(x),1e-9))
mode=sys.argv[1]
for p in sys.argv[2:]:
    y=dec(p); a=np.abs(y); env=np.sqrt(np.convolve(y**2,np.ones(int(.01*SR))/int(.01*SR),'same'))
    ip=int(env.argmax()); pk=env[ip]
    if mode=='swish':
        thr=pk*0.1  # -20 dB
        idx=np.where(env>thr)[0]; on=idx[0]/SR; off=idx[-1]/SR
        # smoothed apex
        sm=np.convolve(env,np.ones(int(.05*SR))/int(.05*SR),'same'); ap=sm.argmax()/SR
        print(f"{p.split('/')[-1][:42]:42} dur {len(y)/SR:5.2f} -20dB span {on:.2f}-{off:.2f} apex {ap:.2f} ({ap-on:.2f} after onset, {off-ap:.2f} before end) peak {db(a.max()):.1f} dBFS cen~")
    else:
        # strongest onset: first sample within 6 dB of max abs in the first part
        t0=max(0,ip-int(.02*SR)); seg=y[t0:t0+int(.25*SR)]
        bands=[(25,90),(90,250),(250,2000),(2000,8000),(8000,16000)]
        e=[]
        for lo,hi in bands:
            sos=ss.butter(4,[lo,min(hi,SR/2-100)],'band',fs=SR,output='sos'); e.append(db(np.sqrt(np.mean(ss.sosfilt(sos,seg)**2))))
        m=max(e); rel=[round(x-m) for x in e]
        d=env[ip:]; 
        def tt(l):
            k=np.where(d<pk*10**(-l/20))[0]; return round(k[0]/SR,2) if len(k) else None
        print(f"{p.split('/')[-1][:42]:42} dur {len(y)/SR:5.2f} hit@{ip/SR:5.2f}s pk {db(a.max()):5.1f} first250ms bands rel(25-90/90-250/250-2k/2-8k/8-16k) {rel} abs-max {m:.0f}; t-20dB {tt(20)} t-40 {tt(40)}")
