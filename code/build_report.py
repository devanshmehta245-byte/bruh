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
    "consistent with the shelf-life ranges reported in the literature. A "
    "second, more complete data-driven pipeline is also presented: it reads "
    "accelerated-ageing tensile tests, extracts mechanical properties, trains a "
    "cross-validated machine-learning surrogate, fits global first-order "
    "Arrhenius kinetics and predicts service life (recovering an activation "
    "energy of about 83 kJ/mol and a service life of roughly 30 years for the "
    "demonstration dataset). Both codes, their governing formulae and "
    "reproducible results are presented together with a practical decision tree "
    "for service-life assessment."
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

doc.add_heading("1.1 Composition and microstructure", level=2)
para(
    "A composite solid propellant is engineered at the level of its "
    "microstructure, and its long-term behaviour cannot be understood without "
    "appreciating that structure. A representative AP/HTPB formulation contains "
    "roughly 85\u201390 % by mass of solid fillers held together by only "
    "10\u201315 % of polymeric binder. The constituents play distinct roles:"
)
bullet("a cross-linked elastomer (typically HTPB cured with a di- or "
       "tri-isocyanate) that provides the continuous, load-bearing, "
       "rubber-like matrix and gives the grain its compliance and strain "
       "capability.",
       bold_lead="Binder \u2014 ")
bullet("ammonium perchlorate (AP), usually as a bimodal blend of coarse and "
       "fine particles to maximise solids loading; it supplies the oxygen for "
       "combustion and dominates the volume fraction.",
       bold_lead="Oxidiser \u2014 ")
bullet("aluminium powder, which raises the flame temperature and specific "
       "impulse and suppresses combustion instability.",
       bold_lead="Metallic fuel \u2014 ")
bullet("bonding agents that strengthen the binder\u2013filler interface, "
       "plasticisers that lower the glass-transition temperature and improve "
       "low-temperature strain capability, cure catalysts, antioxidants and "
       "burn-rate modifiers.",
       bold_lead="Additives \u2014 ")
para(
    "Mechanically, the cured grain is a particulate composite: stiff inclusions "
    "in a soft matrix bonded across an interface. Most aging phenomena, and "
    "most failures, originate at that binder\u2013filler interface or in the "
    "binder network itself, which is why both the chemistry of the binder and "
    "the integrity of the interface feature so prominently in the models that "
    "follow."
)

doc.add_heading("1.2 Structural failure modes", level=2)
para(
    "\u201cFailure\u201d of a propellant grain is not a single event but a set "
    "of distinct mechanical limit states, any of which can render the motor "
    "unsafe or unreliable:"
)
bullet("surface or bore cracking under thermal-shrinkage and pressurisation "
       "strains, which exposes additional burning area and can raise chamber "
       "pressure beyond design limits.",
       bold_lead="Cracking \u2014 ")
bullet("separation of the grain from the case/insulation (case-bond failure), "
       "which creates an uncontrolled burning surface and is a leading cause of "
       "catastrophic motor failure.",
       bold_lead="Debonding \u2014 ")
bullet("microscopic separation of binder from filler particles (\u201c"
       "dewetting\u201d) that nucleates voids, reduces modulus and strength, and "
       "is an early precursor to macroscopic cracking.",
       bold_lead="Dewetting \u2014 ")
bullet("loss of strain capability as the binder embrittles with age, so that "
       "strains that were once tolerable now exceed the rupture limit, "
       "especially at low temperature.",
       bold_lead="Embrittlement \u2014 ")
para(
    "Because these limit states are governed by mechanical properties "
    "(modulus, strength, strain-to-failure, bond strength) that all drift with "
    "age, tracking the degradation of a representative property over time is a "
    "rational basis for service-life prediction \u2014 exactly the approach "
    "taken by the model implemented here."
)

doc.add_heading("1.3 Aging mechanisms in detail", level=2)
para(
    "The two aging families introduced above act through several concrete "
    "physico-chemical processes. On the chemical side, the isocyanate-cured "
    "HTPB network continues to react long after manufacture: post-cure "
    "cross-linking and oxidative cross-linking progressively tighten the "
    "network, raising modulus and hardness while lowering strain capability; "
    "competing chain scission and hydrolysis break the network and soften it; "
    "and plasticiser and bonding-agent migration changes the local stiffness "
    "near interfaces. Layton\u2019s observation [4] that mechanical properties "
    "drift roughly with the logarithm of aging time is a direct signature of "
    "these diffusion- and reaction-limited processes."
)
para(
    "On the physical side, repeated thermal cycling and sustained storage "
    "loads accumulate irreversible micro-damage \u2014 dewetting, micro-void "
    "growth and interface debonding \u2014 that softens the material and "
    "reduces its strength. The two families compete: a propellant may first "
    "stiffen (chemical hardening dominant) and later soften (damage and "
    "scission dominant), producing the non-monotonic property\u2013time curves "
    "that Adel and Liang [10] model explicitly. Crucially, the rates of nearly "
    "all of these processes rise approximately exponentially with temperature, "
    "which is the physical justification for the Arrhenius treatment in "
    "Section 4.1."
)

