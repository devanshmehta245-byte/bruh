function A = srp_aggregate(D, cfg)
%SRP_AGGREGATE  Average the replicate samples for each ageing condition.
%
%   A = SRP_AGGREGATE(D, cfg) groups the per-file rows of D (built by
%   srp_build_dataset) by the unique (temp_C, days, strain_rate) condition and
%   returns mean / std of every extracted feature over the replicate samples.
%
%   A is a struct with fields:
%       .temp_C, .days, .strain_rate   [nCond x 1] condition descriptors
%       .n                             replicate count per condition
%       .mean.(feat)                   [nCond x 1] mean of each feature
%       .std.(feat)                    [nCond x 1] std  of each feature
%       .featNames                     cell array of feature names

    if nargin < 2 || isempty(cfg); cfg = srp_config(); end

    rows = D.rows;
    key  = [ [rows.temp_C]', [rows.days]', [rows.strain_rate]' ];
    [uKey, ~, grp] = unique(key, 'rows');
    nCond = size(uKey, 1);

    A = struct();
    A.temp_C      = uKey(:, 1);
    A.days        = uKey(:, 2);
    A.strain_rate = uKey(:, 3);
    A.n           = accumarray(grp, 1);
    A.featNames   = D.featNames;
    A.mean = struct();
    A.std  = struct();

    for k = 1:numel(D.featNames)
        fn  = D.featNames{k};
        val = D.Y.(fn);
        mu  = nan(nCond, 1);
        sd  = nan(nCond, 1);
        for g = 1:nCond
            v = val(grp == g);
            v = v(isfinite(v));
            if ~isempty(v)
                mu(g) = mean(v);
                sd(g) = std(v);
            end
        end
        A.mean.(fn) = mu;
        A.std.(fn)  = sd;
    end
end
