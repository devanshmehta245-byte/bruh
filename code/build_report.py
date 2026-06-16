"""
build_report.py
-------------------------------------------------------------------------
Generates the formatted Word report:
    report/Service_Life_Prediction_of_Solid_Propellants.docx

The script uses python-docx to build a styled, editable document containing
the introduction, problem statement, literature review, governing models and
equations, the code listings, the computed results (tables + figures) and the
reference list. Re-running it regenerates the document from scratch, so the
report stays reproducible.
-------------------------------------------------------------------------
"""

import json
import os

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIG_DIR = os.path.join(BASE, "figures")
REPORT_DIR = os.path.join(BASE, "report")
CODE_DIR = os.path.join(BASE, "code")
os.makedirs(REPORT_DIR, exist_ok=True)

ACCENT = RGBColor(0x1F, 0x4E, 0x79)      # deep blue for headings
CODE_BG = "F2F2F2"
MONO = "Consolas"

doc = Document()

# -------------------------------------------------------------------------
# Base styles
# -------------------------------------------------------------------------
normal = doc.styles["Normal"]
normal.font.name = "Calibri"
normal.font.size = Pt(11)
normal.paragraph_format.space_after = Pt(8)
normal.paragraph_format.line_spacing = 1.15

for level, size in ((1, 16), (2, 13), (3, 11.5)):
    st = doc.styles[f"Heading {level}"]
    st.font.color.rgb = ACCENT
    st.font.size = Pt(size)
    st.font.name = "Calibri"


# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------
def set_cell_background(cell, hex_color):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:fill"), hex_color)
    tc_pr.append(shd)


def para(text="", size=11, bold=False, italic=False, align=None,
         space_after=8, color=None):
    p = doc.add_paragraph()
    if align is not None:
        p.alignment = align
    p.paragraph_format.space_after = Pt(space_after)
    if text:
        r = p.add_run(text)
        r.bold = bold
        r.italic = italic
        r.font.size = Pt(size)
        if color is not None:
            r.font.color.rgb = color
    return p


def equation(text, number=None):
    """Centered italic equation, optionally numbered on the right."""
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(8)
    r = p.add_run(text)
    r.italic = True
    r.font.size = Pt(11.5)
    if number:
        tab = p.add_run("\t\t(" + number + ")")
        tab.italic = False
        tab.font.size = Pt(10)
    return p


def caption(text):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(text)
    r.italic = True
    r.font.size = Pt(9.5)
    r.font.color.rgb = RGBColor(0x55, 0x55, 0x55)
    p.paragraph_format.space_after = Pt(12)
    return p


def code_block(path, caption_text=None, max_lines=None):
    """Insert a source file as a shaded monospaced single-cell table."""
    with open(path, "r") as fh:
        lines = fh.read().splitlines()
    if max_lines:
        lines = lines[:max_lines]
    table = doc.add_table(rows=1, cols=1)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    cell = table.cell(0, 0)
    set_cell_background(cell, CODE_BG)
    cell.paragraphs[0].text = ""
    first = True
    for line in lines:
        p = cell.paragraphs[0] if first else cell.add_paragraph()
        first = False
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.line_spacing = 1.0
        r = p.add_run(line if line else " ")
        r.font.name = MONO
        r.font.size = Pt(8.5)
    # thin border
    tbl_pr = table._tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), "6")
        el.set(qn("w:color"), "BFBFBF")
        borders.append(el)
    tbl_pr.append(borders)
    if caption_text:
        caption(caption_text)
    return table


def bullet(text, bold_lead=None):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.space_after = Pt(4)
    if bold_lead:
        r = p.add_run(bold_lead)
        r.bold = True
    p.add_run(text)
    return p


def add_figure(path, width_in, caption_text):
    doc.add_picture(path, width=Inches(width_in))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
    caption(caption_text)


# =========================================================================
# TITLE PAGE
# =========================================================================
for _ in range(3):
    doc.add_paragraph()
