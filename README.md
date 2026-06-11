# Solid Rocket Propellant — Service-Life Prediction (MATLAB)

A complete MATLAB/Octave pipeline that reads UTM (universal testing machine)
tensile data from an accelerated-ageing campaign, extracts mechanical
properties, trains a machine-learning model of how those properties degrade,
and predicts the **service life** of a composite solid rocket propellant (SRP)
using the classic accelerated-ageing (Arrhenius) methodology.

---

## 1. Data the pipeline expects

Each test is one file whose **name encodes the ageing condition**:

```
T<temp>_d<days>_v<strainRate>_s<sample>.csv
```

| token | meaning                                            | example |
|-------|----------------------------------------------------|---------|
| `T`   | storage / ageing temperature (°C)                  | `T50`   |
| `d`   | days the sample was stored before testing          | `d122`  |
| `v`   | UTM cross-head speed / strain rate (mm/min)        | `v500`  |
| `s`   | sample (replicate) number                          | `s3`    |

so `T50_d122_v500_s3.csv` = 50 °C, stored 122 days, pulled at 500 mm/min,
sample 3.

The campaign described:

* **Temperatures:** 50, 60, 70 °C
* **Ageing times (days):** 50 °C → 38, 75, 122, 156 …; 60 °C → 16, 31, 46 …;
  70 °C → 7, 14, 20 … (hotter ⇒ faster ageing ⇒ shorter times — as expected)
* **Strain rates:** 5, 50, 500 mm/min
* **Replicates:** 10 samples per condition

Files are **`.xlsx`** spreadsheets (one test per file, data on the first
worksheet). `.xls`, `.csv`, `.txt` and `.dat` are also accepted. Each file
contains the three columns from the UTM (header row optional; column order /
names auto-detected):

```
disp_mm , load_N , t_min
```

> **GNU Octave only:** reading `.xlsx` needs the `io` package
> (`pkg install -forge io`, or `apt install octave-io`). `srp_pipeline` loads
> it automatically. **MATLAB needs nothing extra.**

**Specimen geometry** (used to convert load/displacement → stress/strain):

* dog-bone gauge length `L0 = 47.75 mm`
* cross-sectional area  `A0 = 24 mm²`

so engineering **stress = load_N / 24** (MPa) and **strain = disp_mm / 47.75**.

---

> **Want the full theory?** See [`EXPLANATION.md`](EXPLANATION.md) for a
> step-by-step walkthrough of the code and **every equation** used (stress–strain
> definitions, feature formulas, the ML/ridge regression, and the first-order +
> Arrhenius service-life kinetics).

## 2. Quick start

**Everything is in a single file: `srp_pipeline.m`.**

```matlab
% Run everything on a synthetic example dataset (auto-generated if data/ empty):
results = srp_pipeline();

% Run on YOUR data:
results = srp_pipeline('DataDir', '/path/to/your/utm/files');

% Options:
results = srp_pipeline('ServiceTemp', 30, ...         % service temperature (°C)
                       'HealthProperty', 'sigma_max');% property defining EOL

% Built-in self-checks:
srp_pipeline('test');

% Just the default settings struct (to inspect/edit):
cfg = srp_pipeline('config');
```

By default `data/` and `results/` are created next to `srp_pipeline.m`.
Outputs are printed to the console and saved in `results/`:

* `degradation_curves.png` — health property vs ageing time with kinetic fits
* `ml_parity.png` — ML predicted vs measured (cross-validated)
* `arrhenius.png` — `ln(t_fail)` vs `1/T` with the service-temperature point
* `service_life_summary.txt` — the headline numbers

> Works in **MATLAB** (uses the Statistics & Machine Learning Toolbox when
> available) and in **GNU Octave** (falls back to a dependency-free polynomial
> regressor so the pipeline always runs).

---

## 3. How it works

### 3.0 Reading files
Reads `.xlsx`/`.xls` (MATLAB `readcell`; Octave `xlsread` from the `io`
package) and delimited text. Header row and column order are auto-detected
from the aliases in `srp_config` (`disp_mm`/`displacement`, `load_N`/`force`,
`t_min`/`time`).

### 3.1 Feature extraction
For every test the load–displacement curve is converted to engineering
stress–strain and the following mechanical features are computed:

| feature        | meaning                                             |
|----------------|-----------------------------------------------------|
| `sigma_max`    | ultimate tensile stress (MPa)                       |
| `eps_at_max`   | strain at maximum stress (strain capacity)          |
| `eps_break`    | strain at fracture                                  |
| `modulus_MPa`  | initial-region Young's modulus                      |
| `toughness`    | energy density to break (area under curve, MJ/m³)   |
| `secant50_MPa` | secant modulus at 50 % of peak stress               |
| `strain_rate`  | nominal cross-head speed (mm/min)                   |

### 3.2 Machine-learning model
A regression model predicts the chosen **health property** from the ageing
conditions `[temperature, days, strain_rate]`. Several learners are trained and
**k-fold cross-validated**, and the best (lowest CV-RMSE) is kept:

* Gaussian Process Regression (ARD kernel)
* Bagged-tree ensemble (random forest)
* Gaussian-kernel SVM
* Robust linear regression
* Polynomial least-squares (always available — the Octave / no-toolbox fallback)

### 3.3 Service-life prediction
Pure ML cannot extrapolate from the accelerated temperatures (50–70 °C) down to
the in-service temperature (~25 °C), so service life is obtained with the
**accelerated-ageing (Arrhenius) method**, optionally denoised by the ML model:

1. The health property is described jointly over all temperatures by a **global
   kinetic model** in which the pristine value `P0` and asymptote are *shared*
   and only the rate constant follows Arrhenius:
   `k(T) = A·exp(−Ea/RT)`. (A global fit is robust even when the coldest
   temperature shows little degradation within the tested window — the usual
   pitfall of fitting each temperature separately.)
2. An **end-of-life criterion** sets the failure value `P_fail` (default:
   the property has dropped to 50 % of pristine — embrittlement).
3. The **time-to-failure** `t_fail(T)` is evaluated at each temperature; the
   activation energy `Ea` comes straight out of the global fit.
4. `t_fail` is **extrapolated to the service temperature** → predicted service
   life (days and years). The ML model gives an independent `t_fail` cross-check.

This is a *physics-informed ML* approach: ML learns the multi-variable
degradation surface; Arrhenius kinetics provide the trustworthy temperature
extrapolation.

---

## 4. Configuration

All tunables live in the `srp_config` section near the top of `srp_pipeline.m`
(get a copy with `cfg = srp_pipeline('config')`). The most important:

| field                  | default        | meaning                                   |
|------------------------|----------------|-------------------------------------------|
| `gaugeLength_mm`       | `47.75`        | dog-bone gauge length                     |
| `area_mm2`             | `24`           | specimen cross-section                     |
| `healthProperty`       | `'eps_at_max'` | property whose decay defines end-of-life  |
| `healthDirection`      | `'decrease'`   | does it fall or rise with ageing          |
| `failureMode`          | `'relative'`   | `'relative'` or `'absolute'`              |
| `failureFraction`      | `0.50`         | retain 50 % of pristine value             |
| `kineticModel`         | `'firstorder'` | `'firstorder'`, `'linear'`, `'loglinear'` |
| `serviceTemp_C`        | `25`           | in-service temperature for the prediction |
| `referenceStrainRate`  | `50`           | strain rate the criterion refers to       |

> **Choosing the health property / criterion is an engineering decision.**
> For SRP, loss of strain capacity (`eps_at_max`) due to embrittlement is the
> classic ageing-limit; switch to `sigma_max` or `modulus_MPa` and an absolute
> threshold if your qualification spec is stress/stiffness based.

---

## 5. File map

```
srp_pipeline.m   % EVERYTHING (config, file reading, feature extraction,
                 %  ML training, Arrhenius service-life, plots, synthetic
                 %  data generator and self-tests) in one file
data/            % put your UTM files here
results/         % generated figures + summary
```

Inside `srp_pipeline.m` the logic is organised in clearly-labelled sections:
configuration, filename parsing, file reading, feature extraction, dataset
assembly, aggregation, ML model, service-life prediction, plotting, synthetic
data generator and the self-test.

---

## 6. Notes & assumptions

* The synthetic generator (the `generate_synthetic_data` section) creates physically
  plausible curves (embrittlement with ageing, strain-rate hardening, Arrhenius
  kinetics with a known `Ea = 80 kJ/mol`) **only so the pipeline is runnable and
  testable**. Replace `data/` with your measured files — nothing else changes.
* Stress is *engineering* stress (`load/A0`); switch to true stress in
  the feature-extraction section if your gauge cross-section change is significant.
* Service-life extrapolation assumes a single dominant degradation mechanism
  obeying Arrhenius behaviour across 25–70 °C, which is standard practice for
  SRP shelf-life assessment but should be validated against your chemistry.