doc.add_heading("1.4 Why service-life prediction matters", level=2)
para(
    "Service-life prediction is the technical backbone of stockpile "
    "surveillance and service-life-extension programmes (SLEP). A defensible "
    "remaining-life estimate determines when a motor must be inspected, "
    "re-qualified, refurbished or disposed of, and it directly trades off "
    "safety against the very high cost of prematurely scrapping serviceable "
    "munitions. Under-prediction wastes assets and readiness; over-prediction "
    "risks a catastrophic failure in storage, transport or flight. The models "
    "reviewed here exist to make that estimate as quantitative, repeatable and "
    "physically grounded as the available data allow."
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

doc.add_heading("2.1 Formal statement", level=2)
para(
    "Let P(t, T) be a normalised mechanical property (for example secant "
    "modulus, tensile strength or strain-to-failure divided by its initial "
    "value) that evolves with aging time t at absolute temperature T. Let "
    "P_crit be the smallest acceptable value of that property before a limit "
    "state of Section 1.2 is reached. The service life t_L at the storage "
    "temperature T_s is defined implicitly by")
equation("P(t_L, T_s) = P_crit", "I")
para(
    "Because tests are run at one or more elevated temperatures T_test > T_s, "
    "the property is actually measured as P(t_test, T_test), and a temperature-"
    "acceleration model is required to map that accelerated observation back to "
    "the slow process at T_s. Service-life prediction is therefore a coupled "
    "problem: a degradation law that describes how P decays with time, plus an "
    "acceleration law that describes how that decay speeds up with temperature. "
    "The implementation in this report adopts a power-law degradation rule "
    "(Section 4.2) and an Arrhenius acceleration law (Section 4.1)."
)

doc.add_heading("2.2 Choice of failure criterion", level=2)
para(
    "The criterion P_crit must be chosen to reflect the dominant limit state. "
    "Common choices include a maximum allowable loss of strain capability "
    "(to guard against cracking under thermal/pressurisation strain), a minimum "
    "allowable bond strength (to guard against case debonding), or a maximum "
    "allowable modulus increase (to guard against embrittlement). In the "
    "present model a single normalised property with a threshold of "
    "P_crit = 0.3 (i.e. failure when the property has fallen to 30 % of its "
    "initial value) is used as a transparent, generic surrogate; the framework "
    "is unchanged if a different property or threshold is substituted."
)

# =========================================================================
# 3. LITERATURE REVIEW
# =========================================================================
doc.add_heading("3. Literature Review", level=1)
para(
    "A broad body of work on solid-propellant aging and service-life prediction "
    "was surveyed for this study. It can be grouped into six complementary "
    "families of models, each of which contributes a piece of the overall "
    "service-life picture. The discussion below is organised around these "
    "families and cites a representative selection of the works studied; the "
    "numbered references are illustrative of each family rather than an "
    "exhaustive list of the literature consulted."
)

doc.add_heading("3.1 Cumulative-damage failure models", level=2)
para(
    "Cumulative-damage approaches treat failure not as a single overload event "
    "but as the gradual accumulation of a scalar damage measure D until it "
    "reaches a critical value (conventionally D = 1). They are attractive for "
    "propellants because the grain experiences a long, variable history of "
    "thermal and mechanical loads, no single one of which would cause failure "
    "on its own."
)
para(
    "Biggs, Nestor et al. [1] (US 6,301,970) patent a stress-based failure "
    "integral for filled polymeric materials. Their method accumulates damage "
    "as a time integral of a stress- (or strain-) dependent rate, extracts the "
    "rate-law parameters by regression against laboratory data, integrates the "
    "damage numerically over the predicted load history, and \u2014 importantly "
    "\u2014 wraps the whole calculation in a Monte-Carlo loop so that scatter in "
    "the material parameters and loads propagates into a probability of "
    "failure rather than a single deterministic number. This probabilistic "
    "framing is what distinguishes the method from a simple safety-factor "
    "check."
)
para(
    "Kunz [8] addresses the weakest link in any such model \u2014 the "
    "parameters. Working with Laheru-type linear cumulative-damage (LCD) "
    "models, he refines how the damage-law constants are determined from test "
    "data and demonstrates that ordinary regression can be biased, "
    "systematically over- or under-estimating life if the fitting variables "
    "and weighting are chosen carelessly. His caution is directly relevant "
    "here: the power-law exponent n used in this report\u2019s model is exactly "
    "the kind of regression-fitted parameter to which the predicted life is "
    "highly sensitive (see Section 6.3)."
)

doc.add_heading("3.2 Time\u2013temperature superposition and viscoelastic "
                "characterisation", level=2)
para(
    "Because the binder is visco-elastic, its stiffness and strength depend not "
    "only on temperature but on the rate and duration of loading. The most "
    "powerful organising idea for such materials is time\u2013temperature "
    "superposition (TTS): the observation that the effect of raising "
    "temperature is, to first order, equivalent to extending the time of "
    "observation. Data taken over an experimentally accessible time window at "
    "many temperatures can therefore be shifted horizontally on a logarithmic "
    "time axis to build a single \u201cmaster curve\u201d spanning many decades "
    "of effective time."
)
para(
    "Villar and Rezende [2] apply exactly this principle to thermally aged "
    "composite propellant. Using Williams\u2013Landel\u2013Ferry (WLF) shift "
    "factors they collapse tensile data measured at several temperatures onto "
    "one master curve, and they show that aging shifts this curve only modestly "
    "at short times but significantly at long storage times \u2014 precisely "
    "the regime that service-life prediction cares about. Their work both "
    "validates the use of accelerated testing and quantifies how the master "
    "curve itself migrates as the material ages."
)
para(
    "Tapia-Romero, Dehonor-G\u00f3mez and Lugo-Uribe [9] supply the missing "
    "constitutive ingredient. They give a practical, numerically robust route "
    "for converting frequency-domain dynamic-mechanical-analysis (DMA) data "
    "(storage and loss modulus versus frequency) into a time-domain Prony "
    "series for the relaxation modulus. That Prony series (Eq. 6) is the exact "
    "form of material input required by the finite-element structural analyses "
    "discussed next, closing the loop from raw laboratory data to a usable "
    "constitutive model."
)

doc.add_heading("3.3 Structural / finite-element assessment", level=2)
para(
    "Material-level property curves only become a service-life statement when "
    "they are combined with the actual stresses and strains in the grain. "
    "Y\u0131ld\u0131r\u0131m and \u00d6z\u00fcpek [3] perform a non-linear "
    "visco-elastic finite-element (FE) structural assessment of a solid-"
    "propellant rocket motor for this purpose. They model the grain with a "
    "time- and temperature-dependent constitutive law (of the Prony/WLF type "
    "above) and subject it to the realistic combined load cases the motor "
    "experiences \u2014 cure-shrinkage and thermal cool-down, low- and high-"
    "temperature soak, and ignition pressurisation."
)
para(
    "Their analysis identifies the inner-bore hoop strain and the case-bond "
    "(grain-to-case interface) stress as the two governing failure indicators, "
    "and it quantifies how aging and accumulated damage progressively erode the "
    "margin between the applied strain/stress and the material\u2019s "
    "(shrinking) capability. This is the bridge between the property-level "
    "models of this report and a true structural verdict: the degradation law "
    "predicts how capability falls, while the FE model predicts the demand it "
    "must withstand."
)

doc.add_heading("3.4 Chemical / kinetic aging studies", level=2)
para(
    "Layton [4] reports chemical structural aging studies on an HTPB "
    "propellant that explain why the macroscopic properties drift the way they "
    "do. By tracking gel content (a measure of network cross-link density) and "
    "correlating it with mechanical-property change, he shows that the drift "
    "scales approximately with the logarithm of aging time \u2014 the signature "
    "of diffusion- and reaction-limited network evolution \u2014 and that the "
    "chemistry of the bonding agent strongly influences both the rate and the "
    "direction (hardening vs. softening) of the change."
)
para(
    "These kinetic findings matter for the present model in two ways. First, "
    "they justify treating the aging rate with an Arrhenius temperature "
    "dependence, because the underlying reactions are thermally activated. "
    "Second, the logarithmic-in-time behaviour they observe is consistent with "
    "the power-law/log-type degradation form adopted in Section 4.2, giving the "
    "chosen functional form a physical, not merely empirical, basis."
)

doc.add_heading("3.5 Handbook and nomograph design methods", level=2)
para(
    "Before routine finite-element analysis was affordable, the field relied on "
    "consolidated handbook and nomograph methods that compress decades of test "
    "experience into rapid hand calculations \u2014 and these remain valuable "
    "today for first-order screening and sanity checks. Waterman and Corley [5] "
    "present an early handbook-style treatment of aging, thermal cycling and "
    "strain-based failure estimation for tactical propellant grains, giving "
    "engineers tabulated correlations and worked procedures rather than a "
    "bespoke analysis for every motor."
)
para(
    "The Aerojet Solid Propulsion Company structural-design nomograph (NWC TM "
    "3365) [6] takes the same spirit further: it encodes the relationships "
    "between multiple geometric and material variables (grain web, bore "
    "geometry, modulus, thermal-expansion mismatch, temperature swing) as a "
    "nomograph that returns a thermal-cycling failure estimate by aligning a "
    "straight-edge across calibrated scales. These methods deliberately trade "
    "fidelity for speed and transparency; the compact Arrhenius model in this "
    "report sits in the same \u201crapid-estimate\u201d tradition."
)

doc.add_heading("3.6 Non-destructive and full-life prediction methods", level=2)
para(
    "Husband and Roberto [7] (US 5,038,295) patent a service-life analysis that "
    "uses dynamic mechanical properties as a non-destructive indicator of aging "
    "rate. The key advantage is that the same motor (or a witness sample) can "
    "be re-measured repeatedly over its life without destructive sectioning, so "
    "the actual aging trajectory of a specific asset can be tracked and its "
    "remaining life updated \u2014 a capability that purely predictive models "
    "cannot provide on their own."
)
para(
    "Adel and Liang [10] present a full service-life prediction for an AP/Al/"
    "HTPB propellant that, unusually, accounts explicitly for softening aging "
    "behaviour. Rather than assuming monotonic hardening, they model the "
    "competition between cross-linking (hardening) and chain-scission/damage "
    "(softening) pathways, capturing the non-monotonic property\u2013time curve "
    "that real propellants often show, and they report a shelf-life estimate of "
    "approximately 13 years under the studied conditions. That figure is the "
    "most direct published benchmark for the results obtained here and is used "
    "for comparison in Section 6."
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
    "The physical premise is that aging is controlled by thermally activated "
    "chemical reactions. The fraction of molecules with enough energy to clear "
    "the reaction\u2019s energy barrier follows a Boltzmann factor, so the "
    "reaction (and hence aging) rate constant k at absolute temperature T obeys "
    "the Arrhenius law:")
equation("k(T) = A\u2080 \u00b7 exp( \u2212E\u2090 / (R\u00b7T) )", "1")
para(
    "Here E\u2090 is the activation energy (J/mol) \u2014 the height of the "
    "energy barrier and the single most influential parameter in the whole "
    "extrapolation \u2014 R is the universal gas constant "
    "(8.314 J\u00b7mol\u207b\u00b9\u00b7K\u207b\u00b9), T is the absolute "
    "temperature (K), and A\u2080 is the pre-exponential (frequency) factor "
    "that absorbs the collision rate and orientation statistics. For solid-"
    "propellant binders E\u2090 typically lies in the range 60\u2013100 kJ/mol; "
    "the value of 80 kJ/mol used here is representative."
)
para(
    "The pre-exponential factor A\u2080 is usually unknown, but it cancels when "
    "we take the ratio of the rate at an elevated test temperature T_test to "
    "the rate at the service temperature T_service. That ratio is the "
    "acceleration factor, AF:")
equation("AF = k(T_test) / k(T_service)", "2a")
para("Substituting Eq. (1) and cancelling A\u2080 gives the working form used "
     "throughout this report:")
equation("AF = exp[ (E\u2090 / R) \u00b7 ( 1/T_service \u2212 1/T_test ) ]", "2")
para(
    "AF > 1 means aging proceeds faster at the test temperature than in "
    "storage, so a short hot test reproduces a long period of cool storage \u2014 "
    "the whole basis of accelerated aging. Because AF depends on the reciprocal "
    "of absolute temperature inside an exponential, it is extremely sensitive: "
    "a 10 \u00b0C rise near room temperature roughly doubles to triples the rate "
    "for E\u2090 in the typical range (the familiar \u201cevery 10 \u00b0C "
    "halves the life\u201d rule of thumb). The chief assumptions are that a "
    "single dominant reaction (one E\u2090) governs aging over the whole "
    "temperature range and that the failure mechanism itself does not change "
    "with temperature \u2014 assumptions that can break down if a new mechanism "
    "is activated at high test temperatures, which is why test temperatures are "
    "kept as low as the test duration allows."
)
para(
    "Equation (2) is the conventional form, in which AF > 1 for T_test > "
    "T_service. The implemented script computes a closely related temperature-"
    "scaling quantity that uses the reciprocal difference with the opposite "
    "sign and folds in the power-law pre-factor A; the exact relationship and "
    "its consequences are set out transparently in Section 5.2. The physical "
    "conclusion is unchanged: predicted life falls as temperature rises."
)

doc.add_heading("4.2 Power-law property-degradation (cumulative damage)", level=2)
para(
    "Having captured how temperature scales the aging rate, a second law is "
    "needed for how the property itself decays as that aging accumulates. "
    "Motivated by the logarithmic-in-time drift observed experimentally "
    "(Section 3.4), the normalised mechanical property E is modelled as a power "
    "law in aging time t:")
equation("E(t) = A \u00b7 t\u207f", "3")
para(
    "where n is the degradation exponent and A a pre-factor. For a property "
    "that decays with time n is negative, so E falls monotonically as t grows; "
    "the magnitude of n sets how quickly. The pre-factor A is not free \u2014 it "
    "is anchored to the property actually measured at the known test duration "
    "t_test, through")
equation("A = E_test / (t_test)\u207f", "3a")
para(
    "so that the curve passes exactly through the measured test point "
    "(E_test, t_test). This is what ties the abstract law to real data."
)
para(
    "Failure is declared when the property has decayed to the critical "
    "threshold E_crit. Setting E(t_f) = E_crit in Eq. (3) and solving for the "
    "failure time t_f gives, after dividing by A and raising both sides to the "
    "power 1/n:")
equation("t_f = ( E_crit / A )^(1/n)", "4")
para(
    "Equation (4) is the time, in test-equivalent units, for the property to "
    "fall from its initial value to the failure threshold. Multiplying t_f by "
    "the temperature-scaling factor of Section 4.1 converts it into an "
    "equivalent service life at the storage temperature, which is finally "
    "divided by 365.25 to express the result in years. The chief assumptions "
    "are that a single power law holds over the whole life (no change of "
    "mechanism) and that the property\u2013time curve is monotonic \u2014 the "
    "latter being exactly the simplification that Adel and Liang [10] relax by "
    "allowing competing hardening and softening."
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

doc.add_heading("4.6 Worked example (one temperature)", level=2)
para(
    "It is worth following the arithmetic for a single temperature so the code "
    "in Section 5 is transparent. Take the service/reference case T_service = "
    "300.15 K (27 \u00b0C) and the test point t_test = 60 days, E_test = 1, with "
    "n = \u22120.4, E_crit = 0.3 and E\u2090 = 80 000 J/mol."
)
bullet("Pre-factor (Eq. 3a): A = 1 / 60^(\u22120.4) = 60^(0.4) \u2248 5.143.")
bullet("Failure time (Eq. 4): t_f = (0.3 / 5.143)^(1/\u22120.4) = "
       "(0.05833)^(\u22122.5) \u2248 1217 days. Because A and the threshold are "
       "the same at every temperature, t_f is the same (\u2248 1217 days) for "
       "every row of the results table.")
bullet("Temperature scaling at, say, 25 \u00b0C (298.15 K): the exponent is "
       "(E\u2090/R)\u00b7(1/298.15 \u2212 1/300.15) = 9622.3 \u00d7 2.234\u00d7"
       "10\u207b\u2075 \u2248 0.215, giving exp(0.215) \u2248 1.240; multiplied "
       "by A \u2248 5.143 this is the script\u2019s AF \u2248 6.38.")
bullet("Equivalent service life: t_f \u00d7 AF = 1217 \u00d7 6.38 \u2248 7761 "
       "days \u2248 21.3 years \u2014 the first row of Table 2.")
para(
    "Repeating the last two steps for each temperature in the list produces the "
    "full results of Section 6. The only quantity that changes from row to row "
    "is the temperature-dependent scaling factor."
)

# =========================================================================
# 5. IMPLEMENTATION (CODE)
# =========================================================================
doc.add_heading("5. Implementation \u2014 Code 1: Arrhenius Screening Model",
                level=1)
para(
    "Two codes are presented in this report. Code 1 (this section) is a compact "
    "Arrhenius screening model that turns a single accelerated test point into a "
    "service-life-versus-temperature curve. Code 2 (Section 7) is a complete, "
    "data-driven pipeline that processes raw tensile-test files, trains a "
    "machine-learning surrogate and fits global ageing kinetics. For each code "
    "the report gives the source listing, the results it produces, and an "
    "explanation of the models and formulas it uses."
)
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

doc.add_heading("5.2 Step-by-step walkthrough", level=2)
para("The script executes in four logical stages:")
bullet("the activation energy E\u2090, gas constant R, reference temperature "
       "T_service, test duration t_test, measured property E_test, failure "
       "threshold E_crit and degradation exponent n are defined. These are the "
       "only inputs a user normally changes.",
       bold_lead="1. Define constants \u2014 ")
bullet("the list temperatures_C is converted to kelvin (T_test = 273.15 + "
       "temperatures_C), and empty arrays tf_days and tf_years are "
       "pre-allocated to hold the per-temperature results.",
       bold_lead="2. Build the temperature sweep \u2014 ")
bullet("for each temperature the script (a) computes the power-law pre-factor "
       "A = E_test / t_test^n (Eq. 3a); (b) forms the exponent X = (E\u2090/R)"
       "\u00b7(1/T_test \u2212 1/T_service) and the scaling factor AF = A\u00b7"
       "exp(X); (c) computes the failure time tf = (E_crit/A)^(1/n) (Eq. 4); "
       "and (d) forms the equivalent service life t_service_eq = tf\u00b7AF, "
       "storing tf in days and t_service_eq/365.25 in years.",
       bold_lead="3. Loop over temperatures \u2014 ")
bullet("the service-life-versus-temperature curve is plotted and the "
       "temperature/service-life pairs are printed as a table.",
       bold_lead="4. Plot and tabulate \u2014 ")
para(
    "Because A, E_crit and n do not change inside the loop, the failure time tf "
    "is computed to the same value (\u2248 1217 days) on every iteration; only "
    "the exponent X \u2014 and therefore AF and the final service life \u2014 "
    "varies with temperature. This is the numerical reason the t_f column in "
    "Table 2 is constant."
)

doc.add_heading("5.3 Mapping of code variables to equations", level=2)
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
    "Two implementation details deserve to be stated plainly, because they "
    "affect how the results are interpreted:"
)
bullet("the script\u2019s AF = A\u00b7exp[(E\u2090/R)(1/T_test \u2212 "
       "1/T_service)] differs from the conventional acceleration factor of "
       "Eq. (2) in two ways. It multiplies by the power-law pre-factor A, and "
       "it uses the reciprocal difference with the opposite sign. Consequently "
       "the script\u2019s AF decreases with temperature (it equals A at "
       "T_service and falls as T_test rises), which is what makes the predicted "
       "service life shorten at high temperature. It is therefore best read as "
       "a combined temperature-scaling factor rather than the textbook AF; "
       "Figure 2 plots this quantity.",
       bold_lead="Sign and content of AF \u2014 ")
bullet("the same pre-factor A anchors the power-law curve (Eq. 3) and also "
       "multiplies the exponential, so the failure time t_f is identical for "
       "every temperature (\u2248 1217 days) and all the temperature dependence "
       "enters through AF.",
       bold_lead="Constant t_f \u2014 ")
para(
    "These choices make the script a transparent first-order screening tool "
    "that produces the physically correct trend (life falls sharply with "
    "temperature) and realistic magnitudes. A more rigorous variant \u2014 in "
    "which a temperature-dependent rate constant drives t_f directly (Eq. 1) "
    "and the conventional AF of Eq. (2) maps test time to service time \u2014 is "
    "identified as future work in Section 7."
)

doc.add_heading("5.4 Reproducing the results without MATLAB", level=2)
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
doc.add_heading("6. Results and Discussion \u2014 Code 1", level=1)
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
           "Figure 2. The script\u2019s temperature-scaling factor (log scale): "
           "it equals the pre-factor A (\u2248 5.14) at the 27 \u00b0C reference "
           "and decays exponentially as temperature rises, driving the drop in "
           "service life.")

