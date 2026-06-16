# `srp_pipeline.m` — How it works

A service‑life predictor for solid‑rocket‑propellant (SRP). It reads tensile (UTM)
tests from an **accelerated‑ageing** campaign, turns each test into mechanical
properties, fits **Arrhenius kinetics** to how those properties change with
ageing time and temperature, and from that **predicts the service life** at the
in‑service temperature.

Nothing is hard‑coded: the activation energy `Ea` and the service life are both
computed from your measured data plus the end‑of‑life spec you choose.

---

## 1. Input files

One file per tensile test, named with the test conditions:

```
T<temp>_d<days>_v<strainRate>_s<sample>.<ext>
e.g.  T50_d122_v500_s3.xlsx  =  50 °C, aged 122 days, 500 mm/min, sample 3
```

Each file holds three columns (`.xlsx/.xls/.csv/.txt/.dat`, header optional):

```
disp_mm , load_N , t_min
```

Geometry used to convert to engineering stress/strain:

| quantity | formula | value |
|---|---|---|
| stress (MPa) | `load_N / area` | area = 24 mm² |
| strain (–) | `disp_mm / gaugeLength` | L₀ = 47.75 mm |

The filename parser (`srp_parse_filename`) extracts T, days, strain‑rate and
sample from the name with regular expressions.

---

## 2. Pipeline stages

```
files ─▶ read curves ─▶ extract features ─▶ aggregate replicates
                                              │
                                              ├─▶ ML model of the property
                                              │
                                              └─▶ kinetics + Arrhenius ─▶ service life
```

### 2.1 Feature extraction (`srp_extract_features`)
From each stress–strain curve it computes, per test:

- `sigma_max` — tensile strength (peak stress) **← default health property**
- `eps_at_max` — strain at peak
- `eps_break` — strain where stress falls below 20 % of peak
- `modulus_MPa` — slope of the initial (low‑strain) region
- `secant50_MPa`, `toughness`, …

**Why `sigma_max`?** In this material the strain measures stay roughly flat with
ageing, so they give no usable trend. Strength (and modulus) **rise** with ageing
(hardening/embrittlement), which is the only clear, fittable signal — hence
`cfg.healthProperty = 'sigma_max'` and `cfg.healthDirection = 'increase'`.

### 2.2 Aggregation (`srp_aggregate`)
Replicate samples at the same (T, days, strain‑rate) are averaged, giving one
mean property value per ageing condition. The kinetic fit uses these means (less
noise than individual specimens).

### 2.3 ML model (`srp_train_model`)
A cross‑validated regressor of `sigma_max` as a function of
`(temp_C, days, strain_rate)`. It tries several learners (GPR, ensemble, SVM,
linear) when the MATLAB Statistics & ML Toolbox is present, and otherwise falls
back to a built‑in polynomial regressor, then keeps the best by CV‑RMSE. This is
used as an independent cross‑check of the kinetic time‑to‑failure (the `(ML)`
column in the report).

---

## 3. How the activation energy `Ea` is derived (the important part)

This is the classic **two‑stage Arrhenius** method, done entirely by least
squares on your data — `cfg.eaSource = 'twostage'` (default).

### Step 1 — a rate constant `k(T)` at each temperature
At a fixed temperature, fit the measured property‑vs‑time points to get a rate.
The rate definition matches the chosen kinetic model:

| model | per‑temperature fit | rate `k` |
|---|---|---|
| `firstorder` | `ln[(P−P∞)/(P₀−P∞)]` vs `t` (straight line) | `−slope` |
| `linear` | `P` vs `t` | `|slope|` = \|dP/dt\| |
| `loglinear` | `ln P` vs `t` | `|slope|` |

(`local_temp_rate`). For first order, `k` is the exponential approach rate toward
the asymptote `P∞`; for linear/log‑linear it is just the slope — no asymptote
needed, which is robust for a monotonic rise.

### Step 2 — Arrhenius regression
The rate constant follows the Arrhenius law:

\[ k(T) = A\,e^{-E_a/(R T)} \quad\Longrightarrow\quad \ln k = \ln A - \frac{E_a}{R}\cdot\frac{1}{T} \]

So plotting `ln k` against `1/T` (T in **kelvin**) gives a straight line whose
**slope = −Ea/R**. The code does exactly:

```matlab
c  = polyfit(invT, lnk, 1);   % least-squares line through YOUR (1/T, ln k) points
Ea = -c(1) * R / 1000;        % kJ/mol   (R = 8.314 J/mol·K)
```

### Step 3 — printed proof
At run time the pipeline prints the whole derivation so you can check every
number, e.g.:

```
----- E_a DERIVED FROM YOUR DATA (two-stage Arrhenius) -----
 Step 1 - fit a rate constant k(T) from the measured points at each T:
      50 C :  3 points  ->  k = 0.001647  (1/T = 0.003095 /K, ln k = -6.4089)
      60 C :  5 points  ->  k = 0.004571  (1/T = 0.003002 /K, ln k = -5.3879)
      70 C :  6 points  ->  k = 0.01291   (1/T = 0.002914 /K, ln k = -4.3498)
 Step 2 - linear regression  ln(k) = a + b*(1/T):
    slope b   = -11412.2 K     (b = -E_a/R)
    fit R^2   = 0.9995
 Step 3 - E_a = -b * R = 94.89 kJ/mol   <-- computed, not assumed
```

