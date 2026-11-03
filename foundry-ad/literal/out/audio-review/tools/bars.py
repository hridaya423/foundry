import sys,json,numpy as np
sys.path.insert(0,'.')
from tempo import *
name,bpm,off,a,b=sys.argv[1],float(sys.argv[2]),float(sys.argv[3]),int(sys.argv[4]),int(sys.argv[5])
y=load(f'/Users/hridyaagrawal/Honey/anvil/foundry-ad/literal/audio/assets/music/{name}.mp3')
c=curves(y,bpm,off)
print(name,' '.join(f'[{i}]{t:.1f}s {al:.0f}/{lo:.0f}/{hi:.0f}' for i,(t,al,lo,hi) in enumerate(c) if a<=i<=b))