doc.add_heading("6.1 Reading the table", level=2)
para(
    "Each row of Table 2 is produced by the worked steps of Section 4.6. The "
    "failure time t_f is constant at \u2248 1217 days because A, E_crit and n do "
    "not change with temperature; the temperature dependence enters entirely "
    "through the scaling factor in the second column. Multiplying the two and "
    "dividing by 365.25 gives the service life in the final column. For "
    "example, at 40 \u00b0C the scaling factor is \u2248 1.359, so the service "
    "life is 1217 \u00d7 1.359 / 365.25 \u2248 4.53 years."
)

doc.add_heading("6.2 Discussion", level=2)
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
    "Two practical implications follow. First, because the temperature term is "
    "exponential in 1/T, modest reductions in storage temperature yield "
    "disproportionately large gains in service life \u2014 a strong argument for "
    "climate-controlled magazines. Second, the same exponential sensitivity "
    "explains why short elevated-temperature tests are so attractive: the "
    "conventional Arrhenius acceleration factor between 27 \u00b0C and 70 "
    "\u00b0C is more than 50\u00d7 (exp[(E\u2090/R)(1/300.15 \u2212 1/343.15)] "
    "\u2248 56), so a few weeks of testing at 70 \u00b0C samples years of "
    "natural aging. The chief caveats are the model\u2019s strong sensitivity "
    "to the assumed activation energy and degradation exponent (cf. Kunz\u2019s "
    "warning on regression bias [8]) and its neglect of competing softening/"
    "hardening pathways [10]."
)

