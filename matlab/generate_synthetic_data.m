function generate_synthetic_data(cfg, opts)
%GENERATE_SYNTHETIC_DATA  Create an example UTM dataset matching the campaign.
%
%   generate_synthetic_data(cfg, opts) writes one CSV per (temperature, days,
%   strain rate, sample) into cfg.dataDir, using the naming scheme
%       T<temp>_d<days>_v<rate>_s<sample>.csv
%   with columns  disp_mm, load_N, t_min.
%
%   The curves follow physically-motivated accelerated-ageing trends so the
%   full pipeline can be exercised end-to-end:
%     * strain capacity (strain at peak) DECREASES with ageing (embrittlement)
%     * tensile strength & modulus INCREASE with ageing (continued cure)
%     * ageing rate follows Arrhenius k(T) = A*exp(-Ea/RT)
%     * higher strain rate stiffens/strengthens, slightly lowers elongation
%
%   This is ONLY for demonstration/testing.  Replace cfg.dataDir with your
%   real measured files and the rest of the pipeline is unchanged.
%
%   opts (optional struct):
%       .seed        rng seed                       (default 1)
%       .noise       fractional sample scatter      (default 0.04)
%       .nPointsCurve number of points per curve    (default 60)
%       .EaTrue_kJmol ground-truth activation energy(default 80)

    if nargin < 1 || isempty(cfg); cfg = srp_config(); end
    if nargin < 2; opts = struct(); end
    if ~isfield(opts, 'seed');         opts.seed = 1;           end
    if ~isfield(opts, 'noise');        opts.noise = 0.04;       end
    if ~isfield(opts, 'nPointsCurve'); opts.nPointsCurve = 60;  end
    if ~isfield(opts, 'EaTrue_kJmol'); opts.EaTrue_kJmol = 80;  end

    try, rng(opts.seed); catch; rand('state', opts.seed); randn('state', opts.seed); end
    if ~exist(cfg.dataDir, 'dir'); mkdir(cfg.dataDir); end

    % --- ground-truth material / ageing parameters -----------------------
    Ea = opts.EaTrue_kJmol * 1000;            % J/mol
    R  = cfg.R_gas;
    % pre-exponential chosen so 70C gives strong decay over its day range
    A_k = 5e9;                                % 1/day
    eps0   = 0.40;  epsInf = 0.10;            % strain capacity (-)
    sig0   = 0.50;  dSig   = 0.45;            % tensile strength (MPa)
    E0     = 3.0;   dE     = 4.0;             % modulus-ish (MPa)
    vref   = cfg.referenceStrainRate;
    nRate_sig = 0.08;                         % strain-rate hardening exponent
    nRate_eps = 0.04;                         % strain-rate elongation exponent

    nWritten = 0;
    for T = cfg.temperatures_C
        k = A_k * exp(-Ea / (R * (T + 273.15)));     % 1/day
        daysList = cfg.daysByTemp.(sprintf('T%d', T));
        for d = daysList
            decay = exp(-k * d);
            epsM_base = epsInf + (eps0 - epsInf) * decay;     % decreases
            sigM_base = sig0 + dSig * (1 - decay);            % increases
            E_base    = E0   + dE   * (1 - decay);            % increases
            for v = cfg.strainRates_mmpmin
                rfac_sig = (v / vref) ^ nRate_sig;
                rfac_eps = (vref / v) ^ nRate_eps;
                for s = 1:cfg.nSamples
                    g = @(x) x * (1 + opts.noise * randn());
                    epsM = max(0.02, g(epsM_base) * rfac_eps);
                    sigM = max(0.05, g(sigM_base) * rfac_sig);
                    [disp_mm, load_N, t_min] = local_curve( ...
                        epsM, sigM, cfg, v, opts.nPointsCurve, opts.noise);
                    fname = sprintf('T%d_d%d_v%d_s%d.csv', T, d, v, s);
                    local_write(fullfile(cfg.dataDir, fname), ...
                        disp_mm, load_N, t_min);
                    nWritten = nWritten + 1;
                end
            end
        end
    end
    fprintf('generate_synthetic_data: wrote %d files to %s\n', nWritten, cfg.dataDir);
    fprintf('  (ground-truth Ea = %.0f kJ/mol)\n', opts.EaTrue_kJmol);
end

function [disp_mm, load_N, t_min] = local_curve(epsM, sigM, cfg, v, N, noise)
%LOCAL_CURVE  Phenomenological stress-strain curve peaking at (epsM, sigM).
    epsBreak = 1.40 * epsM;
    eps = linspace(0, epsBreak, N)';
    % sigma(eps) = sigM * (eps/epsM) * exp(1 - eps/epsM): peak at eps=epsM
    r = eps / epsM;
    sigma = sigM .* r .* exp(1 - r);
    sigma = max(sigma, 0);
    sigma = sigma .* (1 + 0.01 * noise/0.04 * randn(N, 1));   % mild measurement noise
    sigma = max(sigma, 0);

    disp_mm = eps * cfg.gaugeLength_mm;
    load_N  = sigma * cfg.area_mm2;
    t_min   = disp_mm / v;     % displacement / cross-head speed (mm / (mm/min))
end

function local_write(fpath, disp_mm, load_N, t_min)
    fid = fopen(fpath, 'w');
    if fid < 0; error('Cannot write %s', fpath); end
    fprintf(fid, 'disp_mm,load_N,t_min\n');
    fprintf(fid, '%.6f,%.6f,%.6f\n', [disp_mm, load_N, t_min]');
    fclose(fid);
end
