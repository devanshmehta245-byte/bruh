function model = srp_train_model(X, y, predictorNames, cfg, verbose)
%SRP_TRAIN_MODEL  Train & cross-validate ML regressors for a propellant property.
%
%   model = SRP_TRAIN_MODEL(X, y, predictorNames, cfg) trains every candidate
%   learner listed in cfg.mlLearners on predictors X (rows = samples,
%   columns = predictorNames) and response y, evaluates each with k-fold
%   cross-validation, and returns the best model (lowest CV RMSE).
%
%   It uses the Statistics & Machine Learning Toolbox when available
%   (Gaussian process regression, bagged-tree ensembles, SVM, robust linear)
%   and ALWAYS includes a dependency-free polynomial least-squares model, so
%   the pipeline runs even with no toolbox / in GNU Octave.
%
%   The returned struct provides:
%       .name         name of the selected learner
%       .predictFcn   handle: yhat = predictFcn(Xnew)
%       .cvRMSE       cross-validated RMSE of the selected model
%       .cvR2         cross-validated R^2  of the selected model
%       .candidates   struct array with metrics for every learner tried
%       .predictors   predictorNames
%
%   See also: SRP_CONFIG, SRP_PREDICT_SERVICE_LIFE.

    if nargin < 4 || isempty(cfg);     cfg = srp_config(); end
    if nargin < 5 || isempty(verbose); verbose = true; end

    % keep only finite rows
    good = isfinite(y) & all(isfinite(X), 2);
    X = X(good, :); y = y(good);
    if numel(y) < 4
        error('srp_train_model:tooFew', 'Need >= 4 valid observations.');
    end

    local_seed(cfg.rngSeed);
    folds = local_kfold_indices(numel(y), cfg.cvFolds, cfg.rngSeed);

    cand = struct('name', {}, 'cvRMSE', {}, 'cvR2', {}, ...
                  'trainFcn', {}, 'available', {});
    for i = 1:numel(cfg.mlLearners)
        spec = local_learner_spec(cfg.mlLearners{i});
        if isempty(spec); continue; end
        cand(end+1) = spec; %#ok<AGROW>
    end

    % cross-validate every available candidate
    for i = 1:numel(cand)
        if ~cand(i).available
            cand(i).cvRMSE = Inf; cand(i).cvR2 = -Inf; continue;
        end
        [rmse, r2] = local_cross_validate(cand(i).trainFcn, X, y, folds);
        cand(i).cvRMSE = rmse;
        cand(i).cvR2   = r2;
        if verbose
            fprintf('  %-14s  CV-RMSE = %10.5g   CV-R2 = %7.4f\n', ...
                cand(i).name, rmse, r2);
        end
    end

    [~, best] = min([cand.cvRMSE]);

    % refit the best learner on ALL data
    finalPredict = cand(best).trainFcn(X, y);

    model = struct();
    model.name       = cand(best).name;
    model.predictFcn = finalPredict;
    model.cvRMSE     = cand(best).cvRMSE;
    model.cvR2       = cand(best).cvR2;
    model.candidates = cand;
    model.predictors = predictorNames;
    if verbose
        fprintf('  -> selected: %s (CV-RMSE = %.5g, CV-R2 = %.4f)\n', ...
            model.name, model.cvRMSE, model.cvR2);
    end
end

% ====================================================================== specs
function spec = local_learner_spec(name)
    spec = struct('name', name, 'cvRMSE', Inf, 'cvR2', -Inf, ...
                  'trainFcn', [], 'available', false);
    switch lower(name)
        case 'gpr'
            if exist('fitrgp', 'file')
                spec.trainFcn  = @(X,y) local_wrap(fitrgp(X, y, ...
                    'KernelFunction', 'ardsquaredexponential', ...
                    'BasisFunction', 'linear', 'Standardize', true));
                spec.available = true;
            end
        case 'ensemble'
            if exist('fitrensemble', 'file')
                spec.trainFcn  = @(X,y) local_wrap(fitrensemble(X, y, ...
                    'Method', 'Bag', 'NumLearningCycles', 200));
                spec.available = true;
            end
        case 'svm'
            if exist('fitrsvm', 'file')
                spec.trainFcn  = @(X,y) local_wrap(fitrsvm(X, y, ...
                    'KernelFunction', 'gaussian', 'Standardize', true));
                spec.available = true;
            end
        case 'linear'
            if exist('fitlm', 'file')
                spec.trainFcn  = @(X,y) local_wrap_lm(fitlm(X, y, ...
                    'RobustOpts', 'on'));
                spec.available = true;
            end
        case 'polyfallback'
            spec.trainFcn  = @(X,y) local_poly_train(X, y);
            spec.available = true;   % always available
        otherwise
            spec = [];
    end
end

function h = local_wrap(mdl)
    h = @(Xn) predict(mdl, Xn);
end

function h = local_wrap_lm(mdl)
    h = @(Xn) predict(mdl, Xn);
end

% ============================================ dependency-free polynomial model
function predictFcn = local_poly_train(X, y)
% Second-order polynomial (with interactions) + log(days) basis, fit by
% regularised least squares.  Standardises predictors for conditioning.
    mu = mean(X, 1); sg = std(X, 0, 1); sg(sg == 0) = 1;
    Phi = local_poly_basis(X, mu, sg);
    lambda = 1e-6 * trace(Phi' * Phi) / size(Phi, 2);
    beta = (Phi' * Phi + lambda * eye(size(Phi, 2))) \ (Phi' * y);
    predictFcn = @(Xn) local_poly_basis(Xn, mu, sg) * beta;
end

function Phi = local_poly_basis(X, mu, sg)
    Z = (X - mu) ./ sg;                 % standardised predictors
    n = size(Z, 1); p = size(Z, 2);
    cols = {ones(n, 1)};
    cols{end+1} = Z;                    % linear
    cols{end+1} = Z.^2;                 % quadratic
    for a = 1:p                         % pairwise interactions
        for b = a+1:p
            cols{end+1} = Z(:, a) .* Z(:, b); %#ok<AGROW>
        end
    end
    % log term on the 2nd predictor (days) helps saturating ageing trends
    if p >= 2
        cols{end+1} = log(max(X(:, 2), 0) + 1); %#ok<AGROW>
    end
    Phi = [cols{:}];
end

% ================================================================ CV utilities
function [rmse, r2] = local_cross_validate(trainFcn, X, y, folds)
    k = max(folds);
    yhat = nan(size(y));
    for f = 1:k
        te = (folds == f);
        tr = ~te;
        if sum(tr) < 3 || ~any(te); continue; end
        pf = trainFcn(X(tr, :), y(tr));
        yhat(te) = pf(X(te, :));
    end
    ok = isfinite(yhat);
    e  = y(ok) - yhat(ok);
    rmse = sqrt(mean(e.^2));
    ss_res = sum(e.^2);
    ss_tot = sum((y(ok) - mean(y(ok))).^2);
    if ss_tot > 0; r2 = 1 - ss_res / ss_tot; else; r2 = NaN; end
end

function folds = local_kfold_indices(n, k, seed)
    local_seed(seed);
    k = max(2, min(k, n));
    idx = mod(randperm(n) - 1, k) + 1;
    folds = zeros(n, 1);
    folds(:) = idx;
end

function local_seed(seed)
    try
        rng(seed);
    catch
        rand('state', seed); randn('state', seed); %#ok<RAND>
    end
end