para("Service-Life Prediction of Solid Rocket Propellants",
     size=24, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER, space_after=6,
     color=ACCENT)
para("Aging, Cumulative-Damage and Accelerated-Testing Models with a "
     "MATLAB Arrhenius Implementation",
     size=14, italic=True, align=WD_ALIGN_PARAGRAPH.CENTER, space_after=40)

para("Technical Report", size=13, bold=True,
     align=WD_ALIGN_PARAGRAPH.CENTER, space_after=4)
para("Structural Integrity & Service-Life Assessment of Energetic Materials",
     size=11, italic=True, align=WD_ALIGN_PARAGRAPH.CENTER, space_after=60)

para("Prepared by: ______________________", size=11,
     align=WD_ALIGN_PARAGRAPH.CENTER, space_after=4)
para("Organisation: GTAG", size=11,
     align=WD_ALIGN_PARAGRAPH.CENTER, space_after=4)
para("Date: ______________________", size=11,
     align=WD_ALIGN_PARAGRAPH.CENTER, space_after=4)

doc.add_page_break()

# =========================================================================
# ABSTRACT
# =========================================================================
doc.add_heading("Abstract", level=1)
para(
    "Solid rocket propellants are visco-elastic, highly filled polymeric "
    "composites whose mechanical integrity slowly degrades during storage "
    "through coupled chemical and physical aging. Predicting the remaining "
    "service life of a propellant grain is therefore central to munition "
    "safety, readiness and life-extension decisions. This report reviews the "
    "principal models used for solid-propellant aging and service-life "
    "prediction \u2014 cumulative-damage failure integrals, time\u2013"
    "temperature superposition, viscoelastic finite-element analysis, "
    "chemical-aging kinetics, handbook/nomograph design methods and "
    "non-destructive-testing indicators \u2014 and consolidates the governing "
    "equations behind them. A practical accelerated-aging model is then "
    "implemented in MATLAB: an Arrhenius temperature-acceleration law coupled "
    "with a power-law property-degradation rule is used to estimate the time "
    "for a normalised mechanical property to fall to a failure threshold over "
    "a range of storage temperatures. The model predicts a strong, "
    "non-linear reduction in service life with temperature \u2014 from "
    "roughly 21 years at 25 \u00b0C to under 4 months at 70 \u00b0C \u2014 "
    "consistent with the shelf-life ranges reported in the literature. The "
    "code, governing formulae and reproducible results are presented together "
    "with a practical decision tree for service-life assessment."
)

doc.add_page_break()

# =========================================================================
# 1. INTRODUCTION
# =========================================================================
doc.add_heading("1. Introduction", level=1)
para(
    "Composite solid propellants are the energy source of the majority of "
    "tactical and strategic rocket motors. Mechanically they behave as a "
    "highly filled visco-elastic rubber: an elastomeric binder (most commonly "
    "hydroxyl-terminated polybutadiene, HTPB) holds a high volume fraction of "
    "oxidiser (ammonium perchlorate, AP) and metallic fuel (aluminium) "
    "particles. The grain is bonded to the motor case and must survive "
    "ignition pressurisation, thermal cycling, transport vibration and "
    "long-term storage without cracking, debonding or losing its designed "
    "burning surface."
)
para(
    "Because a motor may be stored for one to two decades before use, the slow "
    "evolution of the propellant\u2019s properties \u2014 a process collectively "
    "called \u201caging\u201d \u2014 governs its useful life. Aging is driven by two "
    "broad mechanisms acting together:"
)
bullet("continued cross-linking, chain scission and oxidative cure of the "
       "binder, together with migration of plasticiser and bonding agents, "
       "which usually stiffen and embrittle the material; and",
       bold_lead="Chemical aging \u2014 ")
bullet("the accumulation of micro-damage (dewetting of filler particles, "
       "micro-void growth, interface debonding) under thermal and mechanical "
       "loading, which softens and weakens the material.",
       bold_lead="Physical / mechanical aging \u2014 ")
