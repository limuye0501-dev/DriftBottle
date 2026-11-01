# Synthesized cork experiments only (variants A/B/C). NOT shipped: the app uses a real CC0 recording, see Resources/Sounds/LICENSES.md. Writes only local cork_*.wav.
import numpy as np, scipy.signal as ss, scipy.io.wavfile as wf, sys
SR=44100; rng=np.random.default_rng(7)
def bp(x,lo,hi,o=2): return ss.sosfilt(ss.butter(o,[lo,hi],'band',fs=SR,output='sos'),x)
def lp(x,f,o=2): return ss.sosfilt(ss.butter(o,f,'low',fs=SR,output='sos'),x)
def env(n,a,d): t=np.arange(n)/SR; return (1-np.exp(-t/a))*np.exp(-t/d)
def make(sq_amp,sq_dur,pop_f0,pop_f1,pop_dec,body,hiss,ring,rev,total=1.45):
    N=int(total*SR); y=np.zeros(N); t=np.arange(N)/SR
    # squeak: stick-slip bursts at rising rate, bandpassed, soft
    ns=int(sq_dur*SR); ts=np.arange(ns)/SR
    rate=35+70*(ts/sq_dur)**1.5; ph=np.cumsum(rate)/SR
    pulses=np.maximum(0,np.sin(2*np.pi*ph))**6
    fr=bp(rng.standard_normal(ns),700,2200)*pulses
    fr+=0.5*np.sin(2*np.pi*np.cumsum(600+250*ts/sq_dur)/SR)*pulses*0.3
    shape=np.sin(np.pi*np.minimum(1,ts/sq_dur))**0.7*(0.4+0.6*ts/sq_dur)
    y[:ns]+=sq_amp*lp(fr,3000)*shape
    p0=ns+int(0.03*SR); n=N-p0; tp=np.arange(n)/SR
    f=pop_f1+(pop_f0-pop_f1)*np.exp(-tp/0.018)
    pop=np.sin(2*np.pi*np.cumsum(f)/SR)*env(n,0.0015,pop_dec)
    pop+=body*np.sin(2*np.pi*np.cumsum(0.55*f)/SR)*env(n,0.002,pop_dec*1.3)
    pop+=0.5*lp(rng.standard_normal(n),900)*env(n,0.001,0.012)  # soft air burst
    h=hiss*bp(rng.standard_normal(n),1500,7000)*env(n,0.01,0.12)
    r=sum(a*np.sin(2*np.pi*fq*tp+k)*env(n,0.004,d) for fq,a,d,k in [(1180,1,0.35,0),(2870,.5,0.25,1),(4320,.25,0.18,2),(640,.6,0.4,3)])
    y[p0:]+=pop+h+ring*r*0.15
    # small glass-room reverb
    ir_n=int(0.5*SR); ir=rng.standard_normal(ir_n)*np.exp(-np.arange(ir_n)/SR/rev); ir=lp(ir,4000); ir/=np.sqrt((ir**2).sum())
    y=y+0.35*ss.fftconvolve(y,ir)[:N]
    fi=int(0.01*SR); fo=int(0.15*SR); y[:fi]*=np.linspace(0,1,fi); y[-fo:]*=np.linspace(1,0,fo)**2
    y=lp(y,9000); return y/np.abs(y).max()*0.89
V={'A':make(0.18,0.55,480,240,0.07,0.6,0.25,1.0,0.12),   # balanced
   'B':make(0.10,0.45,380,190,0.10,0.9,0.15,0.6,0.15,1.35),  # deeper, rounder, minimal squeak
   'C':make(0.15,0.60,520,280,0.06,0.5,0.40,1.8,0.18,1.6)}  # airier, more glass ring
for k,v in V.items(): wf.write(f'cork_{k}.wav',SR,(v*32767).astype(np.int16))
