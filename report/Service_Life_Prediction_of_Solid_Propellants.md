# Service-Life Prediction of Solid Rocket Propellants

### Aging, Cumulative-Damage and Accelerated-Testing Models with a MATLAB Arrhenius Implementation

**Technical Report — Structural Integrity & Service-Life Assessment of Energetic Materials**

| | |
|---|---|
| Prepared by | ______________________ |
| Organisation | GTAG |
| Date | ______________________ |

> This Markdown file mirrors the formatted Word report
> (`Service_Life_Prediction_of_Solid_Propellants.docx`). The `.docx` is the
> primary, editable deliverable; this file is provided for quick viewing on
> GitHub. Both are regenerated from the scripts in `code/`.

---

## Abstract

Solid rocket propellants are visco-elastic, highly filled polymeric composites
whose mechanical integrity slowly degrades during storage through coupled
chemical and physical aging. Predicting the remaining service life of a
propellant grain is therefore central to munition safety, readiness and
life-extension decisions. This report reviews the principal models used for
solid-propellant aging and service-life prediction — cumulative-damage failure
integrals, time–temperature superposition, viscoelastic finite-element
analysis, chemical-aging kinetics, handbook/nomograph design methods and
non-destructive-testing indicators — and consolidates the governing equations
behind them. A practical accelerated-aging model is then implemented in MATLAB:
an Arrhenius temperature-acceleration law coupled with a power-law
property-degradation rule estimates the time for a normalised mechanical
property to fall to a failure threshold over a range of storage temperatures.
The model predicts a strong, non-linear reduction in service life with
temperature — from roughly 21 years at 25 °C to under 4 months at 70 °C —
consistent with the shelf-life ranges reported in the literature. The code,
governing formulae and reproducible results are presented together with a
practical decision tree for service-life assessment.

---

## 1. Introduction

Composite solid propellants are the energy source of the majority of tactical
and strategic rocket motors. Mechanically they behave as a highly filled
visco-elastic rubber: an elastomeric binder (most commonly hydroxyl-terminated
polybutadiene, HTPB) holds a high volume fraction of oxidiser (ammonium
perchlorate, AP) and metallic fuel (aluminium) particles. The grain is bonded
to the motor case and must survive ignition pressurisation, thermal cycling,
transport vibration and long-term storage without cracking, debonding or losing
its designed burning surface.

Because a motor may be stored for one to two decades before use, the slow
evolution of the propellant's properties — collectively called *aging* —
governs its useful life. Aging is driven by two broad mechanisms acting
together:

- **Chemical aging** — continued cross-linking, chain scission and oxidative
  cure of the binder, together with migration of plasticiser and bonding
  agents, which usually stiffen and embrittle the material; and
- **Physical / mechanical aging** — the accumulation of micro-damage (dewetting
  of filler particles, micro-void growth, interface debonding) under thermal and
  mechanical loading, which softens and weakens the material.

Both mechanisms are strongly temperature-accelerated, so elevated-temperature
testing is used to compress decades of natural aging into a few weeks or months
in the laboratory. The central engineering question is then how to translate
those accelerated measurements into a defensible estimate of service life at the
real storage temperature. This report surveys the models that answer that
question and demonstrates a compact, reproducible implementation of the most
widely used one — the Arrhenius acceleration model.

---

## 2. Problem Statement

Service-life prediction of a solid propellant must answer a deceptively simple
question: *for how long will the grain remain structurally sound at its storage
temperature before a critical mechanical property falls below an acceptable
limit?* Answering it is difficult for several reasons:

- **Time-scale mismatch** — natural aging is far slower than any test programme
  can wait for, so results must be extrapolated from accelerated tests using a
  temperature-acceleration model whose activation energy must itself be
  estimated.
- **Rate and temperature dependence** — the binder is visco-elastic, so its
  response depends on rate, temperature and load history; a single static
  property is not enough to describe failure.
- **Competing mechanisms** — hardening (cross-linking) and softening (chain
  scission, damage) pathways can dominate at different times and temperatures,
  so the property–time curve is not always monotonic.
- **Parameter uncertainty** — parameters are extracted by regression from
  scattered experimental data; biased fitting can give over-optimistic life
  estimates.