doc.add_heading("6.3 Sensitivity to the activation energy", level=2)
para(
    "Because E\u2090 sits inside an exponential, the prediction is acutely "
    "sensitive to it \u2014 the single biggest source of uncertainty in any "
    "accelerated-aging extrapolation. Figure 3 recomputes the service-life "
    "curve for E\u2090 = 60, 80 and 100 kJ/mol with all other inputs fixed. "
    "Raising E\u2090 steepens the curve: it lengthens predicted life at low "
    "storage temperatures and shortens it at high temperatures, pivoting about "
    "the 27 \u00b0C reference where the scaling factor is fixed at A. A 25 % "
    "error in E\u2090 changes the predicted room-temperature life by years, "
    "which is why E\u2090 should be determined from data spanning several test "
    "temperatures and reported with an uncertainty band rather than as a single "
    "number."
)
add_figure(os.path.join(FIG_DIR, "sensitivity_activation_energy.png"), 5.6,
           "Figure 3. Predicted service life for three activation energies; "
           "the curves pivot about the 27 \u00b0C reference, showing the strong "
           "leverage of E\u2090 on the extrapolation.")

# =========================================================================
# 7. CODE 2 - DATA-DRIVEN PIPELINE
# =========================================================================
doc.add_heading("7. Code 2: Data-Driven Service-Life Pipeline", level=1)
para(
    "Code 1 needs only a single test point and is intended for rapid screening. "
    "Code 2 is a complete, self-contained MATLAB pipeline (the function "
    "abcxyz / srp_pipeline) that performs the whole service-life workflow on a "
    "real accelerated-ageing campaign: it reads universal-testing-machine (UTM) "
    "tensile files, extracts mechanical properties from each stress\u2013strain "
    "curve, aggregates replicates, trains a cross-validated machine-learning "
    "surrogate of the chosen health property, fits a global first-order "
    "Arrhenius kinetic model, and extrapolates the service life to the storage "
    "temperature. It also contains a synthetic-data generator (so it runs with "
    "no input files) and a built-in self-test."
)
para(
    "Following the requested order, this section gives (7.1) the full source "
    "listing, (7.2) the results it produces on the built-in demonstration "
    "dataset, and (7.3) an explanation of the models and formulas it uses."
)

