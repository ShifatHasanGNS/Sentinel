# Renders every slide equation as a transparent PNG in the deck's ink colour, in one font and one size,
# so equations look identical across slides. Natural size is stored in sizes.txt (inches at 14 pt).
import subprocess, os, tempfile
from PIL import Image, ImageChops
import numpy as np
here=os.path.dirname(os.path.abspath(__file__)); out=os.path.join(here,'equation_images')
INK=(0x1E,0x29,0x3B); DPI=600
EQ={
'fractal':r'F(\mathbf{x})=\dfrac{\sum_{i=0}^{n-1}2^{-i}\,\nu(2^{i}\mathbf{x})}{\sum_{i=0}^{n-1}2^{-i}}',
'push':r"\mathbf{p}'=\mathbf{p}+A\,\nu(f\mathbf{p})\,\hat n,\qquad \lVert\mathbf{p}'-\mathbf{p}\rVert\le A",
'mpart':r'M_{\mathrm{part}}=T(\mathbf t)\,R_z(\gamma)\,R_y(\beta)\,R_x(\alpha)\,S(\mathbf s)',
'nmat':r"\hat n'=\dfrac{(L^{-1})^{\top}\hat n}{\lVert (L^{-1})^{\top}\hat n\rVert}",
'mgun':r'M_{\mathrm{gun}}=M_{\mathrm{hull}}\;T(\mathbf c_t)R_y(\theta_t)\;T(\mathbf c_g)R_x(-\theta_g)',
'clip':r'\mathbf p_{\mathrm{clip}}=P\,V\,M_{\mathrm{world}}\,M_{\mathrm{part}}\,\mathbf p',
'ry':r'R_y(\theta)=\begin{pmatrix}\cos\theta&0&\sin\theta\\0&1&0\\-\sin\theta&0&\cos\theta\end{pmatrix}',
'sum':r'L_o=\sum_j f(\mathbf l_j,\mathbf v)\,L_j\,\mathrm{att}_j\,\mathrm{sh}_j\,\max(0,\mathbf n\cdot\mathbf l_j)+\mathrm{ambient}\cdot\mathrm{AO}+\mathbf e',
'lambert':r'f=\dfrac{\mathbf c_d}{\pi}',
'phong':r'f=\dfrac{\mathbf c_d(1-F_0)}{\pi}+F_0\dfrac{m+2}{2\pi}(\mathbf r\cdot\mathbf v)^{m}',
'blinn':r'f=\dfrac{\mathbf c_d(1-F_0)}{\pi}+F_0\dfrac{m+8}{8\pi}(\mathbf n\cdot\mathbf h)^{m}',
'oren':r'f=\dfrac{\mathbf c_d}{\pi}\big(A+B\max(0,\cos\Delta\varphi)\sin\alpha\tan\beta\big)',
'ct2':r'f=\dfrac{(1-F_l)(1-F_v)\,\mathbf c_d}{\pi}+D\,V\,F',
'sss':r'\cos\theta\;\to\;\dfrac{\mathbf n\cdot\mathbf l+w}{1+w},\quad w=0.5',
'att':r'\mathrm{att}(d)=\dfrac{\mathrm{clamp}\big(1-(d/R)^{4},0,1\big)^{2}}{d^{2}+1}',
'spot':r'c=\mathrm{clamp}\Big(\dfrac{\cos\theta-\cos\theta_o}{\cos\theta_i-\cos\theta_o},0,1\Big)^{2}',
'csm':r'z_i=\lambda\,n\Big(\dfrac{r}{n}\Big)^{i/N}+(1-\lambda)\Big(n+(r-n)\dfrac{i}{N}\Big)',
'fog':r'C=T\,C_{s}+(1-T)\,C_{h},\qquad T=e^{-kd}',
'aces':r'C_{\mathrm{out}}=\dfrac{x(2.51x+0.03)}{x(2.43x+0.59)+0.14}',
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