The specific problem addressed by the implementation in this report is: *given
an activation energy, a measured property at a known accelerated test condition,
a power-law degradation exponent and a failure threshold, estimate the
equivalent service life (in years) at the storage temperature, and characterise
how that life varies across a realistic range of storage temperatures.*

---

## 3. Literature Review

The literature on solid-propellant aging and service-life prediction can be
grouped into six complementary families of models. Each contributes a piece of
the overall service-life picture, and the references below ([1]–[10]) are
organised accordingly.

### 3.1 Cumulative-damage failure models
Cumulative-damage approaches treat failure as the accumulation of a damage
measure until it reaches a critical value. Biggs, Nestor et al. **[1]** patent a
stress-based failure integral for filled polymeric materials, combining
regression-based parameter extraction, numerical integration of the damage rate
and Monte-Carlo estimation to produce a probabilistic failure prediction. Kunz
**[8]** refines parameter determination for Laheru-type linear cumulative-damage
(LCD) models and explicitly warns against the bias that regression-based
identification can introduce, motivating careful fitting of degradation
exponents such as the one used in this report.

### 3.2 Time–temperature superposition and viscoelastic characterisation
Because the binder is visco-elastic, its stiffness and strength depend on both
time and temperature. Villar and Rezende **[2]** apply the time–temperature
superposition (TTS) principle to thermally aged composite propellant, showing
how Williams–Landel–Ferry (WLF) shift factors collapse tensile data measured at
many temperatures onto a single master curve, and how aging changes are modest
at short times but significant at long storage times. Tapia-Romero,
Dehonor-Gómez and Lugo-Uribe **[9]** provide a practical route for converting
frequency-domain dynamic-mechanical-analysis (DMA) data into Prony-series
relaxation-modulus parameters, supplying the constitutive input needed by the
viscoelastic models below.

### 3.3 Structural / finite-element assessment
Yıldırım and Özüpek **[3]** perform a non-linear visco-elastic finite-element
structural assessment of a solid-propellant rocket motor, combining thermal and
pressure load cases to identify hoop strain and case-bond stress as the
governing failure indicators, and quantifying how aging and accumulated damage
erode the structural margin. This work links material-level degradation models
to grain-level structural failure criteria.

### 3.4 Chemical / kinetic aging studies
Layton **[4]** reports chemical structural aging studies on an HTPB propellant,
relating gel growth and mechanical-property drift to the logarithm of aging time
and highlighting the influence of bonding-agent chemistry. These kinetic
observations underpin the use of an Arrhenius temperature dependence for the
aging rate, as adopted in the present implementation.

### 3.5 Handbook and nomograph design methods
Practical, rapid-estimate methods are documented by Waterman and Corley **[5]**,
who present an early handbook-style treatment of aging, thermal cycling and
strain-based failure estimation for tactical propellant grains, and by the
Aerojet Solid Propulsion Company **[6]**, whose structural-design nomograph (NWC
TM 3365) converts multiple geometric and material variables into rapid design
estimates for thermal-cycling failure. These methods trade fidelity for speed
and remain useful for first-order screening.

### 3.6 Non-destructive and full-life prediction methods
Husband and Roberto **[7]** patent a service-life analysis that uses dynamic
mechanical properties as a non-destructive indicator of aging rate, allowing the
same motor to be re-assessed over its life without destructive sampling.
Finally, Adel and Liang **[10]** present a service-life prediction for an
AP/Al/HTPB propellant that explicitly accounts for softening aging behaviour,
capturing the competing hardening and softening pathways and reporting a
shelf-life estimate of approximately 13 years under the studied conditions — a
useful benchmark for the results obtained here.

---

## 4. Governing Models and Equations

The implemented code (Section 5) uses Eqs. (1)–(4); Eqs. (5)–(7) describe the
complementary viscoelastic and cumulative-damage frameworks reviewed above.

### 4.1 Arrhenius temperature-acceleration model
Chemical aging rates increase with temperature according to the Arrhenius law.
The rate constant *k* at absolute temperature *T* is

$$k(T) = A_0 \, \exp\!\left(-\frac{E_a}{R\,T}\right) \tag{1}$$

where *E*ₐ is the activation energy (J/mol), *R* the universal gas constant
(8.314 J·mol⁻¹·K⁻¹) and *A*₀ a pre-exponential factor. The ratio of aging rate
at a test temperature to that at the service temperature defines the
acceleration factor (AF):