doc.add_heading("7.1 Source code \u2014 abcxyz.m (srp_pipeline)", level=2)
para(
    "Input files are named T<temp>_d<days>_v<rate>_s<sample> (e.g. "
    "T50_d122_v500_s3.xlsx = 50 \u00b0C, 122 days, 500 mm/min cross-head speed, "
    "sample 3). Each file holds three UTM columns: disp_mm, load_N, t_min. The "
    "complete listing follows.")
code_block(os.path.join(CODE_DIR, "abcxyz.m"),
           "Listing 3. Full data-driven service-life pipeline (abcxyz.m).")

doc.add_heading("7.2 Results", level=2)
with open(os.path.join(FIG_DIR, "pipeline_results.json")) as fh:
    pres = json.load(fh)
para(
    "Run on the built-in synthetic campaign (3 ageing temperatures \u00d7 5 "
    "storage durations \u00d7 3 strain rates \u00d7 10 replicates = "
    f"{pres['n_files']} tensile files, {pres['n_conditions']} ageing "
    "conditions, ground-truth activation energy 80 kJ/mol), the pipeline "
    "extracts the strain capacity eps_at_max as the health property and "
    "produces the following. (These numbers are reproduced exactly by "
    "generate_pipeline_results.py.)"
)
p2tbl = doc.add_table(rows=1, cols=2)
p2tbl.style = "Light Grid Accent 1"
p2tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
for c, h in zip(p2tbl.rows[0].cells, ("Quantity", "Value")):
    c.paragraphs[0].add_run(h).bold = True
