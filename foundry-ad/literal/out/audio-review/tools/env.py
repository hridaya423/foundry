import sys,numpy as np,subprocess
SR=22050
def dec(p):
    r=subprocess.run(['ffmpeg','-v','error','-i',p,'-f','f32le','-ac','1','-ar',str(SR),'-'],capture_output=True); return np.frombuffer(r.stdout,np.float32)
step=float(sys.argv[1])
for p in sys.argv[2:]:
    y=dec(p); n=int(step*SR); k=len(y)//n
    e=np.array([np.sqrt(np.mean(y[i*n:(i+1)*n]**2)) for i in range(k)]); pk=e.max()
    db=20*np.log10(e/pk+1e-9); ip=int(e.argmax())
    pkabs=20*np.log10(np.abs(y).max()+1e-9)
    print(p.split('/')[-1][:44],'dur %.1f'%(len(y)/SR),'peak@%.1fs pkdBFS %.1f'%((ip+0.5)*step,pkabs))
    print('   ',' '.join('%d'%max(-99,round(x)) for x in db[:60]))
