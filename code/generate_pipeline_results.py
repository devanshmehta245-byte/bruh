"""
generate_pipeline_results.py
-------------------------------------------------------------------------
Faithful Python reproduction of the data-driven pipeline in `abcxyz.m`.

It mirrors the MATLAB code's synthetic-data generator, feature extraction
(eps_at_max), replicate aggregation, global first-order Arrhenius kinetic fit,
cross-validated ML surrogate and service-life extrapolation, so the report can
embed real, reproducible figures and numbers without a MATLAB licence.
-------------------------------------------------------------------------
"""

import json
import os

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.optimize import minimize
from sklearn.linear_model import Ridge
from sklearn.model_selection import cross_val_predict, KFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import PolynomialFeatures, StandardScaler
from sklearn.metrics import r2_score, mean_squared_error

FIG_DIR = os.path.join(os.path.dirname(__file__), "..", "figures")
os.makedirs(FIG_DIR, exist_ok=True)

# --- configuration / ground-truth generator constants (from abcxyz.m) --------
R = 8.314462618
A_k = 5e9
Ea_true = 80000.0            # J/mol
eps0, epsInf = 0.40, 0.10
sig0, dSig = 0.50, 0.45
vref = 50.0
nRate_eps = 0.04
temperatures_C = [50, 60, 70]
days_by_temp = {50: [38, 75, 122, 156, 190],
                60: [16, 31, 46, 62, 78],
                70: [7, 14, 20, 27, 34]}
strain_rates = [5, 50, 500]
nSamples = 10
noise = 0.04
serviceTemp_C = 27.0
failureFraction = 0.50

rng = np.random.default_rng(42)

# --- 1. synthetic data + feature extraction (eps_at_max == epsM) -------------
rows = []   # (temp_C, days, strain_rate, eps_at_max)
for T in temperatures_C:
    k_true = A_k * np.exp(-Ea_true / (R * (T + 273.15)))
    for d in days_by_temp[T]:
        decay = np.exp(-k_true * d)
        epsM_base = epsInf + (eps0 - epsInf) * decay
        for v in strain_rates:
            rfac_eps = (vref / v) ** nRate_eps
            for _s in range(nSamples):
                epsM = max(0.02, epsM_base * (1 + noise * rng.standard_normal()) * rfac_eps)
                rows.append((float(T), float(d), float(v), epsM))

rows = np.array(rows)
temp_all, days_all, rate_all, eps_all = rows.T
n_files = len(rows)

# --- 2. aggregate replicates at the reference strain rate --------------------
ref = rate_all == vref
agg = {}
for T in temperatures_C:
    for d in days_by_temp[T]:
        m = ref & (temp_all == T) & (days_all == d)
        agg[(T, d)] = (eps_all[m].mean(), eps_all[m].std())
n_conditions = len(set(zip(temp_all.tolist(), days_all.tolist(), rate_all.tolist())))

t_fit = np.array([d for T in temperatures_C for d in days_by_temp[T]])
T_fit = np.array([T for T in temperatures_C for _ in days_by_temp[T]])
P_fit = np.array([agg[(T, d)][0] for T in temperatures_C for d in days_by_temp[T]])

# --- 3. global first-order Arrhenius kinetic fit -----------------------------
# P(t,T) = Pinf + (P0 - Pinf) * exp(-k(T) t),
# k(T)   = exp(lnkref - (Ea*1000/R) (1/TK - 1/TrefK))
TK_fit = T_fit + 273.15
TrefK = np.median(TK_fit)
span = P_fit.max() - P_fit.min()


def k_of_T(lnkref, Ea_kJ, TK):
    return np.exp(lnkref - (Ea_kJ * 1000.0 / R) * (1.0 / TK - 1.0 / TrefK))


def model_P(theta, t, TK):
    P0, Pinf, lnkref, Ea_kJ = theta
    return Pinf + (P0 - Pinf) * np.exp(-k_of_T(lnkref, Ea_kJ, TK) * t)


def ea_penalty(Ea_kJ):
    lo, hi, w = 20.0, 250.0, 1e3 * max(span ** 2, 1e-12)
    return w * (max(0.0, lo - Ea_kJ) ** 2 + max(0.0, Ea_kJ - hi) ** 2)


def objective(theta):
    return float(np.sum((P_fit - model_P(theta, t_fit, TK_fit)) ** 2) + ea_penalty(theta[3]))


P0_0 = P_fit.max() + 0.05 * span
Pinf_0 = P_fit.min() - 0.15 * span
best, best_sse = None, np.inf
for Ea0 in (40, 60, 80, 100, 120, 150):
    res = minimize(objective, [P0_0, Pinf_0, np.log(1e-3), Ea0],
                   method="Nelder-Mead",
                   options={"maxiter": 20000, "maxfev": 20000, "xatol": 1e-10, "fatol": 1e-12})
    sse = float(np.sum((P_fit - model_P(res.x, t_fit, TK_fit)) ** 2))
    if np.isfinite(sse) and sse < best_sse:
        best_sse, best = sse, res.x

P0, Pinf, lnkref, Ea_kJ = best
Phat = model_P(best, t_fit, TK_fit)
ss_res = np.sum((P_fit - Phat) ** 2)
ss_tot = np.sum((P_fit - P_fit.mean()) ** 2)
kinetic_R2 = 1 - ss_res / max(ss_tot, 1e-12)

P_fail = failureFraction * P0