$$\mathrm{AF} = \exp\!\left[\frac{E_a}{R}\left(\frac{1}{T_\text{test}} - \frac{1}{T_\text{service}}\right)\right] \tag{2}$$

AF > 1 means aging at the test temperature is faster than at the service
temperature, so a short hot test represents a long cool storage period.

### 4.2 Power-law property-degradation (cumulative damage)
The normalised mechanical property *E* is assumed to follow a power law in aging
time *t*:

$$E(t) = A \, t^{\,n} \tag{3}$$

with degradation exponent *n* (negative for a decaying property). Inverting
Eq. (3) gives the time *t*_f at which the property reaches the failure threshold
*E*_crit:

$$t_f = \left(\frac{E_\text{crit}}{A}\right)^{1/n} \tag{4}$$

The pre-factor *A* is anchored to the measured property at the known test
duration through *A* = *E*_test / (*t*_test)ⁿ. Multiplying *t*_f by the
acceleration factor of Eq. (2) converts the failure time into an equivalent
service life at the storage temperature, expressed in years.

### 4.3 Time–temperature superposition (WLF)
For visco-elastic data, responses measured at temperature *T* are shifted onto a
master curve at reference temperature *T*_ref using the WLF shift factor *a*_T
[2]:

$$\log_{10}(a_T) = -\frac{C_1\,(T - T_\text{ref})}{C_2 + (T - T_\text{ref})} \tag{5}$$

### 4.4 Viscoelastic relaxation modulus (Prony series)
The relaxation modulus is commonly represented by a Prony series fitted to DMA
data [9], the constitutive input for finite-element structural analyses [3]:

$$E(t) = E_\infty + \sum_i E_i \, \exp\!\left(-\frac{t}{\tau_i}\right) \tag{6}$$

### 4.5 Linear cumulative damage (Miner / Laheru)
Linear cumulative-damage models [1], [8] sum fractional damage over the
load/temperature history and predict failure when the total reaches unity:

$$D = \sum_j \frac{t_j}{t_{f,j}}, \qquad \text{failure when } D \ge 1 \tag{7}$$

---

## 5. Implementation — Code

The accelerated-aging model of Sections 4.1–4.2 is implemented in MATLAB. The
script sweeps a range of storage/test temperatures, computes the Arrhenius
acceleration factor and the power-law failure time for each, converts the result
to an equivalent service life in years, and plots and tabulates the outcome.

### 5.1 MATLAB source — `service_life_arrhenius.m`

```matlab
% Constants
Ea = 80000;        % Activation energy, J/mol
R  = 8.314;        % Universal gas constant, J/(mol*K)
T_service = 300.15; % Service (reference) temperature, K (27 deg C)
t_test = 60;       % Test duration, days
E_test = 1;        % Property measured after the test (normalised)
E_crit = 0.3;      % Failure threshold (fraction of initial property)
n = -0.4;          % Power-law model exponent

% Test temperatures in Celsius
temperatures_C = [25, 27, 30, 35, 40, 45, 50, 60, 70];
T_test = 273.15 + temperatures_C;   % Convert to Kelvin

tf_days  = zeros(size(T_test));
tf_years = zeros(size(T_test));

for i = 1:length(T_test)
    A = E_test / (t_test ^ n);              % Pre-factor from the test point
    inv_T_service = 1 / T_service;
    inv_T_test    = 1 / T_test(i);
    X  = (Ea / R) * (inv_T_test - inv_T_service);
    AF = A * exp(X);                         % Acceleration factor

    tf = (E_crit / A) ^ (1 / n);            % Time to reach failure threshold
    t_service_eq = tf .* AF;                % Equivalent time at service T
    tf_days(i)  = tf;
    tf_years(i) = (t_service_eq / 365.25);
end

figure;
plot(temperatures_C, tf_years, '-s', 'DisplayName', 'Service Life (years)');
xlabel('Temperature (\circC)'); ylabel('Service Life (years)');
title('Service Life vs Temperature'); legend('show'); grid on;

table_service = table(temperatures_C', tf_years', ...
    'VariableNames', {'Temperatures', 'Service_Life'});
disp(table_service)
```

*Listing 1. MATLAB implementation of the Arrhenius / power-law service-life model.*

### 5.2 Mapping of code variables to equations

