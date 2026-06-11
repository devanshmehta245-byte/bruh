# `srp_pipeline.m` — How it works & all the equations

This document explains, step by step, what the single file `srp_pipeline.m` does
to turn your UTM (universal testing machine) tensile tests into a predicted
**service life** for a solid rocket propellant (SRP), and lists every equation
used.

Notation used throughout:

| symbol | meaning | unit |
|--------|---------|------|
| \(F\) | measured load (`load_N`) | N |
| \(\delta\) | cross-head displacement (`disp_mm`) | mm |
| \(t_{\min}\) | elapsed test time (`t_min`) | min |
| \(A_0\) | specimen cross-sectional area = **24** | mm² |
| \(L_0\) | specimen gauge length = **47.75** | mm |
| \(\sigma\) | engineering stress | MPa |
| \(\varepsilon\) | engineering strain | – |
| \(T\) | ageing temperature | °C or K |
| \(t\) | ageing time | days |
| \(v\) | UTM cross-head speed / strain rate | mm/min |
| \(P\) | "health" property tracked for ageing | (depends) |
| \(R\) | gas constant = 8.314462618 | J·mol⁻¹·K⁻¹ |
| \(E_a\) | activation energy | J/mol (reported kJ/mol) |

---

## 0. The big picture

```
xlsx files            features per test        aged-property model        service life
T..d..v..s..   ──►   σ_max, ε_max, E, ...  ──►  ML + Arrhenius kinetics ──►  years @ 25 °C
(disp,load,t)        (stress–strain math)       (degradation vs T, t)
```

The code is **physics-informed machine learning**:
* an **ML model** learns how a mechanical property degrades with ageing
  temperature, time and strain rate, and
* **Arrhenius kinetics** convert that degradation into a service life and
  extrapolate from the accelerated test temperatures (50–70 °C) down to the
  in-service temperature (~25 °C), which pure ML cannot do reliably.

---

## 1. Reading the filename  (`srp_parse_filename`)

Each file is named `T<temp>_d<days>_v<rate>_s<sample>`. A regular expression
pulls the four numbers out, e.g. `T50_d122_v500_s3` →
\(T=50\,^\circ\text{C},\ t=122\ \text{days},\ v=500\ \text{mm/min},\ \text{sample}=3\).

No equation — just parsing. These become the **inputs/labels** of every test.

---

## 2. Reading the curve  (`srp_read_curve`)

Reads the three columns `disp_mm, load_N, t_min` from `.xlsx` (or csv/txt).
Header row and column order are auto-detected. Rows with non-finite load or
displacement are dropped.

---

## 3. Feature extraction — stress–strain analysis  (`srp_extract_features`)

The raw load–displacement curve is converted to **engineering stress–strain**:

**Stress**
\[
\sigma = \frac{F}{A_0} = \frac{F}{24}\quad[\text{MPa, since N/mm}^2=\text{MPa}]
\]

**Strain**
\[
\varepsilon = \frac{\delta}{L_0} = \frac{\delta}{47.75}\quad[-]
\]

**Strain rate** (true rate from the cross-head speed)
\[
\dot{\varepsilon} = \frac{v}{L_0}\quad[\text{min}^{-1}]
\]

From the \((\varepsilon,\sigma)\) curve the following features are computed
(these are the mechanical properties used by the ML model):

**Ultimate tensile strength** (peak stress) and the strain at which it occurs
\[
\sigma_{\max}=\max_i \sigma_i,\qquad
\varepsilon_{\text{at max}}=\varepsilon_{\,\arg\max_i \sigma_i}
\]

**Strain at break** — the first point *after* the peak where the stress falls
below a fraction \(f_b=0.20\) of the peak (specimen fracture); if it never does,
the last recorded strain is used:
\[
\varepsilon_{\text{break}} = \varepsilon_{\,j},\quad
j=\min\{\,i>i_\text{peak} : \sigma_i < f_b\,\sigma_{\max}\,\}
\]

