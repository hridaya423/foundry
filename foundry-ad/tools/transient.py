"""Print the sharpest broadband transients in a window: usage transient.py <audio> <start> <end> [n]"""
import subprocess, sys
import numpy as np
from scipy import signal
SR = 44100
p, a, b = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
n = int(sys.argv[4]) if len(sys.argv) > 4 else 3
x = np.frombuffer(subprocess.run(["ffmpeg","-v","error","-i",p,"-ac","1","-ar",str(SR),"-f","f32le","-"],capture_output=True,check=True).stdout, dtype=np.float32)
env = signal.sosfiltfilt(signal.butter(2, 60, fs=SR, output="sos"), np.abs(x))
d = np.diff(env, prepend=0)
i0, i1 = int(a*SR), int(b*SR)
pk, _ = signal.find_peaks(d[i0:i1], distance=int(0.1*SR))
pk = pk[np.argsort(d[i0:i1][pk])[::-1][:n]]
for k in sorted(pk):
    j = i0 + k
    pre = 20*np.log10(env[max(0,j-int(0.15*SR)):j].mean()+1e-9); post = 20*np.log10(env[j:j+int(0.15*SR)].mean()+1e-9)
    print(f"  {p} t={j/SR:.4f}s rise={d[j]*1e4:.2f} pre={pre:.1f}dB post={post:.1f}dB")