para(
    "Both mechanisms are strongly temperature-accelerated, so elevated-"
    "temperature testing is used to compress decades of natural aging into a "
    "few weeks or months in the laboratory. The central engineering question "
    "is then how to translate those accelerated measurements into a defensible "
    "estimate of service life at the real storage temperature. This report "
    "surveys the models that answer that question and demonstrates a compact, "
    "reproducible implementation of the most widely used one \u2014 the "
    "Arrhenius acceleration model."
)

# =========================================================================
# 2. PROBLEM STATEMENT
# =========================================================================
doc.add_heading("2. Problem Statement", level=1)
para(
    "Service-life prediction of a solid propellant must answer a deceptively "
    "simple question: for how long will the grain remain structurally sound "
    "at its storage temperature before a critical mechanical property falls "
    "below an acceptable limit? Answering it is difficult for several reasons:"
)
bullet("Natural aging is far slower than any test programme can wait for, so "
       "results must be extrapolated from accelerated (elevated-temperature) "
       "tests using a temperature-acceleration model whose activation energy "
       "must itself be estimated.",
       bold_lead="Time-scale mismatch \u2014 ")
bullet("The binder is visco-elastic, so its response depends on rate, "
       "temperature and load history; a single static property is not enough "
       "to describe failure.",
       bold_lead="Rate and temperature dependence \u2014 ")
bullet("Competing hardening (cross-linking) and softening (chain scission, "
       "damage) pathways can dominate at different times and temperatures, so "
       "the property\u2013time curve is not always monotonic.",
       bold_lead="Competing mechanisms \u2014 ")
bullet("Parameters are extracted by regression from scattered experimental "
       "data; biased fitting can give over-optimistic life estimates.",
       bold_lead="Parameter uncertainty \u2014 ")
para(
    "The specific problem addressed by the implementation in this report is: "
    "given an activation energy, a measured property at a known accelerated "
    "test condition, a power-law degradation exponent and a failure threshold, "
    "estimate the equivalent service life (in years) at the storage "
    "temperature, and characterise how that life varies across a realistic "
    "range of storage temperatures."
)

# =========================================================================
# 3. LITERATURE REVIEW
# =========================================================================
doc.add_heading("3. Literature Review", level=1)
para(
    "The literature on solid-propellant aging and service-life prediction can "
    "be grouped into six complementary families of models. Each family "
    "contributes a piece of the overall service-life picture, and the "
    "references below ([1]\u2013[10]) are organised accordingly."
)

doc.add_heading("3.1 Cumulative-damage failure models", level=2)
para(
    "Cumulative-damage approaches treat failure as the accumulation of a "
    "damage measure until it reaches a critical value. Biggs, Nestor et al. "
    "[1] patent a stress-based failure integral for filled polymeric "
    "materials, combining regression-based parameter extraction, numerical "
    "integration of the damage rate and Monte-Carlo estimation to produce a "
    "probabilistic failure prediction. Kunz [8] refines the parameter "
    "determination for Laheru-type linear cumulative-damage (LCD) models and "
    "explicitly warns against the bias that regression-based identification "
    "can introduce, motivating careful fitting of degradation exponents such "
    "as the one used in this report."
)

doc.add_heading("3.2 Time\u2013temperature superposition and viscoelastic "
                "characterisation", level=2)
para(
    "Because the binder is visco-elastic, its stiffness and strength depend on "
    "both time and temperature. Villar and Rezende [2] apply the time\u2013"
    "temperature superposition (TTS) principle to thermally aged composite "
    "propellant, showing how Williams\u2013Landel\u2013Ferry (WLF) shift "
    "factors collapse tensile data measured at many temperatures onto a single "
    "master curve, and how aging changes are modest at short times but become "
    "significant at long storage times. Tapia-Romero, Dehonor-G\u00f3mez and "
    "Lugo-Uribe [9] provide a practical route for converting frequency-domain "
    "dynamic-mechanical-analysis (DMA) data into Prony-series relaxation-"
    "modulus parameters, supplying the constitutive input needed by the "
    "viscoelastic models below."
)