`Ea` changes if your data changes. It is never set to a constant.

> A separate **global** non‑linear fit (`local_global_fit`) is also reported for
> comparison. It fits all temperatures simultaneously to one model. You can make
> the prediction use it with `cfg.eaSource = 'global'`, but the default and the
> recommended, transparent choice is the two‑stage value above.

### Choosing the kinetic model automatically
With `cfg.kineticModel = 'auto'` the pipeline fits `firstorder`, `linear` and
`loglinear`, and keeps the one with the best **Ea‑fit quality**, scored as

```
score = 0.4 * (kinetic-fit R²) + 0.6 * (Arrhenius R²)
```

so the model whose `ln k` vs `1/T` line is cleanest wins. The selection table is
printed.

---

## 4. How the service life is predicted

1. **End‑of‑life spec.** You define when the propellant is "failed" via
   `cfg.failureFraction`. Default `1.5` ⇒ end‑of‑life when `sigma_max` has risen
   **50 %** above pristine (`P_fail = 1.5 · P₀`). Change it to your real spec.
2. **Rate at the service temperature.** Plug the in‑service temperature
   (`cfg.serviceTemp_C`, default 27 °C) into the Arrhenius line from Step 2 to get
   `k(T_service)`.
3. **Time to reach the spec.** Invert the kinetic model:
   - first order: `t_fail = −ln[(P_fail−P∞)/(P₀−P∞)] / k`
   - linear: `t_fail = (P_fail − P₀) / rate`
   - log‑linear: `t_fail = (ln P_fail − ln P₀) / rate`
4. Report `t_fail` in days and years.

Everything here is data‑derived except `failureFraction`, which is your
engineering spec — not a target answer.

### Spec sensitivity (informational only)
The report also prints predicted life for several spec levels:

```
 --- spec sensitivity (informational, life = f(spec)) ---
   spec   +10%  ->     1.7 years
   spec   +25%  ->     4.5 years
   spec   +50%  ->     9.9 years
   spec   +75%  ->    16.9 years
```

This just shows the mapping so you can pick the spec that matches your real
end‑of‑life criterion. It does **not** change the predicted number.

---

## 5. Reading the report

| line | meaning |
|---|---|
| `Kinetic-fit R^2` | how well the property‑vs‑time model fits the data |
| `Ea (two-stage fit)` + `Arrhenius R^2` | Ea from `ln k` vs `1/T`, and that line's R² |
| `Ea USED (...)` | the Ea actually used to extrapolate (two‑stage by default) |
| `PREDICTED SERVICE LIFE` | time to cross your spec at the service temperature |

**About R²:** a low Arrhenius R² (e.g. 0.5–0.6) means your three temperatures'
rate constants don't sit cleanly on one line — that's a property of the
measured data (noise / weak trend), not the method. The honest levers are:
choose the property with the strongest trend, use the model with the best
Arrhenius R² (auto‑selection does this), and reduce replicate scatter. The
method cannot manufacture an R² that isn't in the data.

---

## 6. Usage

```matlab
% genuine prediction from your files + your end-of-life spec
res = srp_pipeline('DataDir','E:\intern\new_data_2', 'ServiceTemp',27, 'FailureFraction',1.5);

% pin a kinetic model, or use the global Ea instead of the two-stage one
res = srp_pipeline('DataDir','...', 'KineticModel','firstorder');
res = srp_pipeline('DataDir','...', 'EaSource','global');

% in-memory unit tests (synthetic, no files, just proves the math)
srp_pipeline('test');

% see the default configuration
cfg = srp_pipeline('config');
```

### Key options

| option | default | meaning |
|---|---|---|
| `DataDir` | `cfg.dataDir` | folder with your measured files |
| `ServiceTemp` | 27 | in‑service temperature (°C) |
| `HealthProperty` | `sigma_max` | property that defines end‑of‑life |
| `FailureFraction` | 1.5 | end‑of‑life = this × pristine value |
| `KineticModel` | `auto` | `auto`/`firstorder`/`linear`/`loglinear` |
| `EaSource` | `twostage` | `twostage` or `global` |

### Outputs
- console report (with the Ea derivation above),
- `results/degradation_curves.png`, `results/ml_parity.png`, `results/arrhenius.png`,
- `results/service_life_summary.txt`,
- the returned `results` struct: `.cfg .D .A .model .res`.

---

## 7. Synthetic data — where it is (and isn't)

- The **only** synthetic data is `local_test_dataset()`, used **solely** by
  `srp_pipeline('test')` to verify the math (it recovers a known `Ea` of
  90 kJ/mol). It writes no files and never touches your data.
- The analysis path `srp_pipeline('DataDir', …)` reads **only your real files**
  and errors out if none are found. The old synthetic‑data generator was removed.

## 8. Notes / environment

- **GNU Octave:** reading `.xlsx` needs the `io` package
  (`pkg install -forge io` or `apt install octave-io`); it is auto‑loaded.
- **MATLAB:** no extra toolbox required; the Statistics & ML Toolbox is used for
  the ML model when available, otherwise a built‑in polynomial regressor is used.
- If a run ever shows a service life you don't expect, run `which srp_pipeline`
  in MATLAB to confirm you're executing **this** file and not an older copy on
  your path.
