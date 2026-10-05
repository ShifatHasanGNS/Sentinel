# Renders every slide equation as a transparent PNG in the deck's ink colour, in one font and one size,
# so equations look identical across slides. Natural size is stored in sizes.txt (inches at 14 pt).
import subprocess, os, tempfile
from PIL import Image, ImageChops
import numpy as np
here=os.path.dirname(os.path.abspath(__file__)); out=os.path.join(here,'equation_images')
INK=(0x1E,0x29,0x3B); DPI=600
EQ={
'fractal':r'F(\mathbf{x})=\dfrac{\displaystyle\sum\limits_{i=0}^{n-1}2^{-i}\,\nu\!\left(2^{i}\mathbf{x}\right)}{\displaystyle\sum\limits_{i=0}^{n-1}2^{-i}}',
'push':r"\mathbf{p}'=\mathbf{p}+A\,\nu(f\mathbf{p})\,\hat n,\qquad \lVert\mathbf{p}'-\mathbf{p}\rVert\le A,\quad \nu\in[-1,1]",
'mpart':r'M_{\mathrm{part}}=T(\mathbf t)\,R_z(\gamma)\,R_y(\beta)\,R_x(\alpha)\,S(\mathbf s)',
'nmat':r"\hat n'=\dfrac{(L^{-1})^{\top}\hat n}{\left\lVert (L^{-1})^{\top}\hat n\right\rVert},\qquad L=\text{upper-left }3\times3\text{ of }M",
'mgun':r'M_{\mathrm{gun}}=M_{\mathrm{hull}}\;T(\mathbf c_t)\,R_y(\theta_t)\;T(\mathbf c_g)\,R_x(-\theta_g)',
'clip':r'\mathbf p_{\mathrm{clip}}=P\,V\,M_{\mathrm{world}}\,M_{\mathrm{part}}\,\mathbf p',
'ry':r'R_y(\theta)=\begin{pmatrix}\cos\theta&0&\sin\theta\\0&1&0\\-\sin\theta&0&\cos\theta\end{pmatrix}',
'sum':r'L_o=\sum\limits_{j=1}^{N_L} f(\mathbf l_j,\mathbf v)\,L_j\,\mathrm{att}_j\,\mathrm{sh}_j\,\max\!\left(0,\mathbf n\cdot\mathbf l_j\right)\;+\;\mathrm{ambient}\cdot\mathrm{AO}\;+\;\mathbf e',
'lambert':r'f=\dfrac{\mathbf c_d}{\pi}',
'phong':r'f=\dfrac{\mathbf c_d\,(1-F_0)}{\pi}+F_0\,\dfrac{m+2}{2\pi}\,\left(\mathbf r\cdot\mathbf v\right)^{m}',
'blinn':r'f=\dfrac{\mathbf c_d\,(1-F_0)}{\pi}+F_0\,\dfrac{m+8}{8\pi}\,\left(\mathbf n\cdot\mathbf h\right)^{m}',
'oren':r'f=\dfrac{\mathbf c_d}{\pi}\left(A+B\,\max(0,\cos\Delta\varphi)\,\sin\alpha\,\tan\beta\right)',
'ct2':r'f=\dfrac{(1-F_l)(1-F_v)\,\mathbf c_d}{\pi}+D\,V\,F',
'sss':r'\left\langle\mathbf n\cdot\mathbf l\right\rangle_w=\mathrm{clamp}\!\left(\dfrac{\mathbf n\cdot\mathbf l+w}{1+w},\,0,\,1\right),\quad w=0.5',
'defs':r'\begin{aligned}m&=\max\!\left(\dfrac{2}{\rho^{2}+10^{-4}}-2,\;1\right),&\mathbf r&=2(\mathbf n\cdot\mathbf l)\,\mathbf n-\mathbf l,&\mathbf h&=\dfrac{\mathbf l+\mathbf v}{\lVert\mathbf l+\mathbf v\rVert}\\[4pt]A&=1-\dfrac{0.5\,\sigma^{2}}{\sigma^{2}+0.33},&B&=\dfrac{0.45\,\sigma^{2}}{\sigma^{2}+0.09},&\sigma&=\rho\end{aligned}',
'ctdefs':r'\begin{aligned}D&=\dfrac{\alpha^{2}}{\pi\left((\mathbf n\cdot\mathbf h)^{2}(\alpha^{2}-1)+1\right)^{2}},&F&=F_0+(1-F_0)\left(1-\mathbf v\cdot\mathbf h\right)^{5},&\alpha&=\rho^{2}\end{aligned}',
'att':r'\mathrm{att}(d)=\begin{cases}\dfrac{\left(1-(d/R)^{4}\right)^{2}}{d^{2}+1}, & 0\le d\le R\\[8pt] 0, & d>R\end{cases}',
'spot':r'c(\theta)=\begin{cases}1,&\theta\le\theta_i\\[2pt]\left(\dfrac{\cos\theta-\cos\theta_o}{\cos\theta_i-\cos\theta_o}\right)^{2},&\theta_i<\theta<\theta_o\\[8pt]0,&\theta\ge\theta_o\end{cases}',
'csm':r'z_i=\lambda\,n\left(\dfrac{r}{n}\right)^{i/N}+(1-\lambda)\left(n+(r-n)\dfrac{i}{N}\right),\qquad i=1,\dots,N',
'fog':r'C=T\,C_{\mathrm{surface}}+(1-T)\,C_{\mathrm{haze}},\qquad T=e^{-k\,d}',
'aces':r'C_{\mathrm{out}}=\dfrac{x\,(2.51\,x+0.03)}{x\,(2.43\,x+0.59)+0.14},\qquad x=\text{exposure}\times\text{radiance}',
'ct':r'f=\dfrac{(1-F_l)(1-F_v)\mathbf c_d}{\pi}+D\,V\,F',
}
sizes=[]
for k,v in EQ.items():
    d=tempfile.mkdtemp()
    open(f'{d}/e.tex','w').write(r'\documentclass[14pt,border=2pt]{standalone}\usepackage[T1]{fontenc}\usepackage{libertine}\usepackage[libertine]{newtxmath}\usepackage{amsmath}\begin{document}$\displaystyle '+v+r'$\end{document}')
    subprocess.run(['pdflatex','-interaction=nonstopmode','-output-directory',d,f'{d}/e.tex'],capture_output=True)
    subprocess.run(['pdftoppm','-r',str(DPI),'-gray','-png','-singlefile',f'{d}/e.pdf',f'{d}/e'])
    g=np.array(Image.open(f'{d}/e.png').convert('L')).astype(float)
    alpha=(255-g)/255.0
    ys,xs=np.where(alpha>0.02); pad=4
    alpha=alpha[max(ys.min()-pad,0):ys.max()+pad,max(xs.min()-pad,0):xs.max()+pad]
    rgba=np.zeros(alpha.shape+(4,),np.uint8); rgba[...,0],rgba[...,1],rgba[...,2]=INK; rgba[...,3]=(alpha*255).astype(np.uint8)
    Image.fromarray(rgba,'RGBA').save(f'{out}/{k}.png')
    sizes.append(f'{k} {alpha.shape[1]/DPI:.4f} {alpha.shape[0]/DPI:.4f}')
open(f'{out}/sizes.txt','w').write('\n'.join(sizes)); print('\n'.join(sizes))