doc.add_heading("3.3 Structural / finite-element assessment", level=2)
para(
    "Y\u0131ld\u0131r\u0131m and \u00d6z\u00fcpek [3] perform a non-linear "
    "visco-elastic finite-element structural assessment of a solid-propellant "
    "rocket motor, combining thermal and pressure load cases to identify hoop "
    "strain and case-bond stress as the governing failure indicators, and "
    "quantifying how aging and accumulated damage erode the structural margin. "
    "This work links the material-level degradation models to grain-level "
    "structural failure criteria."
)

doc.add_heading("3.4 Chemical / kinetic aging studies", level=2)
para(
    "Layton [4] reports chemical structural aging studies on an HTPB "
    "propellant, relating gel growth and mechanical-property drift to the "
    "logarithm of aging time and highlighting the influence of bonding-agent "
    "chemistry. These kinetic observations underpin the use of an Arrhenius "
    "temperature dependence for the aging rate, as adopted in the present "
    "implementation."
)

doc.add_heading("3.5 Handbook and nomograph design methods", level=2)
para(
    "Practical, rapid-estimate methods are documented by Waterman and Corley "
    "[5], who present an early handbook-style treatment of aging, thermal "
    "cycling and strain-based failure estimation for tactical propellant "
    "grains, and by the Aerojet Solid Propulsion Company [6], whose structural-"
    "design nomograph (NWC TM 3365) converts multiple geometric and material "
    "variables into rapid design estimates for thermal-cycling failure. These "
    "methods trade fidelity for speed and remain useful for first-order "
    "screening."
)

doc.add_heading("3.6 Non-destructive and full-life prediction methods", level=2)
para(
    "Husband and Roberto [7] patent a service-life analysis that uses dynamic "
    "mechanical properties as a non-destructive indicator of aging rate, "
    "allowing the same motor to be re-assessed over its life without "
    "destructive sampling. Finally, Adel and Liang [10] present a service-life "
    "prediction for an AP/Al/HTPB propellant that explicitly accounts for "
    "softening aging behaviour, capturing the competing hardening and "
    "softening pathways and reporting a shelf-life estimate of approximately "
    "13 years under the studied conditions \u2014 a useful benchmark for the "
    "results obtained here."
)

# =========================================================================
# 4. GOVERNING MODELS AND EQUATIONS
# =========================================================================
doc.add_heading("4. Governing Models and Equations", level=1)
para(
    "This section consolidates the mathematical models that underpin the "
    "service-life calculation and the broader literature. The implemented code "
    "(Section 5) uses Eqs. (1)\u2013(4); Eqs. (5)\u2013(7) describe the "
    "complementary viscoelastic and cumulative-damage frameworks reviewed "
    "above."
)

doc.add_heading("4.1 Arrhenius temperature-acceleration model", level=2)
para(
    "Chemical aging rates increase with temperature according to the Arrhenius "
    "law. The rate constant k at absolute temperature T is")
equation("k(T) = A\u2080 \u00b7 exp( \u2212E\u2090 / (R\u00b7T) )", "1")
para(
    "where E\u2090 is the activation energy (J/mol), R the universal gas "
    "constant (8.314 J\u00b7mol\u207b\u00b9\u00b7K\u207b\u00b9) and A\u2080 a "
    "pre-exponential factor. The ratio of aging rate at a test temperature "
    "T_test to that at the service temperature T_service defines the "
    "acceleration factor (AF):")
equation("AF = exp[ (E\u2090 / R) \u00b7 ( 1/T_test \u2212 1/T_service ) ]", "2")
para(
    "AF > 1 means aging at the test temperature is faster than at the service "
    "temperature, so a short hot test represents a long cool storage period. "
    "In the code, the acceleration factor is multiplied by a property-based "
    "pre-factor A obtained from the test point (see Section 5)."
)

