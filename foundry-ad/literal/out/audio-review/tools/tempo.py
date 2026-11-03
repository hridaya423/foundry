import sys, json, numpy as np, subprocess, librosa, scipy.signal as ss
SR=22050
def load(p):
    y,_=librosa.load(p,sr=SR,mono=True); return y
def kick_env(y):
    sos=ss.butter(4,[30,140],btype='band',fs=SR,output='sos'); k=ss.sosfilt(sos,y)
    hop=128
    e=np.sqrt(librosa.util.frame(k**2,frame_length=512,hop_length=hop).mean(0))
    d=np.maximum(0,np.diff(e,prepend=e[0])); return d,hop
def best_bpm(d,hop,lo=110,hi=135):
    fr=SR/hop; n=len(d); t=np.arange(n)
    res=[]
    for b in np.arange(lo,hi,0.05):
        per=60/b*fr
        # phase search
        best=0;bp=0
        for ph in np.linspace(0,per,24,endpoint=False):
            idx=(ph+np.arange(0,int((n-ph)/per))*per).astype(int)
            s=d[idx].sum()/len(idx)
            if s>best: best=s;bp=ph
        res.append((best,b,bp/fr))
    res.sort(reverse=True); return res[:3]
def curves(y,bpm,off):
    bar=4*60/bpm
    nb=int((len(y)/SR-off)/bar)
    sos=ss.butter(4,150,btype='low',fs=SR,output='sos'); lo=ss.sosfilt(sos,y)
    sos2=ss.butter(4,1500,btype='high',fs=SR,output='sos'); hi=ss.sosfilt(sos2,y)
    out=[]
    for i in range(nb):
        a=int((off+i*bar)*SR); b=int((off+(i+1)*bar)*SR)
        r=lambda x:20*np.log10(np.sqrt(np.mean(x[a:b]**2))+1e-9)
        out.append((round(off+i*bar,2),round(r(y),1),round(r(lo),1),round(r(hi),1)))
    return out
if __name__=='__main__':
    for p in sys.argv[1:]:
        y=load(p); d,hop=kick_env(y)
        t=best_bpm(d,hop)
        print(p.split('/')[-1],'dur',round(len(y)/SR,1),[(round(b,2),round(o,3),round(s,3)) for s,b,o in t])
