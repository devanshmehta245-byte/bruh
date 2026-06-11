function res = srp_service_life(A, cfg, model)
%SRP_SERVICE_LIFE  Predict propellant service life by accelerated-ageing kinetics.
%
%   res = SRP_SERVICE_LIFE(A, cfg, model) implements the standard accelerated-
%   ageing (Arrhenius) service-life methodology with a GLOBAL kinetic fit:
%
%     1. The chosen health property (cfg.healthProperty, e.g. strain-at-max-
%        stress) is described jointly over ALL ageing temperatures by
%               P(t,T) = f( t ; P0, Pinf, k(T) ),   k(T) = A*exp(-Ea/RT)
%        i.e. the pristine value P0 and asymptote/limit are SHARED across
%        temperatures and only the rate constant k(T) follows Arrhenius.  A
%        global fit is well conditioned even when little degradation occurs at
%        the lowest test temperature within the tested time window (the usual
%        failure mode of per-temperature fits).
%     2. An end-of-life criterion (cfg.failureMode / failureFraction) defines
%        the property value P_fail at which the propellant is unserviceable.
%     3. The activation energy Ea comes straight out of the global fit.
%     4. The time-to-failure is evaluated analytically at each test temperature
%        and extrapolated to the in-service temperature (cfg.serviceTemp_C).
%
%   A trained ML property model (optional) is used as an independent cross-
%   check: it provides a smooth ML-based time-to-failure at each accelerated
%   temperature.  The reported service life is based on the physically-grounded
%   global kinetic fit, because pure ML cannot extrapolate from 50-70 C down to
%   the service temperature.
%
%   Key fields of res:
%       .property, .P0, .Pinf, .P_fail, .kineticModel, .kineticFitR2
%       .temps_C, .tfail_kinetic, .tfail_ml          (days)
%       .Ea_kJmol, .arrheniusSlope, .arrheniusIntercept, .arrheniusR2
%       .serviceTemp_C, .serviceLife_days, .serviceLife_years
%       .accelFactor   (service life / t_fail at each test temperature)
%       .Pfun(t,T)     fitted property surface (function handle)

    if nargin < 2 || isempty(cfg);   cfg = srp_config(); end
    if nargin < 3; model = []; end

    prop    = cfg.healthProperty;
    refRate = cfg.referenceStrainRate;
    R       = cfg.R_gas;

    % --- select conditions at the reference strain rate -------------------
    sel = (A.strain_rate == refRate);
    if ~any(sel)
        warning('srp_service_life:noRefRate', ...
            ['No conditions at reference strain rate %g mm/min; ' ...
             'using all strain rates.'], refRate);
        sel = true(size(A.strain_rate));
    end
    t = A.days(sel);
    T = A.temp_C(sel);
    P = A.mean.(prop)(sel);
    good = isfinite(t) & isfinite(T) & isfinite(P);
    t = t(good); T = T(good); P = P(good);
    temps = unique(T);

    res = struct();
    res.property      = prop;
    res.refStrainRate = refRate;
    res.kineticModel  = cfg.kineticModel;
    res.temps_C       = temps;

    % --- global kinetic + Arrhenius fit ----------------------------------
    fit = local_global_fit(t, T, P, cfg.kineticModel, cfg.healthDirection, R);
    res.P0   = fit.P0;
    res.Pinf = fit.Pinf;
    res.Ea_kJmol = fit.Ea_kJmol;
    res.kineticFitR2 = fit.R2;
    res.Pfun = fit.Pfun;            % Pfun(t, T_in_C)

    % --- pristine value & failure threshold ------------------------------
    switch lower(cfg.failureMode)
        case 'relative'; P_fail = cfg.failureFraction * fit.P0;
        case 'absolute'; P_fail = cfg.failureAbsolute;
        otherwise
            error('srp_service_life:mode', 'Unknown failureMode "%s".', cfg.failureMode);
    end
    res.P_fail = P_fail;

    % --- analytic time-to-failure at each temperature --------------------
    nT = numel(temps);
    tfail_k = arrayfun(@(Tc) fit.tFail(P_fail, Tc), temps);
    res.tfail_kinetic = tfail_k(:);

    % --- ML cross-check time-to-failure ----------------------------------
    tfail_m = nan(nT, 1);
    if ~isempty(model)
        tMaxSearch = 50 * max(A.days);
        for i = 1:nT
            Pml = @(tt) local_ml_predict(model, temps(i), tt, refRate, cfg);
            tfail_m(i) = local_cross_time(Pml, P_fail, tMaxSearch);
        end
    end
    res.tfail_ml = tfail_m;

    % --- Arrhenius numbers / service life --------------------------------
    Ts_K  = cfg.serviceTemp_C + 273.15;
    res.serviceTemp_C    = cfg.serviceTemp_C;
    res.serviceLife_days = fit.tFail(P_fail, cfg.serviceTemp_C);
    res.serviceLife_years= res.serviceLife_days / 365.25;

    % ln(t_fail) = intercept + slope*(1/T): slope = Ea/R (kept for plotting /
    % srp_predict_service_life).  Anchor the intercept on the service point so
    % the linear relation reproduces the analytic service life exactly.
    res.arrheniusSlope     = fit.Ea_kJmol * 1000 / R;
    res.arrheniusIntercept = log(res.serviceLife_days) - res.arrheniusSlope / Ts_K;
    res.tfail_used = exp(res.arrheniusIntercept + res.arrheniusSlope ./ (temps + 273.15));
    res.source     = 'kinetic_global';

    % goodness of the straight Arrhenius line through the analytic t_fail pts
    ylog = log(tfail_k(:));
    yhat = res.arrheniusIntercept + res.arrheniusSlope ./ (temps + 273.15);
    vOK = isfinite(ylog) & isfinite(yhat);
    if nnz(vOK) >= 2
        ss_res = sum((ylog(vOK) - yhat(vOK)).^2);
        ss_tot = sum((ylog(vOK) - mean(ylog(vOK))).^2);
        res.arrheniusR2 = 1 - ss_res / max(ss_tot, eps);
    else
        res.arrheniusR2 = NaN;
    end

    res.accelFactor = res.serviceLife_days ./ tfail_k(:);