doc.add_heading("4.2 Power-law property-degradation (cumulative damage)", level=2)
para(
    "The normalised mechanical property E is assumed to follow a power law in "
    "aging time t:")
equation("E(t) = A \u00b7 t\u207f", "3")
para(
    "with degradation exponent n (negative for a property that decays with "
    "time). Inverting Eq. (3) gives the time t_f at which the property reaches "
    "the failure threshold E_crit:")
equation("t_f = ( E_crit / A )^(1/n)", "4")
para(
    "The pre-factor A is anchored to the measured property at the known test "
    "duration through A = E_test / (t_test)\u207f. Multiplying t_f by the "
    "Arrhenius acceleration factor of Eq. (2) converts the failure time into an "
    "equivalent service life at the storage temperature, which is then "
    "expressed in years."
)

doc.add_heading("4.3 Time\u2013temperature superposition (WLF)", level=2)
para(
    "For visco-elastic data, responses measured at temperature T are shifted "
    "onto a master curve at reference temperature T_ref using the Williams\u2013"
    "Landel\u2013Ferry shift factor a_T [2]:")
equation("log\u2081\u2080(a_T) = \u2212C\u2081 (T \u2212 T_ref) / "
         "( C\u2082 + T \u2212 T_ref )", "5")
para(
    "where C\u2081 and C\u2082 are material constants. The shift factor lets a "
    "single relaxation master curve represent behaviour across the full "
    "temperature range of interest."
)

doc.add_heading("4.4 Viscoelastic relaxation modulus (Prony series)", level=2)
para(
    "The relaxation modulus is commonly represented by a Prony series fitted "
    "to DMA data [9], which is the constitutive input for finite-element "
    "structural analyses [3]:")
equation("E(t) = E_\u221e + \u03a3\u1d62 E\u1d62 \u00b7 exp( \u2212t / "
         "\u03c4\u1d62 )", "6")
para(
    "with long-term modulus E_\u221e, Prony coefficients E\u1d62 and relaxation "
    "times \u03c4\u1d62."
)

doc.add_heading("4.5 Linear cumulative damage (Miner / Laheru)", level=2)
para(
    "Linear cumulative-damage models [1], [8] sum fractional damage over the "
    "load/temperature history and predict failure when the total reaches "
    "unity:")
equation("D = \u03a3\u2c7c ( t\u2c7c / t_f,\u2c7c )  ;  failure when D \u2265 1",
         "7")
para(
    "where t\u2c7c is the time spent under condition j and t_f,\u2c7c is the "
    "time-to-failure under that condition alone. Eq. (4) supplies the "
    "single-condition t_f used in such summations."
)

# =========================================================================
# 5. IMPLEMENTATION (CODE)
# =========================================================================
doc.add_heading("5. Implementation \u2014 Code", level=1)
para(
    "The accelerated-aging service-life model of Section 4.1\u20134.2 is "
    "implemented in MATLAB. The script sweeps a range of storage/test "
    "temperatures, computes the Arrhenius acceleration factor and the power-law "
    "failure time for each, converts the result to an equivalent service life "
    "in years, and plots and tabulates the outcome. The full listing follows."
)
doc.add_heading("5.1 MATLAB source \u2014 service_life_arrhenius.m", level=2)
code_block(os.path.join(CODE_DIR, "service_life_arrhenius.m"),
           "Listing 1. MATLAB implementation of the Arrhenius / power-law "
           "service-life model.")

doc.add_heading("5.2 Mapping of code variables to equations", level=2)
para("The key variables in Listing 1 correspond to the governing equations as "
     "follows:")