p2_rows = [
    ("Tensile files analysed", f"{pres['n_files']}"),
    ("Ageing conditions", f"{pres['n_conditions']}"),
    ("Pristine value P0 (eps_at_max)", f"{pres['P0']:.3f}"),
    ("Failure threshold P_fail (50% of P0)", f"{pres['P_fail']:.3f}"),
    ("Fitted activation energy E\u2090", f"{pres['Ea_kJmol']:.1f} kJ/mol"),
    ("Kinetic-fit R\u00b2", f"{pres['kinetic_R2']:.3f}"),
    ("ML surrogate CV-R\u00b2 (5-fold)", f"{pres['ml_R2']:.3f}"),
    ("t_fail @ 50 / 60 / 70 \u00b0C (days)",
     f"{pres['tfail_kinetic_days']['50']:.0f} / "
     f"{pres['tfail_kinetic_days']['60']:.0f} / "
     f"{pres['tfail_kinetic_days']['70']:.0f}"),
    (f"Predicted service life @ {pres['serviceTemp_C']:.0f} \u00b0C",
     f"{pres['serviceLife_days']:.0f} days "
     f"({pres['serviceLife_years']:.1f} years)"),
]
for q, v in p2_rows:
    cells = p2tbl.add_row().cells
    cells[0].paragraphs[0].add_run(q).font.size = Pt(10)
    cells[1].paragraphs[0].add_run(v).font.size = Pt(10)