end

% =================================================================== global fit
function fit = local_global_fit(t, T, P, modelName, direction, R)
%LOCAL_GLOBAL_FIT  Joint fit of P(t,T) with Arrhenius-temperature dependence.
    t = t(:); T = T(:); P = P(:);
    TK = T + 273.15;
    sgn = 1; if strcmpi(direction, 'decrease'); sgn = -1; end
    span = max(P) - min(P); if span <= 0; span = max(abs(P), eps); end

    TrefK = median(TK);     % reference T for a well-scaled rate parameter
    EaSeeds = [40 60 80 100 120 150];   % kJ/mol multi-start seeds

    switch lower(modelName)
        % --------------------------------------------------- first order
        case 'firstorder'
            if sgn < 0           % decreasing toward a lower asymptote
                P0_0   = max(P) + 0.05 * span;
                Pinf_0 = min(P) - 0.15 * span;
            else                 % increasing toward an upper asymptote
                P0_0   = min(P) - 0.05 * span;
                Pinf_0 = max(P) + 0.15 * span;
            end
            lnkref0 = local_init_lnkref(t, TK, P, P0_0, Pinf_0, TrefK);
            % model uses rate referenced to TrefK: well conditioned.
            modelFun = @(th, tt, TTk) local_fo_model_ref(th, tt, TTk, R, TrefK);
            obj = @(th) sum((P - modelFun(th, t, TK)).^2) + local_ea_penalty(th(4), span);
            best = []; bestSSE = Inf;
            for Ea0 = EaSeeds
                th0 = [P0_0, Pinf_0, lnkref0, Ea0];
                th  = local_minimize(obj, th0);
                sse = sum((P - modelFun(th, t, TK)).^2);
                if isfinite(sse) && sse < bestSSE; bestSSE = sse; best = th; end
            end
            th = best;
            P0 = th(1); Pinf = th(2); lnkref = th(3); Ea_kJ = th(4);
            kFun  = @(Tc) exp(lnkref - (Ea_kJ*1000/R) .* (1./(Tc+273.15) - 1/TrefK));
            Pfun  = @(tt, Tc) Pinf + (P0 - Pinf) .* exp(-kFun(Tc) .* tt);
            tFail = @(Pf, Tc) local_fo_tfail(Pf, P0, Pinf, kFun(Tc));

        % --------------------------------------------------- linear (zero-order)
        case 'linear'
            P0_0  = local_intercept(t, P);
            [lnB0, Ea0] = local_init_rate(t, TK, P, R);
            th0 = [P0_0, lnB0, Ea0];
            rate = @(th, Tc) sgn * exp(th(2) - th(3)*1000 ./ (R*(Tc+273.15)));
            modelFun = @(th, tt, TTc) th(1) + rate(th, TTc) .* tt;
            th = local_minimize(@(th) sum((P - modelFun(th, t, T)).^2), th0);
            P0 = th(1); Pinf = sgn*Inf; Ea_kJ = th(3);
            Pfun  = @(tt, Tc) modelFun(th, tt, Tc);
            tFail = @(Pf, Tc) (Pf - P0) ./ rate(th, Tc);

        % --------------------------------------------------- log-linear
        case 'loglinear'
            lnP = log(max(P, eps));
            lnP0_0 = local_intercept(t, lnP);
            [lnB0, Ea0] = local_init_rate(t, TK, lnP, R);
            th0 = [lnP0_0, lnB0, Ea0];
            rate = @(th, Tc) sgn * exp(th(2) - th(3)*1000 ./ (R*(Tc+273.15)));
            modelFun = @(th, tt, TTc) exp(th(1) + rate(th, TTc) .* tt);
            th = local_minimize(@(th) sum((P - modelFun(th, t, T)).^2), th0);
            P0 = exp(th(1)); Pinf = sgn*Inf; Ea_kJ = th(3);
            Pfun  = @(tt, Tc) modelFun(th, tt, Tc);
            tFail = @(Pf, Tc) (log(max(Pf,eps)) - th(1)) ./ rate(th, Tc);

        otherwise
            error('local_global_fit:model', 'Unknown kineticModel "%s".', modelName);
    end

    % goodness of fit (R^2) on the property values
    Phat = Pfun(t, T);
    ss_res = sum((P - Phat).^2);
    ss_tot = sum((P - mean(P)).^2);
    fit = struct();
    fit.P0 = P0; fit.Pinf = Pinf; fit.Ea_kJmol = Ea_kJ;
    fit.Pfun = Pfun; fit.tFail = tFail;
    fit.R2 = 1 - ss_res / max(ss_tot, eps);