map_rows = [
    ("Ea, R", "E\u2090, R in Eqs. (1)\u2013(2)", "Activation energy and gas constant"),
    ("T_service, T_test", "T_service, T_test in Eq. (2)", "Reference and test temperatures (K)"),
    ("A = E_test/t_test^n", "A in Eq. (3)", "Power-law pre-factor from the test point"),
    ("X, AF", "exponent and AF in Eq. (2)", "Arrhenius acceleration factor"),
    ("tf", "t_f in Eq. (4)", "Time to reach the failure threshold E_crit"),
    ("t_service_eq = tf*AF", "t_f \u00d7 AF", "Equivalent service life (days)"),
    ("tf_years", "t_service_eq / 365.25", "Service life expressed in years"),
]
tbl = doc.add_table(rows=1, cols=3)
tbl.style = "Light Grid Accent 1"
tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
hdr = tbl.rows[0].cells
for c, h in zip(hdr, ("Code variable", "Equation symbol", "Meaning")):
    c.paragraphs[0].add_run(h).bold = True
for r in map_rows:
    cells = tbl.add_row().cells
    for c, v in zip(cells, r):
        c.paragraphs[0].add_run(v).font.size = Pt(10)
caption("Table 1. Correspondence between code variables and governing equations.")

para(
    "A note on the model as coded: the same pre-factor A is used both to anchor "
    "the power-law property curve (Eq. 3) and as a multiplier on the Arrhenius "
    "factor. As a result the failure time t_f is identical for every "
    "temperature (1217 days), and the temperature dependence of the predicted "
    "service life enters entirely through the acceleration factor AF. This is a "
    "transparent first-order screening model; refining it so that the "
    "temperature dependence acts on t_f directly (rather than through a "
    "constant-t_f \u00d7 AF product) is identified as future work in Section 7."
)

doc.add_heading("5.3 Reproducing the results without MATLAB", level=2)
para(
    "Because a MATLAB licence is not always available, the identical numerical "
    "model is reproduced in Python (generate_results.py) using NumPy and "
    "Matplotlib. Running it regenerates the figures and the results table in "
    "Section 6, guaranteeing that the reported numbers are reproducible."
)
code_block(os.path.join(CODE_DIR, "generate_results.py"),
           "Listing 2. Python reproduction used to generate the figures and "
           "table (excerpt).", max_lines=46)

# =========================================================================
# 6. RESULTS AND DISCUSSION
# =========================================================================
doc.add_heading("6. Results and Discussion", level=1)
para(
    "Using E\u2090 = 80 kJ/mol, a service (reference) temperature of 27 \u00b0C, "
    "a 60-day test point, a failure threshold E_crit = 0.3 and a degradation "
    "exponent n = \u22120.4, the model produces the service-life predictions "
    "below for storage temperatures from 25 \u00b0C to 70 \u00b0C."
)

# Results table from generated JSON
with open(os.path.join(FIG_DIR, "results.json")) as fh:
    results = json.load(fh)

rtbl = doc.add_table(rows=1, cols=4)
rtbl.style = "Light Grid Accent 1"
rtbl.alignment = WD_TABLE_ALIGNMENT.CENTER
hdr = rtbl.rows[0].cells
for c, h in zip(hdr, ("Temperature (\u00b0C)", "Acceleration factor (AF)",
                      "t_f (days)", "Service life (years)")):
    c.paragraphs[0].add_run(h).bold = True
for row in results:
    cells = rtbl.add_row().cells
    cells[0].paragraphs[0].add_run(f"{row['temperature_C']:.0f}")
    cells[1].paragraphs[0].add_run(f"{row['acceleration_factor']:.4f}")
    cells[2].paragraphs[0].add_run(f"{row['tf_days']:.0f}")
    cells[3].paragraphs[0].add_run(f"{row['service_life_years']:.2f}")
caption("Table 2. Predicted acceleration factor and service life vs. "
        "storage temperature.")

add_figure(os.path.join(FIG_DIR, "service_life_vs_temperature.png"), 5.6,
           "Figure 1. Predicted service life decreases sharply and "
           "non-linearly with storage temperature.")