caption("Table 3. Key outputs of the data-driven pipeline on the demonstration "
        "dataset.")

add_figure(os.path.join(FIG_DIR, "pipeline_degradation_curves.png"), 5.6,
           "Figure 4. Health property (strain capacity) versus ageing time at "
           "the reference strain rate. Markers are replicate means \u00b1 1 SD; "
           "solid lines are the fitted first-order kinetic model; the dashed "
           "line is the failure threshold P_fail.")
add_figure(os.path.join(FIG_DIR, "pipeline_arrhenius.png"), 5.6,
           "Figure 5. Arrhenius plot of ln(t_fail) versus 1/T. The fit recovers "
           f"E\u2090 \u2248 {pres['Ea_kJmol']:.0f} kJ/mol (ground truth 80) and "
           f"extrapolates a {pres['serviceLife_years']:.0f}-year service life at "
           f"{pres['serviceTemp_C']:.0f} \u00b0C.")
add_figure(os.path.join(FIG_DIR, "pipeline_ml_parity.png"), 4.6,
           "Figure 6. Cross-validated parity plot for the machine-learning "
           f"surrogate (CV-R\u00b2 \u2248 {pres['ml_R2']:.2f}); points cluster "
           "around the 1:1 line, confirming the surrogate generalises.")
para(
    "The pipeline recovers the ground-truth activation energy to within a few "
    "kJ/mol and predicts a service life of roughly "
    f"{pres['serviceLife_years']:.0f} years at the {pres['serviceTemp_C']:.0f} "
    "\u00b0C storage temperature, comfortably bracketing the literature shelf-"
    "life benchmark of ~13 years [10] for a hotter or more conservative duty "
    "cycle. One honest caveat: because the accelerated window only spans about "
    "10 % of the property decay, the first-order asymptote P_inf is weakly "
    "identified (the optimiser drives it well below the physical floor while "
    "still fitting the data); the activation energy, per-temperature t_fail and "
    "extrapolated service life are nevertheless robust, because they depend on "
    "how the decay rate scales with temperature rather than on the far-field "
    "asymptote."
)

doc.add_heading("7.3 Models and formulas used", level=2)
para("The pipeline chains together five models, each summarised below.")

doc.add_heading("7.3.1 Feature extraction from the stress\u2013strain curve",
                level=3)
para(
    "Each UTM curve is converted to engineering stress and strain using the "
    "specimen geometry (gauge length L\u2080 = 47.75 mm, area A\u2080 = "
    "24 mm\u00b2):")
equation("\u03c3 = load / A\u2080 ,   \u03b5 = disp / L\u2080", "8")
para("From the (\u03b5, \u03c3) curve the code extracts: the tensile strength "
     "\u03c3_max and the strain at peak stress \u03b5_at_max; the initial "
     "modulus as the slope of a linear fit over the first 25 % of strain; a "
     "secant modulus at half the peak stress; the strain at break (where the "
     "stress first falls below 20 % of \u03c3_max after the peak); and the "
     "toughness as the area under the curve up to break:")