end

function y = local_fo_model_ref(th, t, TK, R, TrefK)
    P0 = th(1); Pinf = th(2); lnkref = th(3); Ea_kJ = th(4);
    k = exp(lnkref - (Ea_kJ*1000/R) .* (1 ./ TK - 1/TrefK));
    y = Pinf + (P0 - Pinf) .* exp(-k .* t);
end

function pen = local_ea_penalty(Ea_kJ, scale)
%LOCAL_EA_PENALTY  Soft barrier keeping activation energy in [20,250] kJ/mol.
    lo = 20; hi = 250;
    w  = 1e3 * max(scale^2, eps);
    pen = w * (max(0, lo - Ea_kJ)^2 + max(0, Ea_kJ - hi)^2);
end

function tf = local_fo_tfail(Pf, P0, Pinf, k)
    ratio = (Pf - Pinf) / (P0 - Pinf);
    if ratio <= 0 || ratio >= 1 || ~isfinite(ratio) || k <= 0
        tf = NaN;
    else
        tf = -log(ratio) / k;
    end
end

function lnkref0 = local_init_lnkref(t, TK, P, P0_0, Pinf_0, TrefK)
%LOCAL_INIT_LNKREF  Estimate ln(k) at the reference temperature for init.
    temps = unique(TK);
    kT = nan(numel(temps), 1);
    for i = 1:numel(temps)
        m = (TK == temps(i));
        ratio = (P(m) - Pinf_0) / (P0_0 - Pinf_0);
        ratio = min(max(ratio, 1e-4), 1 - 1e-9);
        y = log(ratio);                 % = -k*t
        if sum(m) >= 2
            p = polyfit(t(m), y, 1);
            kT(i) = max(-p(1), 1e-8);
        else
            kT(i) = max(-y / max(t(m), eps), 1e-8);
        end
    end
    % interpolate ln(k) to TrefK in 1/T space (Arrhenius-linear)
    x = 1 ./ temps; yk = log(kT);
    if numel(x) >= 2
        pr = polyfit(x, yk, 1);
        lnkref0 = polyval(pr, 1/TrefK);
    else
        lnkref0 = yk(1);
    end
    if ~isfinite(lnkref0); lnkref0 = log(1e-2); end
