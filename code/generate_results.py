"""
generate_results.py
-------------------------------------------------------------------------
Faithful Python reproduction of `service_life_arrhenius.m`.

It reproduces, line-for-line, the numerical model coded in the MATLAB script
so that the report can embed real, reproducible results (a temperature vs.
service-life table and figure) without requiring a MATLAB licence.
-------------------------------------------------------------------------
"""

import json
import os

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

FIG_DIR = os.path.join(os.path.dirname(__file__), "..", "figures")
os.makedirs(FIG_DIR, exist_ok=True)

# --- Constants (identical to the MATLAB script) ------------------------------
Ea = 80000.0          # Activation energy, J/mol
R = 8.314             # Universal gas constant, J/(mol*K)
T_service = 300.15    # Service (reference) temperature, K (27 C)
t_test = 60.0         # Test duration, days
E_test = 1.0          # Property measured after the test (normalised)
E_crit = 0.3          # Failure threshold (fraction of initial property)
n = -0.4              # Power-law model exponent

temperatures_C = np.array([25, 27, 30, 35, 40, 45, 50, 60, 70], dtype=float)
T_test = 273.15 + temperatures_C

tf_days = np.zeros_like(T_test)
tf_years = np.zeros_like(T_test)
AF_arr = np.zeros_like(T_test)

for i in range(len(T_test)):
    A = E_test / (t_test ** n)
    inv_T_service = 1.0 / T_service
    inv_T_test = 1.0 / T_test[i]
    X = (Ea / R) * (inv_T_test - inv_T_service)
    AF = A * np.exp(X)

    tf = (E_crit / A) ** (1.0 / n)
    t_service_eq = tf * AF
    tf_days[i] = tf
    tf_years[i] = t_service_eq / 365.25
    AF_arr[i] = AF

# --- Figure 1: Service life vs temperature -----------------------------------
plt.figure(figsize=(7, 4.5))
plt.plot(temperatures_C, tf_years, "-s", color="#1f6feb",
         linewidth=2, markersize=7, label="Service Life (years)")
plt.xlabel("Temperature (\u00b0C)")
plt.ylabel("Service Life (years)")
plt.title("Predicted Service Life vs Temperature")
plt.grid(True, linestyle="--", alpha=0.5)
plt.legend()
plt.tight_layout()
fig1 = os.path.join(FIG_DIR, "service_life_vs_temperature.png")
plt.savefig(fig1, dpi=160)
plt.close()

# --- Figure 2: Acceleration factor vs temperature (log scale) ----------------
plt.figure(figsize=(7, 4.5))
plt.semilogy(temperatures_C, AF_arr, "-o", color="#cf222e",
             linewidth=2, markersize=7, label="Acceleration Factor (AF)")
plt.axvline(27, color="grey", linestyle=":", label="Service temp (27 \u00b0C)")
plt.xlabel("Temperature (\u00b0C)")
plt.ylabel("Acceleration Factor (log scale)")
plt.title("Arrhenius Acceleration Factor vs Temperature")
plt.grid(True, which="both", linestyle="--", alpha=0.5)
plt.legend()
plt.tight_layout()
fig2 = os.path.join(FIG_DIR, "acceleration_factor_vs_temperature.png")
plt.savefig(fig2, dpi=160)
plt.close()

# --- Figure 3: Sensitivity of service life to activation energy --------------
plt.figure(figsize=(7, 4.5))
for Ea_s, colour in zip((60000.0, 80000.0, 100000.0),
                        ("#2da44e", "#1f6feb", "#cf222e")):
    life = np.zeros_like(T_test)
    for i in range(len(T_test)):
        A = E_test / (t_test ** n)
        X = (Ea_s / R) * (1.0 / T_test[i] - 1.0 / T_service)
        AF = A * np.exp(X)
        tf = (E_crit / A) ** (1.0 / n)
        life[i] = (tf * AF) / 365.25
    plt.plot(temperatures_C, life, "-o", color=colour, linewidth=2,
             markersize=5, label=f"Ea = {Ea_s/1000:.0f} kJ/mol")
plt.xlabel("Temperature (\u00b0C)")
plt.ylabel("Service Life (years)")
plt.title("Sensitivity of Predicted Service Life to Activation Energy")
plt.grid(True, linestyle="--", alpha=0.5)
plt.legend()
plt.tight_layout()
fig3 = os.path.join(FIG_DIR, "sensitivity_activation_energy.png")
plt.savefig(fig3, dpi=160)
plt.close()

# --- Dump results table for the report ---------------------------------------
rows = []
print(f"{'Temp (C)':>10} {'AF':>12} {'t_f (days)':>14} {'Service life (yr)':>20}")
for tc, af, td, ty in zip(temperatures_C, AF_arr, tf_days, tf_years):
    print(f"{tc:>10.0f} {af:>12.4f} {td:>14.2f} {ty:>20.3f}")
    rows.append({
        "temperature_C": tc,
        "acceleration_factor": round(af, 4),
        "tf_days": round(td, 2),
        "service_life_years": round(ty, 3),
    })

with open(os.path.join(FIG_DIR, "results.json"), "w") as fh:
    json.dump(rows, fh, indent=2)

print("\nFigures written to:", os.path.abspath(FIG_DIR))