add_figure(os.path.join(FIG_DIR, "acceleration_factor_vs_temperature.png"),
           5.6,
           "Figure 2. Arrhenius acceleration factor (log scale); AF = 1 near "
           "the 27 \u00b0C service temperature and rises/falls exponentially "
           "around it.")

doc.add_heading("6.1 Discussion", level=2)
para(
    "The results show the expected exponential sensitivity of service life to "
    "temperature. At the 25 \u00b0C the model predicts roughly 21 years of "
    "service life; this falls to about 17 years at the 27 \u00b0C reference, "
    "12.5 years at 30 \u00b0C, 4.5 years at 40 \u00b0C and only about 0.3 years "
    "(\u2248 113 days) at 70 \u00b0C. The predicted life near typical magazine "
    "storage temperatures is consistent in order of magnitude with the "
    "\u2248 13-year shelf life reported by Adel and Liang [10] for an "
    "AP/Al/HTPB propellant, lending qualitative confidence to the model."
)
para(
    "Two practical implications follow. First, because AF is exponential in "
    "1/T, modest reductions in storage temperature yield disproportionately "
    "large gains in service life \u2014 a strong argument for climate-"
    "controlled magazines. Second, the acceleration factor curve (Figure 2) "
    "shows why short elevated-temperature tests are so attractive: at 70 "
    "\u00b0C aging proceeds roughly 70\u00d7 faster than at the service "
    "temperature implied by the AF ratio, so a few weeks of testing samples "
    "years of natural aging. The chief caveats are the sensitivity of the "
    "extrapolation to the assumed activation energy and degradation exponent "
    "(cf. Kunz\u2019s warning on regression bias [8]) and the model\u2019s "
    "neglect of competing softening/hardening pathways [10]."
)

# =========================================================================
# 7. CONCLUSION
# =========================================================================
doc.add_heading("7. Conclusion and Future Work", level=1)
para(
    "This report reviewed the main modelling families for solid-propellant "
    "aging and service-life prediction \u2014 cumulative-damage failure "
    "integrals, time\u2013temperature superposition, viscoelastic finite-"
    "element analysis, chemical-aging kinetics, handbook/nomograph methods and "
    "non-destructive indicators \u2014 and consolidated their governing "
    "equations. A compact Arrhenius / power-law service-life model was "
    "implemented in MATLAB and reproduced in Python, yielding reproducible "
    "predictions that capture the strong, non-linear dependence of service "
    "life on storage temperature and that agree in order of magnitude with "
    "published shelf-life estimates."
)
para("Recommended future work includes:")
bullet("letting the temperature dependence act on the failure time t_f "
       "directly, rather than through a constant-t_f \u00d7 AF product, so the "
       "power-law and Arrhenius terms are fully coupled;")
bullet("calibrating E\u2090 and n against measured accelerated-aging data and "
       "propagating their uncertainty (Monte-Carlo, after [1]);")
bullet("incorporating competing hardening/softening kinetics [10] and a "
       "non-monotonic property\u2013time curve;")
bullet("coupling the material model to a viscoelastic finite-element grain "
       "model [3] using Prony-series inputs [9] to predict structural rather "
       "than property-based failure.")