**Young's modulus** — slope of the initial (approximately linear) region,
obtained by least-squares fitting a line over
\(\varepsilon \in [0,\ 0.25\,\varepsilon_{\text{at max}}]\):
\[
E=\left.\frac{d\sigma}{d\varepsilon}\right|_{\text{initial}}
 =\text{slope of } \min_{a,b}\sum_i\big(\sigma_i-(a\varepsilon_i+b)\big)^2
 \quad[\text{MPa}]
\]

**Secant modulus at 50 % of peak**
\[
E_{50}=\frac{\sigma(\varepsilon^\ast)}{\varepsilon^\ast},\quad
\varepsilon^\ast=\text{first }\varepsilon\text{ with }\sigma\ge 0.5\,\sigma_{\max}
\]

**Toughness** — energy absorbed per unit volume = area under the stress–strain
curve up to break (trapezoidal integration):
\[
U=\int_0^{\varepsilon_{\text{break}}}\sigma\,d\varepsilon
 \approx \sum_i \tfrac{1}{2}(\sigma_{i+1}+\sigma_i)(\varepsilon_{i+1}-\varepsilon_i)
 \quad[\text{MJ/m}^3]
\]

---

## 4. Aggregation over replicates  (`srp_aggregate`)

For each unique ageing condition \((T,t,v)\) the 10 replicate samples are
averaged, with the spread kept for the error bars:
\[
\bar P_{(T,t,v)}=\frac{1}{n}\sum_{i=1}^{n}P_i,\qquad
s_{(T,t,v)}=\sqrt{\frac{1}{n-1}\sum_{i=1}^{n}\big(P_i-\bar P\big)^2}
\]

---

## 5. Machine-learning model  (`srp_train_model`)

A regression model predicts the chosen **health property** \(P\) (default
\(P=\varepsilon_{\text{at max}}\), the strain capacity) from the ageing
conditions:
\[
P \;=\; f(\mathbf{x}),\qquad \mathbf{x}=[\,T,\ t,\ v\,]
\]

Several learners are tried and the best (lowest cross-validated error) is kept:
Gaussian-process regression, bagged-tree ensemble (random forest), Gaussian-SVM
and robust linear regression (MATLAB Statistics & ML Toolbox), **plus** a
dependency-free polynomial regressor that always runs.

