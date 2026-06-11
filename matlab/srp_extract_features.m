function f = srp_extract_features(curve, cfg, nominalStrainRate)
%SRP_EXTRACT_FEATURES  Mechanical properties from one UTM load-displacement test.
%
%   f = SRP_EXTRACT_FEATURES(curve, cfg, nominalStrainRate) converts a raw
%   displacement/load curve into engineering stress-strain and extracts the
%   mechanical features used as ML predictors / targets:
%
%       .sigma_max     maximum (ultimate) tensile stress         (MPa)
%       .load_max_N    maximum load                              (N)
%       .eps_at_max    engineering strain at peak stress         (-)
%       .eps_break     strain at break/fracture                  (-)
%       .modulus_MPa   initial-region Young's modulus            (MPa)
%       .toughness     energy density to break (area under curve)(MJ/m^3)
%       .secant50_MPa  secant modulus at 50% of peak stress      (MPa)
%       .strain_rate   nominal cross-head rate                   (mm/min)
%       .true_rate_pm  strain rate = rate / gaugeLength          (1/min)
%       .nPoints       number of valid data points
%
%   Stress  = load_N / area_mm2            (N/mm^2 == MPa)
%   Strain  = disp_mm / gaugeLength_mm     (dimensionless)

    if nargin < 2 || isempty(cfg); cfg = srp_config(); end
    if nargin < 3; nominalStrainRate = NaN; end

    f = local_empty_features();
    f.strain_rate  = nominalStrainRate;
    f.true_rate_pm = nominalStrainRate / cfg.gaugeLength_mm;

    d = curve.disp_mm(:);
    P = curve.load_N(:);
    ok = isfinite(d) & isfinite(P);
    d = d(ok); P = P(ok);
    if numel(d) < 3
        return;   % not enough data; leave NaNs
    end

    % Sort by displacement (monotone loading) to be robust to row ordering.
    [d, order] = sort(d);
    P = P(order);

    stress = P / cfg.area_mm2;          % MPa
    strain = d / cfg.gaugeLength_mm;     % -

    f.nPoints = numel(d);

    % --- peak / ultimate ----------------------------------------------------
    [sigmaMax, idxMax] = max(stress);
    f.sigma_max  = sigmaMax;
    f.load_max_N = max(P);
    f.eps_at_max = strain(idxMax);

    % --- break / fracture ---------------------------------------------------
    idxBreak = numel(stress);   % default: last recorded point
    postPeak = idxMax+1 : numel(stress);
    if ~isempty(postPeak)
        dropped = find(stress(postPeak) < cfg.breakLoadFraction * sigmaMax, 1, 'first');
        if ~isempty(dropped)
            idxBreak = postPeak(dropped);
        end
    end
    f.eps_break = strain(idxBreak);

    % --- initial modulus ----------------------------------------------------
    epsCut = cfg.modulusStrainFraction * f.eps_at_max;
    region = find(strain <= epsCut & strain >= 0);
    if numel(region) < cfg.modulusMinPoints
        region = 1:min(cfg.modulusMinPoints, numel(strain));
    end
    if numel(region) >= 2 && (max(strain(region)) - min(strain(region))) > 0
        p = polyfit(strain(region), stress(region), 1);
        f.modulus_MPa = p(1);
    end

    % --- secant modulus at 50% of peak stress ------------------------------
    halfLvl = 0.5 * sigmaMax;
    iHalf = find(stress(1:idxMax) >= halfLvl, 1, 'first');
    if ~isempty(iHalf) && strain(iHalf) > 0
        f.secant50_MPa = stress(iHalf) / strain(iHalf);
    end

    % --- toughness (area under stress-strain up to break) ------------------
    upto = 1:idxBreak;
    if numel(upto) >= 2
        f.toughness = trapz(strain(upto), stress(upto));  % MPa == MJ/m^3
    end
end

function f = local_empty_features()
    f = struct( ...
        'sigma_max',   NaN, ...
        'load_max_N',  NaN, ...
        'eps_at_max',  NaN, ...
        'eps_break',   NaN, ...
        'modulus_MPa', NaN, ...
        'toughness',   NaN, ...
        'secant50_MPa',NaN, ...
        'strain_rate', NaN, ...
        'true_rate_pm',NaN, ...
        'nPoints',     0);
end
