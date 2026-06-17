# Service-Life Prediction of Solid Rocket Propellants

A technical report and the supporting code/figures on **aging and service-life
prediction of solid rocket propellants**, built around an Arrhenius
temperature-acceleration model coupled with a power-law property-degradation
(cumulative-damage) law.

## Contents

```
report/
  Service_Life_Prediction_of_Solid_Propellants.docx   <- main, editable report (Word)
  Service_Life_Prediction_of_Solid_Propellants.md     <- same content, viewable on GitHub
code/
  service_life_arrhenius.m       <- Code 1: Arrhenius screening model (MATLAB)
  abcxyz.m                       <- Code 2: full data-driven SRP pipeline (MATLAB)
  generate_results.py            <- Python reproduction of Code 1 (figures + results.json)
  generate_pipeline_results.py   <- Python reproduction of Code 2 (figures + pipeline_results.json)
  build_report.py                <- builds the .docx from the code + figures
figures/
  service_life_vs_temperature.png
  acceleration_factor_vs_temperature.png
  sensitivity_activation_energy.png
  pipeline_degradation_curves.png
  pipeline_arrhenius.png
  pipeline_ml_parity.png
  results.json / pipeline_results.json   <- computed results
```

## The report

The report is organised as:

1. Introduction (what solid propellants are and why aging matters)
2. Problem statement
3. Literature review (six model families; representative references cited)
4. Governing models and equations (Arrhenius, power-law/cumulative damage,
   time–temperature superposition, Prony series, linear cumulative damage)
5. Implementation — the code, with each variable mapped to its equation
6. Results and discussion (table + figures)
7. Conclusion and future work
8. References
9. Appendix A — practical decision tree

## Reproducing the results

Requires Python 3 with `numpy`, `matplotlib`, `scipy`, `scikit-learn` and
`python-docx`:

```bash
pip3 install numpy matplotlib scipy scikit-learn python-docx
python3 code/generate_results.py            # Code 1 figures + results.json
python3 code/generate_pipeline_results.py   # Code 2 figures + pipeline_results.json
python3 code/build_report.py                # regenerate the .docx report
```

The MATLAB scripts `code/service_life_arrhenius.m` (Code 1) and `code/abcxyz.m`
(Code 2) produce the same numbers and plots directly in MATLAB/Octave. Code 2
runs a synthetic demo out of the box: `abcxyz()` (or `abcxyz('test')` for the
self-test).