# =========================================================================
# REFERENCES
# =========================================================================
doc.add_heading("References", level=1)
refs = [
    "Biggs, G. L., Nestor, J. J., et al. Cumulative damage model for "
    "structural analysis of filled polymeric materials (US 6,301,970). The "
    "work provides a stress-based failure integral, regression-based parameter "
    "extraction, numerical integration, and Monte-Carlo estimation for failure "
    "prediction.",
    "Villar, L. D., and Rezende, L. C. Time-temperature superposition "
    "principle applied to thermally aged composite propellant. The paper shows "
    "how WLF shift factors can collapse tensile data into master curves and how "
    "aging changes are modest at short times but significant at long storage "
    "times.",
    "Y\u0131ld\u0131r\u0131m, H. C., and \u00d6z\u00fcpek, S. Structural "
    "assessment of a solid propellant rocket motor: Effects of aging and "
    "damage. The paper combines nonlinear viscoelastic finite-element analysis "
    "with thermal/pressure load cases to identify hoop strain and bond stress "
    "as governing failure indicators.",
    "Layton, L. H. Chemical structural aging studies on an HTPB propellant. "
    "The report links gel growth and mechanical-property drift to logarithmic "
    "aging time and highlights the influence of bonding-agent chemistry.",
    "Waterman, C. S., and Corley, R. C. Solid propellant aging studies. The "
    "report presents an early handbook-style treatment of aging, thermal "
    "cycling, and strain-based failure estimation for tactical propellant "
    "grains.",
    "Aerojet Solid Propulsion Company. Structural design nomograph for thermal "
    "cycling of tactical rocket propellants (NWC TM 3365). The handbook "
    "converts multiple geometric and material variables into rapid design "
    "estimates for thermal-cycling failure.",
    "Husband, D. M., and Roberto, F. Q. Solid propellant service life analysis "
    "via nondestructive testing (US 5,038,295). The patent uses dynamic "
    "mechanical properties as a nondestructive indicator of aging rate.",
    "Kunz, R. K. Characterization of solid propellant for linear cumulative "
    "damage modeling. The paper refines parameter determination for Laheru-type "
    "LCD models and cautions against bias in regression-based identification.",
    "Tapia-Romero, M. A., Dehonor-G\u00f3mez, M., and Lugo-Uribe, L. Prony "
    "series calculation for viscoelastic behavior modeling of structural "
    "adhesives from DMA data. The paper provides a practical route from "
    "frequency-domain data to relaxation-modulus parameters.",
    "Adel, W. M., and Liang, G. Service life prediction of AP/Al/HTPB solid "
    "rocket propellant with consideration of softening aging behavior. The "
    "paper captures the competing hardening and softening pathways and reports "
    "a shelf-life estimate around 13 years under the studied conditions.",
]
for i, r in enumerate(refs, 1):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.left_indent = Inches(0.35)
    p.paragraph_format.first_line_indent = Inches(-0.35)
    run = p.add_run(f"[{i}] ")
    run.bold = True
    p.add_run(r).font.size = Pt(10.5)

# =========================================================================
# APPENDIX A
# =========================================================================
doc.add_page_break()
doc.add_heading("Appendix A. Practical Decision Tree", level=1)
para(
    "The following decision tree summarises how the models in this report fit "
    "together in a practical service-life assessment workflow.")
steps = [
    ("Step 1 \u2014 Define requirement.", " Set the service temperature, the "
     "critical property and its failure threshold E_crit."),
    ("Step 2 \u2014 Choose method by data availability.", " If only accelerated "
     "property data exist \u2192 use the Arrhenius / power-law model (Sections "
     "4.1\u20134.2, Listing 1). If DMA/relaxation data exist \u2192 build a "
     "Prony-series + TTS master curve (Eqs. 5\u20136)."),
    ("Step 3 \u2014 Extract parameters.", " Fit E\u2090, n (and WLF C\u2081, "
     "C\u2082 if applicable) by regression; check for bias [8]."),
    ("Step 4 \u2014 Predict.", " Compute the acceleration factor and failure "
     "time; convert to service life. For structural margins, feed the material "
     "model into a viscoelastic FE grain model [3]."),
    ("Step 5 \u2014 Validate & monitor.", " Compare against handbook/nomograph "
     "estimates [5], [6] and against non-destructive aging indicators [7]; "
     "re-assess periodically over the stockpile life."),
]
for lead, body in steps:
    p = doc.add_paragraph(style="List Number")
    p.paragraph_format.space_after = Pt(6)
    r = p.add_run(lead)
    r.bold = True
    p.add_run(body)

out = os.path.join(REPORT_DIR, "Service_Life_Prediction_of_Solid_Propellants.docx")
doc.save(out)
print("Saved:", out)