end

function [lnB0, Ea0] = local_init_rate(t, TK, P, R)
%LOCAL_INIT_RATE  Per-temperature linear slopes -> Arrhenius init (magnitude).
    temps = unique(TK);
    bT = nan(numel(temps), 1);
    for i = 1:numel(temps)
        m = (TK == temps(i));
        p = polyfit(t(m), P(m), 1);
        bT(i) = max(abs(p(1)), 1e-10);
    end
    pr = polyfit(1 ./ temps, log(bT), 1);
    Ea0  = -pr(1) * R / 1000;
    lnB0 = pr(2);
    if ~isfinite(Ea0) || Ea0 <= 0; Ea0 = 80; end
    if ~isfinite(lnB0);            lnB0 = 0;  end
end

function b = local_intercept(t, P)
    p = polyfit(t, P, 1);
    b = p(2);
end

% ====================================================================== helpers
function th = local_minimize(obj, th0)
    try
        opts = optimset('MaxIter', 20000, 'MaxFunEvals', 20000, ...
                        'TolX', 1e-10, 'TolFun', 1e-12);
        th = fminsearch(obj, th0, opts);
    catch
        th = fminsearch(obj, th0);
    end
end

function tcross = local_cross_time(Pfun, P_fail, tMax)
%LOCAL_CROSS_TIME  First time t in [0,tMax] where Pfun(t) crosses P_fail.
    N = 4000;
    tt = linspace(0, tMax, N);
    pp = Pfun(tt);
    g  = pp(:).' - P_fail;
    s  = sign(g);
    idx = find(s(1:end-1) .* s(2:end) <= 0 & s(1:end-1) ~= 0, 1, 'first');
    if isempty(idx)
        if g(1) == 0; tcross = 0; else; tcross = NaN; end
        return;
    end
    t1 = tt(idx); t2 = tt(idx+1); g1 = g(idx); g2 = g(idx+1);
    if g2 == g1; tcross = t1; else; tcross = t1 - g1*(t2 - t1)/(g2 - g1); end
end

function P = local_ml_predict(model, T, t, rate, cfg)
%LOCAL_ML_PREDICT  Evaluate the ML property model at (T, t, rate).
    t = t(:);
    X = zeros(numel(t), numel(cfg.mlInputs));
    for j = 1:numel(cfg.mlInputs)
        switch cfg.mlInputs{j}
            case 'temp_C';      X(:, j) = T;
            case 'days';        X(:, j) = t;
            case 'strain_rate'; X(:, j) = rate;
            otherwise;          X(:, j) = 0;
        end
    end
    P = model.predictFcn(X);
    P = P(:).';
end
