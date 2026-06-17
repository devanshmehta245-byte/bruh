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
  service_life_arrhenius.m   <- original MATLAB model (faithfully reproduced)
  generate_results.py        <- Python reproduction: makes figures + results.json
  build_report.py            <- builds the .docx from the code + figures
figures/
  service_life_vs_temperature.png
  acceleration_factor_vs_temperature.png
  results.json               <- computed results table
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

Requires Python 3 with `numpy`, `matplotlib` and `python-docx`:

```bash
pip3 install numpy matplotlib python-docx
python3 code/generate_results.py   # regenerate figures + results.json
python3 code/build_report.py       # regenerate the .docx report
```

The MATLAB script `code/service_life_arrhenius.m` produces the same numbers and
the service-life-vs-temperature plot directly in MATLAB/Octave.
