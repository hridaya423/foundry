import sys,numpy as np,librosa,scipy.signal as ss,warnings
warnings.filterwarnings('ignore')
N=['C','C#','D','D#','E','F','F#','G','G#','A','A#','B']
for name in sys.argv[1:]:
    y,sr=librosa.load(f'/Users/hridyaagrawal/Honey/anvil/foundry-ad/literal/audio/assets/music/{name}.mp3',sr=22050,mono=True)
    # bass band: low-pass 400 then CQT from C1
    sos=ss.butter(4,400,btype='low',fs=sr,output='sos'); b=ss.sosfilt(sos,y)
    ch=librosa.feature.chroma_cqt(y=b,sr=sr,fmin=librosa.note_to_hz('C1'),n_octaves=4,hop_length=2048)
    full=librosa.feature.chroma_cqt(y=y,sr=sr,hop_length=2048)
    for lab,c in (('bass',ch),('full',full)):
        m=c.mean(1); o=np.argsort(-m)[:4]
        print(name,lab,[(N[i],round(float(m[i]/m.max()),2)) for i in o])