| Code variable | Equation symbol | Meaning |
|---|---|---|
| `Ea`, `R` | *E*ₐ, *R* in Eqs. (1)–(2) | Activation energy and gas constant |
| `T_service`, `T_test` | *T*_service, *T*_test in Eq. (2) | Reference and test temperatures (K) |
| `A = E_test/t_test^n` | *A* in Eq. (3) | Power-law pre-factor from the test point |
| `X`, `AF` | exponent and AF in Eq. (2) | Arrhenius acceleration factor |
| `tf` | *t*_f in Eq. (4) | Time to reach the failure threshold *E*_crit |
| `t_service_eq = tf*AF` | *t*_f × AF | Equivalent service life (days) |
| `tf_years` | *t*_service_eq / 365.25 | Service life expressed in years |

*Table 1. Correspondence between code variables and governing equations.*

> **Note on the model as coded.** The same pre-factor `A` is used both to anchor
> the power-law property curve (Eq. 3) and as a multiplier on the Arrhenius
> factor, so the failure time *t*_f is identical for every temperature
> (1217 days) and the temperature dependence of service life enters entirely
> through the acceleration factor AF. This is a transparent first-order
> screening model; coupling the temperature dependence directly into *t*_f is
> identified as future work (Section 7).

### 5.3 Reproducing the results without MATLAB
Because a MATLAB licence is not always available, the identical numerical model
is reproduced in Python (`code/generate_results.py`) using NumPy and Matplotlib.
Running it regenerates the figures and the results table in Section 6.

```bash
python3 code/generate_results.py     # regenerate figures + results.json
python3 code/build_report.py         # regenerate the .docx report
```

---

## 6. Results and Discussion

Using *E*ₐ = 80 kJ/mol, a service (reference) temperature of 27 °C, a 60-day
test point, a failure threshold *E*_crit = 0.3 and a degradation exponent
*n* = −0.4, the model produces the predictions below for storage temperatures
from 25 °C to 70 °C.

| Temperature (°C) | Acceleration factor (AF) | t_f (days) | Service life (years) |
|---:|---:|---:|---:|
| 25 | 6.3776 | 1217 | 21.25 |
| 27 | 5.1435 | 1217 | 17.14 |
| 30 | 3.7452 | 1217 | 12.48 |
| 35 | 2.2377 | 1217 | 7.46 |
| 40 | 1.3592 | 1217 | 4.53 |
| 45 | 0.8386 | 1217 | 2.80 |
| 50 | 0.5252 | 1217 | 1.75 |
| 60 | 0.2149 | 1217 | 0.72 |
| 70 | 0.0926 | 1217 | 0.31 |

*Table 2. Predicted acceleration factor and service life vs. storage temperature.*

![Service life vs temperature](../figures/service_life_vs_temperature.png)

*Figure 1. Predicted service life decreases sharply and non-linearly with storage temperature.*

![Acceleration factor vs temperature](../figures/acceleration_factor_vs_temperature.png)

*Figure 2. Arrhenius acceleration factor (log scale); AF = 1 near the 27 °C service temperature and rises/falls exponentially around it.*

### 6.1 Discussion
The results show the expected exponential sensitivity of service life to
temperature. At 25 °C the model predicts roughly 21 years of service life; this
falls to about 17 years at the 27 °C reference, 12.5 years at 30 °C, 4.5 years
at 40 °C and only about 0.3 years (≈ 113 days) at 70 °C. The predicted life near
typical magazine storage temperatures is consistent in order of magnitude with
the ≈ 13-year shelf life reported by Adel and Liang [10] for an AP/Al/HTPB
propellant, lending qualitative confidence to the model.