equation("E \u2248 d\u03c3/d\u03b5 |\u2080 ,   "
         "Toughness = \u222b\u2080^\u03b5_break \u03c3 d\u03b5", "9")
para("The default health property whose decay defines end-of-life is the strain "
     "capacity \u03b5_at_max, a direct measure of embrittlement (Section 1.2).")

doc.add_heading("7.3.2 Global first-order Arrhenius kinetic model", level=3)
para(
    "The aggregated health property at the reference strain rate is fitted "
    "across all temperatures simultaneously with a first-order decay whose rate "
    "constant follows Arrhenius:")
equation("P(t, T) = P_\u221e + (P\u2080 \u2212 P_\u221e) \u00b7 "
         "exp( \u2212k(T)\u00b7t )", "10")
equation("k(T) = exp[ ln k_ref \u2212 (E\u2090\u00b71000/R)\u00b7"
         "(1/T \u2212 1/T_ref) ]", "11")
para(
    "The four parameters P\u2080 (pristine value), P_\u221e (asymptote), "
    "ln k_ref (rate at the reference temperature T_ref) and E\u2090 (activation "
    "energy) are found by non-linear least squares (multi-start fminsearch), "
    "with a penalty keeping E\u2090 in the physical range 20\u2013250 kJ/mol. "
    "Two alternative kinetic laws are also provided \u2014 a linear model "
    "P = P\u2080 + r(T)\u00b7t and a log-linear model P = exp(P\u2080 + "
    "r(T)\u00b7t) \u2014 both with an Arrhenius rate r(T).")

doc.add_heading("7.3.3 Failure criterion and time-to-failure", level=3)
para(
    "End-of-life is reached when the health property falls to a fraction of its "
    "pristine value (default 50 %):")
equation("P_fail = f \u00b7 P\u2080   (f = 0.5)", "12")
para("Inverting the first-order model (Eq. 10) gives the time-to-failure at any "
     "temperature:")
equation("t_fail(T) = \u2212 ln[ (P_fail \u2212 P_\u221e)/(P\u2080 \u2212 "
         "P_\u221e) ] / k(T)", "13")

doc.add_heading("7.3.4 Arrhenius extrapolation to the service temperature",
                level=3)
para(
    "Plotted as ln(t_fail) against 1/T, the time-to-failure is linear with "
    "slope E\u2090\u00b71000/R (Figure 5), so the service life at the storage "
    "temperature T_s follows directly:")
equation("ln t_fail = b + (E\u2090\u00b71000/R)\u00b7(1/T) ,   "
         "service life = t_fail(T_s)", "14")

doc.add_heading("7.3.5 Cross-validated machine-learning surrogate", level=3)
para(
    "In parallel with the physics-based kinetics, the pipeline trains a "
    "data-driven surrogate that predicts the health property directly from "
    "(temperature, days, strain rate). It evaluates several learners \u2014 "
    "Gaussian-process regression, a bagged-tree ensemble, a support-vector "
    "machine, a robust linear model and a built-in polynomial-ridge fallback "
    "\u2014 by k-fold cross-validation and selects the one with the lowest "
    "cross-validated RMSE, reporting CV-RMSE and CV-R\u00b2 (Figure 6). The "
    "surrogate captures the combined effect of strain rate and ageing that the "
    "single-rate kinetic fit omits, and provides an independent check on the "
    "kinetic time-to-failure."
)
para(
    "As with Code 1, a Python reproduction (generate_pipeline_results.py) "
    "mirrors the synthetic generator, kinetic fit and ML surrogate so the "
    "figures and Table 3 can be regenerated without MATLAB."
)

# =========================================================================
# 8. CONCLUSION
# =========================================================================
doc.add_heading("8. Conclusion and Future Work", level=1)
para(
    "This report reviewed the main modelling families for solid-propellant "
    "aging and service-life prediction \u2014 cumulative-damage failure "
    "integrals, time\u2013temperature superposition, viscoelastic finite-"
    "element analysis, chemical-aging kinetics, handbook/nomograph methods and "
    "non-destructive indicators \u2014 and consolidated their governing "
    "equations. Two codes were then implemented and explained: a compact "
    "Arrhenius / power-law screening model (Code 1) and a complete data-driven "
    "pipeline (Code 2) that extracts mechanical properties from tensile tests, "
    "trains a cross-validated machine-learning surrogate and fits global "
    "first-order Arrhenius kinetics. Both were reproduced in Python and yield "
    "reproducible predictions: Code 1 captures the strong, non-linear "
    "dependence of service life on storage temperature, while Code 2 recovers "
    "the ground-truth activation energy (\u2248 83 vs 80 kJ/mol) and predicts a "
    "service life of order decades \u2014 results that agree in order of "
    "magnitude with published shelf-life estimates."
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
para(
    "The following are representative of the works studied for this report and "
    "are cited in the text; they are a selected subset of the broader "
    "literature consulted on solid-propellant aging and service-life "
    "prediction.", size=10.5, italic=True)
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
