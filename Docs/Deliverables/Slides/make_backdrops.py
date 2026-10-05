# Procedural backdrops for the PPTX: nothing is drawn by hand, everything comes from noise and gradients.
import numpy as np, os
from PIL import Image, ImageFilter
rng=np.random.default_rng(11)
out=os.path.join(os.path.dirname(os.path.abspath(__file__)),'backdrops')
def fbm1(n,octaves,seed,period_cells=4):
    r=np.random.default_rng(seed); x=np.linspace(0,1,n,endpoint=False); s=np.zeros(n); a=1;t=0;p=period_cells
    for o in range(octaves):
        g=r.random(p)*2-1; i=np.floor(x*p).astype(int); f=x*p-i
        u=f*f*f*(f*(f*6-15)+10); s+=a*((g[i%p]*(1-u))+(g[(i+1)%p]*u)); t+=a; a*=.5; p*=2
    return s/t
def hexc(h): return np.array([int(h[i:i+2],16) for i in (1,3,5)],float)
def vgrad(W,H,top,bottom):
    t=np.linspace(0,1,H)[:,None,None]; return hexc(top)*(1-t)+hexc(bottom)*t+np.zeros((H,W,3))
def glow(img,cx,cy,r,color,strength):
    H,W,_=img.shape; y,x=np.mgrid[0:H,0:W]; d=np.hypot((x-cx*W)/W,(y-cy*H)/H)/r
    g=np.exp(-d*d*2.2)[...,None]*strength; return img*(1-g)+hexc(color)*g
# ---- cover
W,H=2667,1500
img=vgrad(W,H,'#050A18','#14284A')
img=glow(img,0.78,0.78,0.55,'#0E7C86',0.55); img=glow(img,0.15,0.2,0.4,'#1D3A78',0.35)
sky=rng.random((H,W)); stars=(sky>0.9993)*(rng.random((H,W))*0.8+0.2)
stars[int(H*0.62):]=0; img+=stars[...,None]*np.array([200,220,255])
ridges=[(0.62,0.10,'#0F2A4A',3,1),(0.72,0.12,'#0B2038',5,2),(0.82,0.10,'#081829',7,3),(0.92,0.08,'#050F1B',11,4)]
x=np.arange(W)/W
for base,amp,col,cells,seed in ridges:
    prof=base+amp*(fbm1(W,6,seed,cells)*0.5)
    mask=(np.arange(H)[:,None]>prof[None,:]*H)
    fade=np.clip((np.arange(H)[:,None]-prof[None,:]*H)/180,0,1)[...,None]
    c=hexc(col); img=np.where(mask[...,None],img*(0.0)+c*(0.78+0.22*fade)+0*img,img)
Image.fromarray(np.clip(img,0,255).astype(np.uint8)).save(os.path.join(out,'cover.jpg'),quality=92)
# ---- content background (light, subtle)
W,H=2667,1500
img=vgrad(W,H,'#F7F9FC','#EEF3F8')
img=glow(img,0.95,0.05,0.5,'#BFE9E4',0.45); img=glow(img,0.02,0.98,0.45,'#D6E4F7',0.5)
yy,xx=np.mgrid[0:H,0:W]; dots=((xx%64<3)&(yy%64<3))[...,None]*np.array([200,210,225])*0.35
img=np.where(dots>0,img*0.93+dots*0.07*3,img)
Image.fromarray(np.clip(img,0,255).astype(np.uint8)).save(os.path.join(out,'content.jpg'),quality=92)
# ---- header strip
W,H=2667,190
img=vgrad(W,H,'#08111F','#0F2F47'); img=glow(img,0.92,0.5,0.5,'#0E8A8F',0.6)
prof=0.78+0.18*fbm1(W,5,21,6); mask=(np.arange(H)[:,None]>prof[None,:]*H)
img=np.where(mask[...,None],img*0.55+hexc('#03101C')*0.45,img)
Image.fromarray(np.clip(img,0,255).astype(np.uint8)).save(os.path.join(out,'header.jpg'),quality=92)
# ---- closing band
W,H=2667,250
img=vgrad(W,H,'#08111F','#0E2A44'); img=glow(img,0.85,0.4,0.5,'#0E8A8F',0.55)
prof=0.55+0.25*fbm1(W,6,31,5); mask=(np.arange(H)[:,None]>prof[None,:]*H)
img=np.where(mask[...,None],hexc('#050F1B')*0.9+img*0.1,img)
Image.fromarray(np.clip(img,0,255).astype(np.uint8)).save(os.path.join(out,'band.jpg'),quality=92)
print('ok')