### Polynomial fallback (always available)
Predictors are standardised
\[
z_k=\frac{x_k-\mu_k}{s_k}
\]
and expanded into a basis with linear, quadratic, pairwise-interaction and a
log-time term (ageing saturates, so \(\log(t+1)\) helps):
\[
\boldsymbol\Phi(\mathbf{x}) = \big[\,1,\ z_k,\ z_k^2,\ z_iz_j\ (i<j),\ \log(t+1)\,\big]
\]
Coefficients are found by **ridge (regularised least squares)**:
\[
\boldsymbol\beta=\big(\boldsymbol\Phi^\top\boldsymbol\Phi+\lambda \mathbf{I}\big)^{-1}\boldsymbol\Phi^\top \mathbf{y},
\qquad
\lambda = 10^{-6}\,\frac{\operatorname{tr}(\boldsymbol\Phi^\top\boldsymbol\Phi)}{\#\text{cols}}
\]
and predictions are \(\hat P=\boldsymbol\Phi(\mathbf{x})\,\boldsymbol\beta\).

### Model scoring (k-fold cross-validation)
Data is split into \(k=5\) folds; each fold is predicted by a model trained on
the others. Quality metrics:
\[
\text{RMSE}=\sqrt{\frac{1}{m}\sum_i\big(y_i-\hat y_i\big)^2},
\qquad
R^2 = 1-\frac{\sum_i (y_i-\hat y_i)^2}{\sum_i (y_i-\bar y)^2}
\]

---

## 6. Service-life prediction — accelerated-ageing kinetics  (`srp_service_life`)

This is the heart of the method. The averaged health property at the reference
strain rate is described as a function of ageing time and temperature, the
end-of-life is defined, the time-to-failure is found at each temperature, and
the result is extrapolated to the service temperature via Arrhenius.

### 6.1 Degradation (kinetic) model

Default is **first-order** kinetics toward an asymptote \(P_\infty\):
\[
\boxed{\,P(t,T)=P_\infty+\big(P_0-P_\infty\big)\,e^{-k(T)\,t}\,}
\]
with the rate constant following the **Arrhenius law**:
\[
\boxed{\,k(T)=A\,e^{-E_a/(R\,T_K)}\,},\qquad T_K = T+273.15
\]

For numerical conditioning the code fits the rate **relative to a reference
temperature** \(T_\text{ref}\) (the median test temperature), which is
mathematically identical:
\[
k(T)=k_\text{ref}\,\exp\!\Big[-\frac{E_a}{R}\Big(\frac{1}{T_K}-\frac{1}{T_{\text{ref},K}}\Big)\Big]
\]

Alternative models (selectable via `cfg.kineticModel`):

* **Linear / zero-order:** \(P(t,T)=P_0 + b(T)\,t,\quad b(T)=\pm A\,e^{-E_a/RT_K}\)
* **Log-linear (first-order on the value itself):**
  \(\ln P(t,T)=\ln P_0 + b(T)\,t\)

### 6.2 Global fit (why it is robust)

All temperatures are fit **simultaneously** with **shared** \(P_0\) and
\(P_\infty\) and only \(k(T)\) varying with temperature. Parameters
\(\boldsymbol\theta=(P_0,P_\infty,\ln k_\text{ref},E_a)\) minimise the
sum of squared errors over every aggregated point, with a soft penalty keeping
\(E_a\) physical:
\[
\min_{\boldsymbol\theta}\ \sum_{(T,t)}\big(\bar P_{(T,t)}-P(t,T;\boldsymbol\theta)\big)^2
\;+\; w\Big[\max(0,20-E_a)^2+\max(0,E_a-250)^2\Big]
\]
(\(E_a\) in kJ/mol, \(w=10^3\,\text{span}^2\)). The minimisation uses
Nelder–Mead (`fminsearch`) with multiple \(E_a\) starting seeds; the best fit is
kept. This avoids the classic failure of fitting each temperature separately,
where the coldest temperature shows too little degradation to be identifiable.

Goodness of fit:
\[
R^2_\text{kin}=1-\frac{\sum(\bar P-\hat P)^2}{\sum(\bar P-\overline{\bar P})^2}
\]

### 6.3 End-of-life criterion

The pristine value \(P_0\) comes from the fit. The propellant is declared
unserviceable when \(P\) reaches the failure threshold \(P_\text{fail}\):

* **Relative** (default): \(P_\text{fail}=f\cdot P_0\) with \(f=0.5\)
  (retain 50 % of the pristine strain capacity).
* **Absolute:** \(P_\text{fail}=\) a fixed value you set.

### 6.4 Time-to-failure (invert the kinetic model)

For first-order kinetics, set \(P(t_\text{fail},T)=P_\text{fail}\) and solve:
\[
\boxed{\,t_\text{fail}(T)=-\frac{1}{k(T)}\,
\ln\!\Big(\frac{P_\text{fail}-P_\infty}{P_0-P_\infty}\Big)\,}
\]
For the linear and log-linear models:
\[
t_\text{fail}=\frac{P_\text{fail}-P_0}{b(T)}
\qquad\text{and}\qquad
t_\text{fail}=\frac{\ln P_\text{fail}-\ln P_0}{b(T)}
\]

### 6.5 Arrhenius extrapolation → service life

Because \(k(T)\propto e^{-E_a/RT_K}\), the time-to-failure is linear in
\(1/T_K\) on a log axis:
\[
\boxed{\,\ln t_\text{fail}(T)=C+\frac{E_a}{R}\cdot\frac{1}{T_K}\,}
\]
i.e. a straight line whose **slope is \(E_a/R\)**. The activation energy is read
off directly from the global fit:
\[
E_a=\text{slope}\times R\quad\Rightarrow\quad
E_{a}\,[\text{kJ/mol}]=\frac{\text{slope}\cdot R}{1000}
\]
The **predicted service life** is this line evaluated at the service temperature
\(T_s\) (default 25 °C):
\[
\boxed{\,t_\text{SL}=t_\text{fail}(T_s)
 =\exp\!\Big(C+\frac{E_a}{R}\cdot\frac{1}{T_{s,K}}\Big)\,}
\qquad
\text{years}=\frac{t_\text{SL}}{365.25}
\]

### 6.6 Acceleration factor

How much each oven test accelerates ageing relative to service conditions:
\[
\text{AF}(T)=\frac{t_\text{SL}}{t_\text{fail}(T)}
\]

### 6.7 Role of the ML model here

The trained ML model gives an **independent, smooth** estimate of the
time-to-failure at each test temperature (it finds where its predicted
\(P(t)\) curve crosses \(P_\text{fail}\)), printed alongside the kinetic value as
a cross-check. The headline service life is taken from the physically-grounded
global Arrhenius fit, since ML must not extrapolate outside the 50–70 °C training
range.

---

## 7. Outputs  (`srp_plot_results`, summary file)

* `degradation_curves.png` — \(\bar P\) vs ageing time per temperature with the
  fitted kinetic curves and the \(P_\text{fail}\) line.
* `ml_parity.png` — ML predicted vs measured property (with CV \(R^2\)).
* `arrhenius.png` — \(\ln t_\text{fail}\) vs \(1/T_K\) line with the service
  point marked; the title shows \(E_a\) and the predicted life.
* `service_life_summary.txt` — all headline numbers.

---

## 8. The synthetic data generator  (`generate_synthetic_data`)

Used only to make a runnable/testable example (replace `data/` with your real
files and nothing else changes). It builds physically plausible curves:

Ageing trends (with Arrhenius rate \(k(T)\), ground-truth \(E_a=80\) kJ/mol):
\[
\varepsilon_M(t,T)=\varepsilon_\infty+(\varepsilon_0-\varepsilon_\infty)e^{-k t}
\quad(\text{embrittlement, }\downarrow)
\]
\[
\sigma_M(t,T)=\sigma_0+\Delta\sigma\,(1-e^{-k t})
\quad(\text{cure/stiffening, }\uparrow)
\]
Strain-rate (viscoelastic) factors with \(v_\text{ref}=50\):
\[
\sigma_M \mathrel{*}= (v/v_\text{ref})^{0.08},\qquad
\varepsilon_M \mathrel{*}= (v_\text{ref}/v)^{0.04}
\]
Each curve shape peaks at \((\varepsilon_M,\sigma_M)\):
\[
\sigma(\varepsilon)=\sigma_M\,\frac{\varepsilon}{\varepsilon_M}\,
\exp\!\Big(1-\frac{\varepsilon}{\varepsilon_M}\Big)
\]
and is written back as raw UTM columns:
\[
\delta=\varepsilon\,L_0,\qquad F=\sigma\,A_0,\qquad t_{\min}=\frac{\delta}{v}
\]

Running the pipeline on this synthetic set recovers \(E_a\approx 83\) kJ/mol
(vs the 80 used to build it), confirming the method works.

---

## 9. Key assumptions (please review for your material)

1. **Health property & threshold** — default tracks strain capacity
   \(\varepsilon_{\text{at max}}\) dropping to 50 % of pristine (embrittlement).
   Change `cfg.healthProperty`, `cfg.failureMode`, `cfg.failureFraction` to match
   your qualification spec (e.g. a max-stress or modulus limit).
2. **Single Arrhenius mechanism** — one dominant degradation process obeying
   \(k=A e^{-E_a/RT}\) across 25–70 °C (standard SRP shelf-life practice).
3. **Engineering stress/strain** — based on the original area \(A_0\) and gauge
   length \(L_0\); switch to true stress/strain if the cross-section changes a lot.
4. **Service temperature** — default 25 °C; set `cfg.serviceTemp_C` to your real
   storage temperature.
