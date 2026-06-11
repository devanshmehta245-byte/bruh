function out = srp_predict_service_life(res, serviceTemp_C)
%SRP_PREDICT_SERVICE_LIFE  Service life at an arbitrary service temperature.
%
%   out = SRP_PREDICT_SERVICE_LIFE(res, serviceTemp_C) uses the fitted
%   Arrhenius relationship in res (from srp_service_life) to predict the
%   service life at one or more service temperatures (deg C).
%
%   out has fields .temp_C, .days, .years (vectors matching serviceTemp_C).

    if ~isfield(res, 'arrheniusSlope') || ~isfinite(res.arrheniusSlope)
        error('srp_predict_service_life:noFit', ...
            'res has no valid Arrhenius fit.');
    end
    serviceTemp_C = serviceTemp_C(:);
    TsK  = serviceTemp_C + 273.15;
    days = exp(res.arrheniusIntercept + res.arrheniusSlope ./ TsK);

    out = struct();
    out.temp_C = serviceTemp_C;
    out.days   = days;
    out.years  = days / 365.25;
end