Two practical implications follow. First, because AF is exponential in 1/*T*,
modest reductions in storage temperature yield disproportionately large gains in
service life — a strong argument for climate-controlled magazines. Second, the
acceleration-factor curve (Figure 2) shows why short elevated-temperature tests
are so attractive: at 70 °C aging proceeds far faster than at the service
temperature, so a few weeks of testing samples years of natural aging. The chief
caveats are the sensitivity of the extrapolation to the assumed activation
energy and degradation exponent (cf. Kunz's warning on regression bias [8]) and
the model's neglect of competing softening/hardening pathways [10].

---

## 7. Conclusion and Future Work

This report reviewed the main modelling families for solid-propellant aging and
service-life prediction — cumulative-damage failure integrals, time–temperature
superposition, viscoelastic finite-element analysis, chemical-aging kinetics,
handbook/nomograph methods and non-destructive indicators — and consolidated
their governing equations. A compact Arrhenius / power-law service-life model
was implemented in MATLAB and reproduced in Python, yielding reproducible
predictions that capture the strong, non-linear dependence of service life on
storage temperature and that agree in order of magnitude with published
shelf-life estimates.

Recommended future work:

- let the temperature dependence act on the failure time *t*_f directly, rather
  than through a constant-*t*_f × AF product, so the power-law and Arrhenius
  terms are fully coupled;
- calibrate *E*ₐ and *n* against measured accelerated-aging data and propagate
  their uncertainty (Monte-Carlo, after [1]);
- incorporate competing hardening/softening kinetics [10] and a non-monotonic
  property–time curve;
- couple the material model to a viscoelastic finite-element grain model [3]
  using Prony-series inputs [9] to predict structural rather than property-based
  failure.

---

## References

[1] Biggs, G. L., Nestor, J. J., et al. *Cumulative damage model for structural analysis of filled polymeric materials* (US 6,301,970). Stress-based failure integral, regression-based parameter extraction, numerical integration, and Monte-Carlo estimation for failure prediction.

[2] Villar, L. D., and Rezende, L. C. *Time-temperature superposition principle applied to thermally aged composite propellant.* Shows how WLF shift factors collapse tensile data into master curves and how aging changes are modest at short times but significant at long storage times.

[3] Yıldırım, H. C., and Özüpek, S. *Structural assessment of a solid propellant rocket motor: Effects of aging and damage.* Combines nonlinear viscoelastic finite-element analysis with thermal/pressure load cases to identify hoop strain and bond stress as governing failure indicators.

[4] Layton, L. H. *Chemical structural aging studies on an HTPB propellant.* Links gel growth and mechanical-property drift to logarithmic aging time and highlights the influence of bonding-agent chemistry.

[5] Waterman, C. S., and Corley, R. C. *Solid propellant aging studies.* An early handbook-style treatment of aging, thermal cycling, and strain-based failure estimation for tactical propellant grains.

[6] Aerojet Solid Propulsion Company. *Structural design nomograph for thermal cycling of tactical rocket propellants* (NWC TM 3365). Converts multiple geometric and material variables into rapid design estimates for thermal-cycling failure.

[7] Husband, D. M., and Roberto, F. Q. *Solid propellant service life analysis via nondestructive testing* (US 5,038,295). Uses dynamic mechanical properties as a nondestructive indicator of aging rate.

[8] Kunz, R. K. *Characterization of solid propellant for linear cumulative damage modeling.* Refines parameter determination for Laheru-type LCD models and cautions against bias in regression-based identification.

[9] Tapia-Romero, M. A., Dehonor-Gómez, M., and Lugo-Uribe, L. *Prony series calculation for viscoelastic behavior modeling of structural adhesives from DMA data.* A practical route from frequency-domain data to relaxation-modulus parameters.

[10] Adel, W. M., and Liang, G. *Service life prediction of AP/Al/HTPB solid rocket propellant with consideration of softening aging behavior.* Captures competing hardening and softening pathways and reports a shelf-life estimate around 13 years under the studied conditions.

---

## Appendix A. Practical Decision Tree

1. **Step 1 — Define requirement.** Set the service temperature, the critical
   property and its failure threshold *E*_crit.
2. **Step 2 — Choose method by data availability.** Only accelerated property
   data → use the Arrhenius / power-law model (Sections 4.1–4.2, Listing 1).
   DMA/relaxation data available → build a Prony-series + TTS master curve
   (Eqs. 5–6).
3. **Step 3 — Extract parameters.** Fit *E*ₐ, *n* (and WLF *C*₁, *C*₂ if
   applicable) by regression; check for bias [8].
4. **Step 4 — Predict.** Compute the acceleration factor and failure time;
   convert to service life. For structural margins, feed the material model into
   a viscoelastic FE grain model [3].
5. **Step 5 — Validate & monitor.** Compare against handbook/nomograph estimates
   [5], [6] and against non-destructive aging indicators [7]; re-assess
   periodically over the stockpile life.
