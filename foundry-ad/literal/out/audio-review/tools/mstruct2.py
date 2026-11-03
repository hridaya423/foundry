import sys,json,numpy as np
sys.path.insert(0,'.')
from tempo import *
cfg=json.loads(sys.argv[1])
for name,(bpm,off) in cfg.items():
    y=load(f'/Users/hridyaagrawal/Honey/anvil/foundry-ad/literal/audio/assets/music/{name}.mp3')
    c=curves(y,bpm,off); a=np.array([x[1:] for x in c],float)
    med=np.median(a,0)
    print('==',name,bpm,'bar %.3fs'%(240/bpm),'bars',len(c),'median all/low/hi %.0f/%.0f/%.0f'%tuple(med))
    prev=None; segs=[]
    # segment by state: kick present (low>med_low-6), hi level class
    for i,(t,al,lo,hi) in enumerate(c):
        kick = lo>med[1]-6
        hic = 'H' if hi>med[2]-4 else ('h' if hi>med[2]-12 else '_')
        lv = 'L' if al>med[0]+2.5 else ('l' if al<med[0]-3 else 'm')
        st=('K' if kick else '-')+hic+lv
        if st!=prev: segs.append([i,t,st]); prev=st
    print('  '+'  '.join(f'b{i}@{t:.1f}s:{s}' for i,t,s in segs))