def t_fail(Pf, Tc):
    k = k_of_T(lnkref, Ea_kJ, Tc + 273.15)
    ratio = (Pf - Pinf) / (P0 - Pinf)
    if ratio <= 0 or ratio >= 1 or k <= 0:
        return np.nan
    return -np.log(ratio) / k


tfail_kinetic = {T: t_fail(P_fail, T) for T in temperatures_C}
serviceLife_days = t_fail(P_fail, serviceTemp_C)
serviceLife_years = serviceLife_days / 365.25

# --- 4. cross-validated ML surrogate (toolbox-optional polyfallback analogue)--
X = np.column_stack([temp_all, days_all, rate_all])
y = eps_all
ml = make_pipeline(StandardScaler(), PolynomialFeatures(2), Ridge(alpha=1e-3))
cv = KFold(n_splits=5, shuffle=True, random_state=42)
yhat = cross_val_predict(ml, X, y, cv=cv)
ml_R2 = r2_score(y, yhat)
ml_RMSE = float(np.sqrt(mean_squared_error(y, yhat)))
ml.fit(X, y)

# --- Figure A: degradation curves --------------------------------------------
plt.figure(figsize=(7, 4.5))
colors = {50: "#1f6feb", 60: "#2da44e", 70: "#cf222e"}
for T in temperatures_C:
    dd = np.array(days_by_temp[T], dtype=float)
    mu = np.array([agg[(T, d)][0] for d in dd])
    sd = np.array([agg[(T, d)][1] for d in dd])
    plt.errorbar(dd, mu, yerr=sd, fmt="o", color=colors[T], capsize=3)
    tg = np.linspace(0, dd.max() * 1.1, 100)
    plt.plot(tg, model_P(best, tg, T + 273.15), "-", color=colors[T],
             linewidth=1.8, label=f"{T} \u00b0C")
plt.axhline(P_fail, color="k", linestyle="--", label="P_fail")
plt.xlabel("ageing time (days)")
plt.ylabel("eps_at_max (strain capacity)")
plt.title("Health property vs ageing time (reference strain rate)")
plt.grid(True, linestyle="--", alpha=0.5)
plt.legend()
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, "pipeline_degradation_curves.png"), dpi=160)
plt.close()

# --- Figure B: Arrhenius plot ------------------------------------------------
plt.figure(figsize=(7, 4.5))
TK = np.array([T + 273.15 for T in temperatures_C])
xinv = 1.0 / TK
ylog = np.log([tfail_kinetic[T] for T in temperatures_C])
plt.plot(xinv, ylog, "o", color="#1f6feb", markersize=8, label="t_fail per temperature")
Ts = serviceTemp_C + 273.15
slope = Ea_kJ * 1000.0 / R
intercept = np.log(serviceLife_days) - slope / Ts
xg = np.linspace(min(xinv.min(), 1 / Ts), max(xinv.max(), 1 / Ts), 50)
plt.plot(xg, intercept + slope * xg, "r-", label="Arrhenius fit")
plt.plot(1 / Ts, np.log(serviceLife_days), "rs", markersize=11,
         label=f"service life @ {serviceTemp_C:.0f} \u00b0C")
plt.xlabel("1/T  (1/K)")
plt.ylabel("ln(t_fail / days)")
plt.title(f"Arrhenius: Ea = {Ea_kJ:.1f} kJ/mol, "
          f"life = {serviceLife_days:.0f} d ({serviceLife_years:.1f} yr) @ {serviceTemp_C:.0f} \u00b0C")
plt.grid(True, linestyle="--", alpha=0.5)
plt.legend()
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, "pipeline_arrhenius.png"), dpi=160)
plt.close()

# --- Figure C: ML parity -----------------------------------------------------
plt.figure(figsize=(5.5, 5.5))
lim = [min(y.min(), yhat.min()), max(y.max(), yhat.max())]
plt.plot(y, yhat, "o", color="#6639ba", alpha=0.5, markersize=4)
plt.plot(lim, lim, "k--")
plt.xlim(lim)
plt.ylim(lim)
plt.xlabel("measured eps_at_max")
plt.ylabel("ML predicted eps_at_max")
plt.title(f"ML surrogate parity (5-fold CV-R\u00b2 = {ml_R2:.3f})")
plt.grid(True, linestyle="--", alpha=0.5)
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, "pipeline_ml_parity.png"), dpi=160)
plt.close()

# --- console + JSON ----------------------------------------------------------
out = {
    "n_files": int(n_files),
    "n_conditions": int(n_conditions),
    "P0": round(float(P0), 4),
    "Pinf": round(float(Pinf), 4),
    "P_fail": round(float(P_fail), 4),
    "Ea_kJmol": round(float(Ea_kJ), 2),
    "kinetic_R2": round(float(kinetic_R2), 4),
    "ml_R2": round(float(ml_R2), 4),
    "ml_RMSE": round(ml_RMSE, 5),
    "serviceTemp_C": serviceTemp_C,
    "serviceLife_days": round(float(serviceLife_days), 1),
    "serviceLife_years": round(float(serviceLife_years), 2),
    "tfail_kinetic_days": {int(T): round(float(tfail_kinetic[T]), 1) for T in temperatures_C},
}
print(json.dumps(out, indent=2))
with open(os.path.join(FIG_DIR, "pipeline_results.json"), "w") as fh:
    json.dump(out, fh, indent=2)
print("\nFigures written to", os.path.abspath(FIG_DIR))
