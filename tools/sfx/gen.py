import numpy as np, scipy.signal as sg, scipy.io.wavfile as wf
SR=44100; rng=np.random.default_rng(1)
def bp(x,lo,hi,o=2): return sg.sosfilt(sg.butter(o,[lo,hi],'band',fs=SR,output='sos'),x)
def lp(x,f,o=2): return sg.sosfilt(sg.butter(o,f,'low',fs=SR,output='sos'),x)
def hp(x,f,o=2): return sg.sosfilt(sg.butter(o,f,'high',fs=SR,output='sos'),x)
def t(d): return np.arange(int(d*SR))/SR
def env(n,a,d,curve=3):  # attack secs, exp decay
    tt=np.arange(n)/SR; return np.minimum(1,tt/max(a,1e-4))*np.exp(-tt*curve/d)
def fade(x,fi=0.005,fo=0.03):
    x=x.copy(); a=int(fi*SR); b=int(fo*SR)
    if a: x[:a]*=np.linspace(0,1,a)
    if b: x[-b:]*=np.linspace(1,0,b)
    return x
def norm(x,target=-16,peak=-1):
    w=int(0.4*SR); 
    if len(x)<w: w=len(x)
    r=max(np.sqrt(np.mean(x[i:i+w]**2)) for i in range(0,len(x)-w+1,max(1,w//4)))
    g=10**(target/20)/r; y=x*g; pk=np.max(np.abs(y)); lim=10**(peak/20)
    if pk>lim: y=y*lim/pk
    return y
def bell(f,d,partials=((1,1),(2.0,.5),(3.01,.25),(4.2,.12)),decay=4):
    tt=t(d); return sum(a*np.sin(2*np.pi*f*m*tt)*np.exp(-tt*decay*(1+m*.4)) for m,a in partials)*np.minimum(1,tt/0.003)
out={}
# 1 waves loop 30s, seamless: periodic modulators + circular filtering via crossfade
L=30; N=L*SR; ex=3*SR
n=rng.standard_normal(N+ex); brown=lp(n,500,2); brown/=np.abs(brown).max()
hiss=hp(bp(rng.standard_normal(N+ex),1500,7000),1500); hiss/=np.abs(hiss).max()
tt=np.arange(N+ex)/SR
sw=np.zeros_like(tt)
for k,(per,ph,a) in enumerate([(7.5,0,1),(10,1.3,.7),(6,2.1,.5),(15,.4,.6)]):  # 30 divisible by all → periodic
    sw+=a*(0.5+0.5*np.sin(2*np.pi*tt/per+ph))**3
sw/=sw.max()
crest=np.clip(np.gradient(sw)*SR*2,0,None); crest=lp(crest,3,1); crest/=crest.max()+1e-9
x=brown*(0.25+0.75*sw)+0.35*hiss*(0.1+crest*0.9+0.2*sw)
xf=int(2*SR); y=x[:N].copy(); tail=x[N:N+xf]   # crossfade continuation into head
w=np.linspace(0,1,xf); y[:xf]=y[:xf]*w+tail*(1-w)
out['sfx_waves_loop']=(norm(y,-20),True)
# 2 throw whoosh
d=0.6;n=rng.standard_normal(int(d*SR)); tt=t(d)
fc=600+2400*np.sin(np.pi*tt/d)**2
y=np.zeros_like(n); 
for i in range(0,len(n),512):
    s=slice(i,i+512); y[s]=bp(n[max(0,i-2048):i+512],max(100,fc[i]*.6),fc[i]*1.4)[-len(n[s]):]
y*=np.sin(np.pi*np.clip(tt/d,0,1))**2
out['sfx_throw_whoosh']=(fade(norm(y)),False)
# 3 splash
d=0.9;n=rng.standard_normal(int(d*SR));tt=t(d)
y=lp(n,3500)*env(len(n),0.004,0.35,4)+0.6*hp(n,3000)*env(len(n),0.002,0.15,5)
for k in range(10):
    st=rng.uniform(0.05,0.5); f0=rng.uniform(500,1400); dd=0.05
    i=int(st*SR); m=int(dd*SR); ti=np.arange(m)/SR
    y[i:i+m]+=0.35*np.sin(2*np.pi*(f0*ti+f0*3*ti**2/dd))*np.exp(-ti*60)
y+=0.8*np.sin(2*np.pi*90*tt)*env(len(n),0.002,0.08,5)
out['sfx_splash']=(fade(norm(y)),False)
# 4 net dip (softer, lower)
d=0.55;n=rng.standard_normal(int(d*SR))
y=lp(n,1800)*env(len(n),0.02,0.25,4)
for k in range(5):
    i=int(rng.uniform(0.03,0.3)*SR);m=int(0.04*SR);ti=np.arange(m)/SR;f0=rng.uniform(400,800)
    y[i:i+m]+=0.25*np.sin(2*np.pi*(f0*ti+f0*4*ti**2/0.04))*np.exp(-ti*70)
out['sfx_net_dip']=(fade(norm(y,-18)),False)
# 5 pick up: lift swoosh + drips
d=0.9;n=rng.standard_normal(int(d*SR));tt=t(d)
y=0.6*bp(n,300,1500)*np.exp(-((tt-0.12)/0.08)**2)
for k in range(7):
    i=int((0.2+k*0.09+rng.uniform(-.02,.02))*SR);m=int(0.06*SR);ti=np.arange(m)/SR;f0=rng.uniform(700,1300)
    y[i:i+m]+=(0.5-k*0.05)*np.sin(2*np.pi*(f0*ti+f0*5*ti**2/0.06))*np.exp(-ti*55)
out['sfx_pick_up']=(fade(norm(y)),False)
# 6 cork pop
d=0.3;tt=t(d);n=rng.standard_normal(len(tt))
f=np.cumsum(700*np.exp(-tt*25)+250)/SR
y=np.sin(2*np.pi*f)*env(len(tt),0.001,0.06,4)+0.5*hp(n,2000)*env(len(tt),0.0005,0.01,5)
out['sfx_cork_pop']=(fade(norm(y),0.0005,0.02),False)
# 7 paper unfold: crinkle grains
d=0.8;y=np.zeros(int(d*SR));tt=t(d)
dens=np.sin(np.pi*tt/d)**1.5
for i in range(len(y)):
    if rng.random()<dens[i]*0.004:
        m=int(rng.uniform(0.002,0.012)*SR); g=rng.standard_normal(m)*np.exp(-np.arange(m)/(m/3))*rng.uniform(.3,1)
        y[i:i+m]+=g[:len(y)-i]
y=bp(y,1200,9000)+0.15*lp(rng.standard_normal(len(y)),600)*dens
out['sfx_paper_unfold']=(fade(norm(y,-18)),False)
# 8 send: soft rising two notes
a=bell(880,0.35,decay=9); b=bell(1318.5,0.45,decay=8)
y=np.zeros(int(0.55*SR)); y[:len(a)]+=a; i=int(0.08*SR); y[i:i+len(b)]+=b
out['sfx_send']=(fade(norm(y,-18)),False)
# 9 receive: falling marimba-ish
mar=((1,1),(3.9,.3),(9.2,.08))
a=bell(1046.5,0.4,mar,10); b=bell(784,0.5,mar,8)
y=np.zeros(int(0.65*SR)); y[:len(a)]+=a; i=int(0.11*SR); y[i:i+len(b)]+=b
out['sfx_receive']=(fade(norm(y,-18)),False)
# 10 lighthouse chime: warm bell chord
y=np.zeros(int(2.4*SR))
for k,(f,dl) in enumerate([(523.25,0),(659.25,.12),(783.99,.24),(1046.5,.36)]):
    b=bell(f,2.0,((1,1),(2.76,.3),(5.4,.1),(0.5,.2)),2.2); i=int(dl*SR); y[i:i+len(b)]+=b*(1-k*.12)
out['sfx_lighthouse_chime']=(fade(norm(y,-17),0.002,0.3),False)
for k,(x,_) in out.items(): wf.write(f'{k}.wav',SR,(np.clip(x,-1,1)*32767).astype(np.int16))
print(list(out))
