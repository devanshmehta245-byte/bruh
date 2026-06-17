function results = abcxyz(varargin)
%SRP_PIPELINE All-in-one solid-rocket-propellant (SRP) service-life predictor.
%
% A single self-contained file that reads UTM tensile tests from an
% accelerated-ageing campaign, extracts mechanical properties, trains a
% cross-validated ML model of property degradation, fits accelerated-ageing
% (Arrhenius) kinetics and predicts the propellant SERVICE LIFE.
%
% FILE NAMING expected: T<temp>_d<days>_v<strainRate>_s<sample>
%   T  storage/ageing temperature (deg C)   e.g. T50
%   d  days stored before testing           e.g. d122
%   v  UTM cross-head speed (mm/min)         e.g. v500
%   s  sample/replicate number              e.g. s3
%   so T50_d122_v500_s3.xlsx = 50 C, 122 days, 500 mm/min, sample 3.
%
% EACH FILE (.xlsx/.xls/.csv/.txt/.dat) holds the three UTM columns:
%   disp_mm , load_N , t_min   (header row optional, auto-detected)
%   Geometry: gauge length 47.75 mm, area 24 mm^2 -> stress=load/24 (MPa),
%   strain = disp/47.75.
%
% USAGE
%   results = srp_pipeline();                          % synthetic demo (xlsx)
%   results = srp_pipeline('DataDir','/path/data');    % your files
%   results = srp_pipeline('ServiceTemp',30, 'HealthProperty','sigma_max');
%   srp_pipeline('test');                              % run built-in self-checks
%   cfg = srp_pipeline('config');                      % get the default config
%
% OPTIONS (Name,Value):
%   'DataDir'        folder with the data files
%   'GenerateData'   logical, create synthetic data first
%   'ServiceTemp'    in-service temperature (deg C), default 25
%   'HealthProperty' property whose decay defines end-of-life
%                    ('eps_at_max' default, 'sigma_max', 'modulus_MPa', ...)
%
% OUTPUT struct: .cfg .D (dataset) .A (aggregated) .model (ML) .res (service life)
%
% NOTE (GNU Octave): xlsx needs the "io" package (auto-loaded here; install
% with `pkg install -forge io` or `apt install octave-io`). MATLAB needs no
% extra toolbox; the Statistics & ML Toolbox is used when present, otherwise a
% built-in polynomial regressor is used.

addpath(fileparts(mfilename("C:\Users\TANVI GATTANI\Downloads\data\new_data_2")));
try pkg load io; catch; end %#ok<*CTCH>

% ----- dispatch special string commands
if nargin >= 1 && (ischar(varargin{1}) || isstring(varargin{1}))
    cmd = lower(char(varargin{1}));
    if any(strcmp(cmd, {'test', 'selftest', 'tests'}))
        results = srp_selftest(); return;
    elseif strcmp(cmd, 'config')
        results = srp_config(); return;
    end
end

cfg = srp_config();

% ----- parse Name/Value options
p = local_opts(varargin);
if isfield(p, 'DataDir'); cfg.dataDir = p.DataDir; end
if isfield(p, 'ServiceTemp'); cfg.serviceTemp_C = p.ServiceTemp; end
if isfield(p, 'HealthProperty')
    cfg.healthProperty = p.HealthProperty;
    cfg.mlTarget = p.HealthProperty;
end
if ~exist(cfg.resultsDir, 'dir'); mkdir(cfg.resultsDir); end

% ----- 1. (optional) generate synthetic data
genFlag = (local_count_files(cfg) == 0);
if isfield(p, 'GenerateData'); genFlag = logical(p.GenerateData); end
if genFlag
    fprintf('== Generating synthetic example dataset ==\n');
    generate_synthetic_data(cfg);
end

% ----- 2-3. load + feature extraction
fprintf('\n== Loading data & extracting features ==\n');
D = srp_build_dataset(cfg);

% ----- 4. aggregate replicates
A = srp_aggregate(D, cfg);
fprintf('Aggregated into %d ageing conditions.\n', numel(A.days));

% ----- 5. train ML model of the health property
fprintf('\n== Training ML model for "%s" ==\n', cfg.mlTarget);
model = srp_train_model(D.X, D.Y.(cfg.mlTarget), cfg.mlInputs, cfg, true);

% ----- 6-7. kinetics + service life
fprintf('\n== Accelerated-ageing kinetics & service life ==\n');
res = srp_service_life(A, cfg, model);
local_report(res, cfg);

% ----- 8. plots + summary file
srp_plot_results(D, A, model, res, cfg);
local_save_summary(D, A, model, res, cfg);

results = struct('cfg', cfg, 'D', D, 'A', A, 'model', model, 'res', res);
end

%% ======================================================================
%% CONFIGURATION
%% ======================================================================
function cfg = srp_config()
cfg = struct();
thisDir = fileparts(mfilename("C:\Users\USER\Downloads\intern\new_data_2"));
cfg.rootDir = thisDir;
cfg.dataDir = fullfile(thisDir, 'new_data_2');
cfg.resultsDir = fullfile(thisDir, 'results');

% dog-bone specimen geometry
cfg.gaugeLength_mm = 47.75;   % L0 (mm)
cfg.area_mm2 = 24.0;          % A0 (mm^2) -> stress in N/mm^2 == MPa

% column-name aliases (case-insensitive) and fallback order
cfg.col.disp = {'disp_mm','disp','displacement','displacement_mm','extension_mm'};
cfg.col.load = {'load_N','load','force','force_n','load_n'};
cfg.col.time = {'t_min','time','time_min','t','time_s'};
cfg.defaultColumnOrder = {'disp_mm','load_N','t_min'};
cfg.fileExtensions = {'.xlsx','.xls','.csv','.txt','.dat'};
cfg.syntheticFormat = 'xlsx';   % 'xlsx' or 'csv'

% feature-extraction settings
cfg.modulusStrainFraction = 0.25;
cfg.modulusMinPoints = 5;
cfg.breakLoadFraction = 0.20;

% ageing test matrix (also used by the synthetic generator)
cfg.temperatures_C = [50, 60, 70];
cfg.daysByTemp = struct('T50',[38 75 122 156 190], ...
    'T60',[16 31 46 62 78], ...
    'T70',[7 14 20 27 34]);
cfg.strainRates_mmpmin = [5, 50, 500];
cfg.nSamples = 10;

% service-life definition
cfg.healthProperty = 'eps_at_max';   % strain capacity (embrittlement)
cfg.healthDirection = 'decrease';    % 'decrease' or 'increase'
cfg.failureMode = 'relative';        % 'relative' or 'absolute'
cfg.failureFraction = 0.50;          % retain 50% of pristine
cfg.failureAbsolute = NaN;
cfg.kineticModel = 'firstorder';     % 'firstorder','linear','loglinear'
cfg.serviceTemp_C = 27;
cfg.referenceStrainRate = 50;

% ML options
cfg.mlInputs = {'temp_C','days','strain_rate'};
cfg.mlTarget = cfg.healthProperty;
cfg.cvFolds = 5;
cfg.rngSeed = 42;
cfg.mlLearners = {'gpr','ensemble','svm','linear','polyfallback'};

cfg.R_gas = 8.314462618;   % J/(mol*K)
end

%% ======================================================================
%% FILENAME PARSING
%% ======================================================================
function info = srp_parse_filename(name)
[~, base, ext] = fileparts(char(name));
if isempty(base) && ~isempty(ext); base = ext; end
info = struct('temp_C',NaN,'days',NaN,'strain_rate',NaN, ...
    'sample',NaN,'name',base,'valid',false);
info.temp_C = local_token(base, '[Tt]');
info.days = local_token(base, '[Dd]');
info.strain_rate = local_token(base, '[Vv]');
info.sample = local_token(base, '[Ss]');
info.valid = all(~isnan([info.temp_C, info.days, info.strain_rate, info.sample]));
end

function val = local_token(str, letterClass)
pat = [letterClass, '([+-]?\d+(?:\.\d+)?)'];
tok = regexp(str, pat, 'tokens', 'once');
if isempty(tok); val = NaN; else; val = str2double(tok{1}); end
end

%% ======================================================================
%% FILE READING (xlsx / xls / csv / txt / dat)
%% ======================================================================
function curve = srp_read_curve(filepath, cfg)
if nargin < 2 || isempty(cfg); cfg = srp_config(); end
[~, ~, ext] = fileparts(filepath);
if any(strcmpi(ext, {'.xlsx','.xls','.xlsm','.ods'}))
    [headers, M] = local_read_spreadsheet(filepath);
else
    [headers, M] = local_read_text(filepath);
end
if isempty(M)
    error('srp_read_curve:empty', 'No numeric data found in: %s', filepath);
end
if ~isempty(headers)
    colIdx = local_match_columns(lower(strtrim(headers)), cfg);
else
    colIdx = local_default_columns(cfg);
end
curve = struct();
curve.file = filepath;
curve.disp_mm = local_get(M, colIdx.disp);
curve.load_N = local_get(M, colIdx.load);
curve.t_min = local_get(M, colIdx.time);
ok = isfinite(curve.disp_mm) & isfinite(curve.load_N);
curve.disp_mm = curve.disp_mm(ok);
curve.load_N = curve.load_N(ok);
if numel(curve.t_min) == numel(ok)
    curve.t_min = curve.t_min(ok);
else
    curve.t_min = nan(sum(ok), 1);
end
end

function [headers, M] = local_read_spreadsheet(filepath)
raw = [];
if exist('readcell', 'file')   % MATLAB R2019a+
    try raw = readcell(filepath); catch, raw = []; end
end
if isempty(raw) && exist('xlsread', 'file')   % Octave io / older MATLAB
    try pkg load io; catch; end
    try [~, ~, raw] = readtable(filepath); catch, raw = []; end
end
if isempty(raw) && exist('readtable', 'file')
    try
        Tt = readtable(filepath);
        headers = Tt.Properties.VariableNames;
        M = local_table2num(Tt); return;
    catch, raw = [];
    end
end
if isempty(raw)
    error('srp_read_curve:noXlsx', ...
        'Cannot read spreadsheet "%s".\nIn GNU Octave: pkg install -forge io', filepath);
end
[headers, M] = local_cellblock2num(raw);
end

function [headers, M] = local_read_text(filepath)
NL = newline;
raw = fileread(filepath);
raw = strrep(raw, sprintf('\r\n'), NL);
raw = strrep(raw, sprintf('\r'), NL);
lines = strsplit(raw, NL);
lines = lines(~cellfun(@(s) isempty(strtrim(s)), lines));
if isempty(lines); headers = {}; M = []; return; end
delim = local_detect_delimiter(lines{1});
firstTokens = local_split(lines{1}, delim);
hasHeader = any(cellfun(@(t) isnan(str2double(t)) && ~isempty(strtrim(t)), firstTokens));
if hasHeader
    headers = strtrim(firstTokens); dataLines = lines(2:end);
else
    headers = {}; dataLines = lines;
end
nc = numel(firstTokens);
M = nan(numel(dataLines), max(nc, 3));
keep = false(numel(dataLines), 1);
for i = 1:numel(dataLines)
    tok = local_split(dataLines{i}, delim);
    v = str2double(tok);
    n = min(numel(v), size(M, 2));
    if n >= 1; M(i, 1:n) = v(1:n); keep(i) = true; end
end
M = M(keep, :);
end

function [headers, M] = local_cellblock2num(raw)
if isempty(raw); headers = {}; M = []; return; end
nRows = size(raw, 1); nCols = size(raw, 2);
firstRowText = false;
for c = 1:nCols
    if local_is_text(raw{1, c}); firstRowText = true; break; end
end
if firstRowText
    headers = cell(1, nCols);
    for c = 1:nCols; headers{c} = local_cell2str(raw{1, c}); end
    dataRows = 2:nRows;
else
    headers = {}; dataRows = 1:nRows;
end
M = nan(numel(dataRows), nCols);
for r = 1:numel(dataRows)
    for c = 1:nCols; M(r, c) = local_cell2num(raw{dataRows(r), c}); end
end
M = M(any(isfinite(M), 2), :);
end

function M = local_table2num(Tt)
nCols = size(Tt, 2);
M = nan(height(Tt), nCols);
for c = 1:nCols
    col = Tt{:, c};
    if isnumeric(col); M(:, c) = double(col);
    else; M(:, c) = str2double(string(col)); end
end
M = M(any(isfinite(M), 2), :);
end

function tf = local_is_text(x)
tf = ischar(x) || (iscell(x) && ~isempty(x) && ischar(x{1})) || ...
    (isstring(x) && ~ismissing(x) && isnan(str2double(x)));
end
function s = local_cell2str(x)
if ischar(x); s = x; elseif isstring(x); s = char(x);
elseif isnumeric(x); s = num2str(x); else; s = ''; end
end
function v = local_cell2num(x)
if isnumeric(x) && isscalar(x); v = double(x);
elseif islogical(x); v = double(x);
elseif ischar(x); v = str2double(x);
elseif isstring(x); v = str2double(x); else; v = NaN;
end
if isempty(v); v = NaN; end
end
function delim = local_detect_delimiter(line)
candidates = {',', sprintf('\t'), ';'};
counts = cellfun(@(d) numel(strfind(line, d)), candidates);
[mx, k] = max(counts);
if mx > 0; delim = candidates{k}; else; delim = ' '; end
end
function parts = local_split(line, delim)
if strcmp(delim, ' '); parts = regexp(strtrim(line), '\s+', 'split');
else; parts = strsplit(line, delim); end
parts = strtrim(parts);
end
function colIdx = local_match_columns(headers, cfg)
colIdx.disp = local_find_col(headers, cfg.col.disp);
colIdx.load = local_find_col(headers, cfg.col.load);
colIdx.time = local_find_col(headers, cfg.col.time);
if isnan(colIdx.disp) || isnan(colIdx.load)
    d = local_default_columns(cfg);
    if isnan(colIdx.disp); colIdx.disp = d.disp; end
    if isnan(colIdx.load); colIdx.load = d.load; end
    if isnan(colIdx.time); colIdx.time = d.time; end
end
end
function idx = local_find_col(headers, aliases)
idx = NaN;
for a = 1:numel(aliases)
    hit = find(strcmpi(headers, aliases{a}), 1);
    if ~isempty(hit); idx = hit; return; end
end
end
function colIdx = local_default_columns(cfg)
order = cfg.defaultColumnOrder;
colIdx.disp = find(strcmpi(order, 'disp_mm'), 1);
colIdx.load = find(strcmpi(order, 'load_N'), 1);
colIdx.time = find(strcmpi(order, 't_min'), 1);
if isempty(colIdx.disp); colIdx.disp = 1; end
if isempty(colIdx.load); colIdx.load = 2; end
if isempty(colIdx.time); colIdx.time = 3; end
end
function v = local_get(M, idx)
if isnan(idx) || idx < 1 || idx > size(M, 2); v = nan(size(M, 1), 1);
else; v = M(:, idx); end
end

%% ======================================================================
%% FEATURE EXTRACTION (stress-strain -> mechanical properties)
%% ======================================================================
function f = srp_extract_features(curve, cfg, nominalStrainRate)
if nargin < 2 || isempty(cfg); cfg = srp_config(); end
if nargin < 3; nominalStrainRate = NaN; end
f = local_empty_features();
f.strain_rate = nominalStrainRate;
f.true_rate_pm = nominalStrainRate / cfg.gaugeLength_mm;

d = curve.disp_mm(:); P = curve.load_N(:);
ok = isfinite(d) & isfinite(P); d = d(ok); P = P(ok);
if numel(d) < 3; return; end
[d, order] = sort(d); P = P(order);

stress = P / cfg.area_mm2;       % MPa
strain = d / cfg.gaugeLength_mm; % -
f.nPoints = numel(d);

[sigmaMax, idxMax] = max(stress);
f.sigma_max = sigmaMax;
f.load_max_N = max(P);
f.eps_at_max = strain(idxMax);

idxBreak = numel(stress);
postPeak = idxMax+1 : numel(stress);
if ~isempty(postPeak)
    dropped = find(stress(postPeak) < cfg.breakLoadFraction * sigmaMax, 1, 'first');
    if ~isempty(dropped); idxBreak = postPeak(dropped); end
end
f.eps_break = strain(idxBreak);

epsCut = cfg.modulusStrainFraction * f.eps_at_max;
region = find(strain <= epsCut & strain >= 0);
if numel(region) < cfg.modulusMinPoints
    region = 1:min(cfg.modulusMinPoints, numel(strain));
end
if numel(region) >= 2 && (max(strain(region)) - min(strain(region))) > 0
    pcoef = polyfit(strain(region), stress(region), 1);
    f.modulus_MPa = pcoef(1);
end

halfLvl = 0.5 * sigmaMax;
iHalf = find(stress(1:idxMax) >= halfLvl, 1, 'first');
if ~isempty(iHalf) && strain(iHalf) > 0
    f.secant50_MPa = stress(iHalf) / strain(iHalf);
end

upto = 1:idxBreak;
if numel(upto) >= 2; f.toughness = trapz(strain(upto), stress(upto)); end
end

function f = local_empty_features()
f = struct('sigma_max',NaN,'load_max_N',NaN,'eps_at_max',NaN, ...
    'eps_break',NaN,'modulus_MPa',NaN,'toughness',NaN, ...
    'secant50_MPa',NaN,'strain_rate',NaN,'true_rate_pm',NaN,'nPoints',0);
end

%% ======================================================================
%% DATASET ASSEMBLY
%% ======================================================================
function D = srp_build_dataset(cfg, dataDir)
if nargin < 1 || isempty(cfg); cfg = srp_config(); end
if nargin < 2 || isempty(dataDir); dataDir = cfg.dataDir; end
files = local_list_data_files(dataDir, cfg.fileExtensions);
if isempty(files)
    error('srp_build_dataset:noFiles', ...
        'No data files found in "%s". Generate demo data or set cfg.dataDir.', dataDir);
end
rows = struct([]); n = 0;
for i = 1:numel(files)
    fp = files{i};
    info = srp_parse_filename(fp);
    if ~info.valid
        warning('srp_build_dataset:skip', 'Skipping unparseable file: %s', fp);
        continue;
    end
    curve = srp_read_curve(fp, cfg);
    feat = srp_extract_features(curve, cfg, info.strain_rate);
    n = n + 1;
    r = struct('file',fp, 'name',info.name, 'temp_C',info.temp_C, ...
        'days',info.days, 'strain_rate',info.strain_rate, 'sample',info.sample);
    ff = fieldnames(feat);
    for k = 1:numel(ff); r.(ff{k}) = feat.(ff{k}); end
    if isempty(rows); rows = r; else; rows(n) = r; end
end
if n == 0; error('srp_build_dataset:noValid', 'No valid, parseable data files.'); end

D = struct();
D.rows = rows;
D.files = {rows.file};
D.predictors = cfg.mlInputs;
D.featNames = fieldnames(srp_extract_features( ...
    struct('disp_mm',[],'load_N',[],'t_min',[]), cfg, NaN));
D.X = zeros(n, numel(D.predictors));
for j = 1:numel(D.predictors); D.X(:, j) = [rows.(D.predictors{j})]'; end
D.Y = struct();
for k = 1:numel(D.featNames); D.Y.(D.featNames{k}) = [rows.(D.featNames{k})]'; end
fprintf('srp_build_dataset: loaded %d files from %s\n', n, dataDir);
end

function files = local_list_data_files(dataDir, exts)
files = {};
for e = 1:numel(exts)
    L = dir(fullfile(dataDir, ['*' exts{e}]));
    for i = 1:numel(L)
        if ~L(i).isdir; files{end+1} = fullfile(dataDir, L(i).name); end %#ok<AGROW>
    end
end
files = sort(files);
end

%% ======================================================================
%% AGGREGATION OVER REPLICATES
%% ======================================================================
function A = srp_aggregate(D, cfg)
if nargin < 2 || isempty(cfg); cfg = srp_config(); end
rows = D.rows;
key = [ [rows.temp_C]', [rows.days]', [rows.strain_rate]' ];
[uKey, ~, grp] = unique(key, 'rows');
nCond = size(uKey, 1);
A = struct();
A.temp_C = uKey(:,1); A.days = uKey(:,2); A.strain_rate = uKey(:,3);
A.n = accumarray(grp, 1);
A.featNames = D.featNames;
A.mean = struct(); A.std = struct();
for k = 1:numel(D.featNames)
    fn = D.featNames{k}; val = D.Y.(fn);
    mu = nan(nCond,1); sd = nan(nCond,1);
    for g = 1:nCond
        v = val(grp == g); v = v(isfinite(v));
        if ~isempty(v); mu(g) = mean(v); sd(g) = std(v); end
    end
    A.mean.(fn) = mu; A.std.(fn) = sd;
end
end

%% ======================================================================
%% MACHINE-LEARNING MODEL (cross-validated, toolbox-optional)
%% ======================================================================
function model = srp_train_model(X, y, predictorNames, cfg, verbose)
if nargin < 4 || isempty(cfg); cfg = srp_config(); end
if nargin < 5 || isempty(verbose); verbose = true; end
good = isfinite(y) & all(isfinite(X), 2);
X = X(good, :); y = y(good);
if numel(y) < 4; error('srp_train_model:tooFew', 'Need >= 4 valid observations.'); end
local_seed(cfg.rngSeed);
folds = local_kfold_indices(numel(y), cfg.cvFolds, cfg.rngSeed);

cand = struct('name', {}, 'cvRMSE', {}, 'cvR2', {}, 'trainFcn', {}, 'available', {});
for i = 1:numel(cfg.mlLearners)
    spec = local_learner_spec(cfg.mlLearners{i});
    if isempty(spec); continue; end
    cand(end+1) = spec; %#ok<AGROW>
end
for i = 1:numel(cand)
    if ~cand(i).available; cand(i).cvRMSE = Inf; cand(i).cvR2 = -Inf; continue; end
    [rmse, r2] = local_cross_validate(cand(i).trainFcn, X, y, folds);
    cand(i).cvRMSE = rmse; cand(i).cvR2 = r2;
    if verbose
        fprintf('   %-14s  CV-RMSE = %10.5g   CV-R2 = %7.4f\n', cand(i).name, rmse, r2);
    end
end
[~, best] = min([cand.cvRMSE]);
finalPredict = cand(best).trainFcn(X, y);
model = struct('name',cand(best).name, 'predictFcn',finalPredict, ...
    'cvRMSE',cand(best).cvRMSE, 'cvR2',cand(best).cvR2, ...
    'candidates',cand, 'predictors',{predictorNames});
if verbose
    fprintf('   -> selected: %s (CV-RMSE = %.5g, CV-R2 = %.4f)\n', ...
        model.name, model.cvRMSE, model.cvR2);
end
end

function spec = local_learner_spec(name)
spec = struct('name',name,'cvRMSE',Inf,'cvR2',-Inf,'trainFcn',[],'available',false);
switch lower(name)
    case 'gpr'
        if exist('fitrgp','file')
            spec.trainFcn = @(X,y) local_wrap(fitrgp(X,y, ...
                'KernelFunction','ardsquaredexponential','BasisFunction','linear','Standardize',true));
            spec.available = true;
        end
    case 'ensemble'
        if exist('fitrensemble','file')
            spec.trainFcn = @(X,y) local_wrap(fitrensemble(X,y,'Method','Bag','NumLearningCycles',200));
            spec.available = true;
        end
    case 'svm'
        if exist('fitrsvm','file')
            spec.trainFcn = @(X,y) local_wrap(fitrsvm(X,y,'KernelFunction','gaussian','Standardize',true));
            spec.available = true;
        end
    case 'linear'
        if exist('fitlm','file')
            spec.trainFcn = @(X,y) local_wrap(fitlm(X,y,'RobustOpts','on'));
            spec.available = true;
        end
    case 'polyfallback'
        spec.trainFcn = @(X,y) local_poly_train(X,y);
        spec.available = true;
    otherwise
        spec = [];
end
end
function h = local_wrap(mdl); h = @(Xn) predict(mdl, Xn); end

function predictFcn = local_poly_train(X, y)
mu = mean(X,1); sg = std(X,0,1); sg(sg==0) = 1;
Phi = local_poly_basis(X, mu, sg);
lambda = 1e-6 * trace(Phi'*Phi) / size(Phi,2);
beta = (Phi'*Phi + lambda*eye(size(Phi,2))) \ (Phi'*y);
predictFcn = @(Xn) local_poly_basis(Xn, mu, sg) * beta;
end
function Phi = local_poly_basis(X, mu, sg)
Z = (X - mu) ./ sg; n = size(Z,1); pdim = size(Z,2);
cols = {ones(n,1)}; cols{end+1} = Z; cols{end+1} = Z.^2;
for a = 1:pdim
    for b = a+1:pdim; cols{end+1} = Z(:,a).*Z(:,b); end %#ok<AGROW>
end
if pdim >= 2; cols{end+1} = log(max(X(:,2),0)+1); end
Phi = [cols{:}];
end
function [rmse, r2] = local_cross_validate(trainFcn, X, y, folds)
k = max(folds); yhat = nan(size(y));
for f = 1:k
    te = (folds==f); tr = ~te;
    if sum(tr) < 3 || ~any(te); continue; end
    pf = trainFcn(X(tr,:), y(tr)); yhat(te) = pf(X(te,:));
end
okk = isfinite(yhat); e = y(okk) - yhat(okk);
rmse = sqrt(mean(e.^2));
ss_res = sum(e.^2); ss_tot = sum((y(okk)-mean(y(okk))).^2);
if ss_tot > 0; r2 = 1 - ss_res/ss_tot; else; r2 = NaN; end
end
function folds = local_kfold_indices(n, k, seed)
local_seed(seed); k = max(2, min(k, n));
idx = mod(randperm(n)-1, k) + 1; folds = idx(:);
end
function local_seed(seed)
try rng(seed); catch, rand('state',seed); randn('state',seed); end %#ok<RAND>
end

%% ======================================================================
%% SERVICE-LIFE PREDICTION (global kinetic + Arrhenius)
%% ======================================================================
function res = srp_service_life(A, cfg, model)
if nargin < 2 || isempty(cfg); cfg = srp_config(); end
if nargin < 3; model = []; end
prop = cfg.healthProperty; refRate = cfg.referenceStrainRate; R = cfg.R_gas;

sel = (A.strain_rate == refRate);
if ~any(sel)
    warning('srp_service_life:noRefRate', ...
        'No conditions at reference strain rate %g; using all.', refRate);
    sel = true(size(A.strain_rate));
end
t = A.days(sel); T = A.temp_C(sel); P = A.mean.(prop)(sel);
good = isfinite(t) & isfinite(T) & isfinite(P);
t = t(good); T = T(good); P = P(good);
temps = unique(T);

res = struct();
res.property = prop; res.refStrainRate = refRate;
res.kineticModel = cfg.kineticModel; res.temps_C = temps;

fit = local_global_fit(t, T, P, cfg.kineticModel, cfg.healthDirection, R);
res.P0 = fit.P0; res.Pinf = fit.Pinf;
res.Ea_kJmol = fit.Ea_kJmol; res.kineticFitR2 = fit.R2; res.Pfun = fit.Pfun;

switch lower(cfg.failureMode)
    case 'relative'; P_fail = cfg.failureFraction * fit.P0;
    case 'absolute'; P_fail = cfg.failureAbsolute;
    otherwise; error('srp_service_life:mode','Unknown failureMode "%s".', cfg.failureMode);
end
res.P_fail = P_fail;

nT = numel(temps);
tfail_k = arrayfun(@(Tc) fit.tFail(P_fail, Tc), temps);
res.tfail_kinetic = tfail_k(:);

tfail_m = nan(nT, 1);
if ~isempty(model)
    tMaxSearch = 50 * max(A.days);
    for i = 1:nT
        Pml = @(tt) local_ml_predict(model, temps(i), tt, refRate, cfg);
        tfail_m(i) = local_cross_time(Pml, P_fail, tMaxSearch);
    end
end
res.tfail_ml = tfail_m;

Ts_K = cfg.serviceTemp_C + 273.15;
res.serviceTemp_C = cfg.serviceTemp_C;
res.serviceLife_days = fit.tFail(P_fail, cfg.serviceTemp_C);
res.serviceLife_years = res.serviceLife_days / 365.25;
res.arrheniusSlope = fit.Ea_kJmol * 1000 / R;
res.arrheniusIntercept = log(res.serviceLife_days) - res.arrheniusSlope / Ts_K;
res.tfail_used = exp(res.arrheniusIntercept + res.arrheniusSlope ./ (temps + 273.15));
res.source = 'kinetic_global';

ylog = log(tfail_k(:));
yhat = res.arrheniusIntercept + res.arrheniusSlope ./ (temps + 273.15);
vOK = isfinite(ylog) & isfinite(yhat);
if nnz(vOK) >= 2
    ss_res = sum((ylog(vOK)-yhat(vOK)).^2);
    ss_tot = sum((ylog(vOK)-mean(ylog(vOK))).^2);
    res.arrheniusR2 = 1 - ss_res/max(ss_tot,eps);
else
    res.arrheniusR2 = NaN;
end
res.accelFactor = res.serviceLife_days ./ tfail_k(:);
end

function fit = local_global_fit(t, T, P, modelName, direction, R)
t = t(:); T = T(:); P = P(:); TK = T + 273.15;
sgn = 1; if strcmpi(direction,'decrease'); sgn = -1; end
span = max(P) - min(P); if span <= 0; span = max(abs(P), eps); end
TrefK = median(TK); EaSeeds = [40 60 80 100 120 150];

switch lower(modelName)
    case 'firstorder'
        if sgn < 0
            P0_0 = max(P)+0.05*span; Pinf_0 = min(P)-0.15*span;
        else
            P0_0 = min(P)-0.05*span; Pinf_0 = max(P)+0.15*span;
        end
        lnkref0 = local_init_lnkref(t, TK, P, P0_0, Pinf_0, TrefK);
        modelFun = @(th, tt, TTk) local_fo_model_ref(th, tt, TTk, R, TrefK);
        obj = @(th) sum((P - modelFun(th, t, TK)).^2) + local_ea_penalty(th(4), span);
        best = []; bestSSE = Inf;
        for Ea0 = EaSeeds
            th0 = [P0_0, Pinf_0, lnkref0, Ea0];
            th = local_minimize(obj, th0);
            sse = sum((P - modelFun(th, t, TK)).^2);
            if isfinite(sse) && sse < bestSSE; bestSSE = sse; best = th; end
        end
        th = best;
        P0 = th(1); Pinf = th(2); lnkref = th(3); Ea_kJ = th(4);
        kFun = @(Tc) exp(lnkref - (Ea_kJ*1000/R) .* (1./(Tc+273.15) - 1/TrefK));
        Pfun = @(tt, Tc) Pinf + (P0 - Pinf) .* exp(-kFun(Tc) .* tt);
        tFail = @(Pf, Tc) local_fo_tfail(Pf, P0, Pinf, kFun(Tc));
    case 'linear'
        P0_0 = local_intercept(t, P);
        [lnB0, Ea0] = local_init_rate(t, TK, P, R);
        th0 = [P0_0, lnB0, Ea0];
        rate = @(th, Tc) sgn * exp(th(2) - th(3)*1000 ./ (R*(Tc+273.15)));
        modelFun = @(th, tt, TTc) th(1) + rate(th, TTc) .* tt;
        th = local_minimize(@(th) sum((P - modelFun(th, t, T)).^2), th0);
        P0 = th(1); Pinf = sgn*Inf; Ea_kJ = th(3);
        Pfun = @(tt, Tc) modelFun(th, tt, Tc);
        tFail = @(Pf, Tc) (Pf - P0) ./ rate(th, Tc);
    case 'loglinear'
        lnP = log(max(P, eps));
        lnP0_0 = local_intercept(t, lnP);
        [lnB0, Ea0] = local_init_rate(t, TK, lnP, R);
        th0 = [lnP0_0, lnB0, Ea0];
        rate = @(th, Tc) sgn * exp(th(2) - th(3)*1000 ./ (R*(Tc+273.15)));
        modelFun = @(th, tt, TTc) exp(th(1) + rate(th, TTc) .* tt);
        th = local_minimize(@(th) sum((P - modelFun(th, t, T)).^2), th0);
        P0 = exp(th(1)); Pinf = sgn*Inf; Ea_kJ = th(3);
        Pfun = @(tt, Tc) modelFun(th, tt, Tc);
        tFail = @(Pf, Tc) (log(max(Pf,eps)) - th(1)) ./ rate(th, Tc);
    otherwise
        error('local_global_fit:model','Unknown kineticModel "%s".', modelName);
end
Phat = Pfun(t, T);
ss_res = sum((P - Phat).^2); ss_tot = sum((P - mean(P)).^2);
fit = struct('P0',P0,'Pinf',Pinf,'Ea_kJmol',Ea_kJ,'Pfun',Pfun, ...
    'tFail',tFail,'R2', 1 - ss_res/max(ss_tot,eps));
end

function y = local_fo_model_ref(th, t, TK, R, TrefK)
P0 = th(1); Pinf = th(2); lnkref = th(3); Ea_kJ = th(4);
k = exp(lnkref - (Ea_kJ*1000/R) .* (1 ./ TK - 1/TrefK));
y = Pinf + (P0 - Pinf) .* exp(-k .* t);
end
function pen = local_ea_penalty(Ea_kJ, scale)
lo = 20; hi = 250; w = 1e3 * max(scale^2, eps);
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
temps = unique(TK); kT = nan(numel(temps),1);
for i = 1:numel(temps)
    m = (TK==temps(i));
    ratio = (P(m) - Pinf_0) / (P0_0 - Pinf_0);
    ratio = min(max(ratio, 1e-4), 1 - 1e-9);
    yv = log(ratio);
    if sum(m) >= 2; pcoef = polyfit(t(m), yv, 1); kT(i) = max(-pcoef(1), 1e-8);
    else; kT(i) = max(-yv / max(t(m), eps), 1e-8); end
end
x = 1 ./ temps; yk = log(kT);
if numel(x) >= 2; pr = polyfit(x, yk, 1); lnkref0 = polyval(pr, 1/TrefK);
else; lnkref0 = yk(1); end
if ~isfinite(lnkref0); lnkref0 = log(1e-2); end
end
function [lnB0, Ea0] = local_init_rate(t, TK, P, R)
temps = unique(TK); bT = nan(numel(temps),1);
for i = 1:numel(temps)
    m = (TK==temps(i)); pcoef = polyfit(t(m), P(m), 1);
    bT(i) = max(abs(pcoef(1)), 1e-10);
end
pr = polyfit(1 ./ temps, log(bT), 1);
Ea0 = -pr(1)*R/1000; lnB0 = pr(2);
if ~isfinite(Ea0) || Ea0 <= 0; Ea0 = 80; end
if ~isfinite(lnB0); lnB0 = 0; end
end
function b = local_intercept(t, P); pcoef = polyfit(t, P, 1); b = pcoef(2); end
function th = local_minimize(obj, th0)
try
    opts = optimset('MaxIter',20000,'MaxFunEvals',20000,'TolX',1e-10,'TolFun',1e-12);
    th = fminsearch(obj, th0, opts);
catch
    th = fminsearch(obj, th0);
end
end
function tcross = local_cross_time(Pfun, P_fail, tMax)
N = 4000; tt = linspace(0, tMax, N);
pp = Pfun(tt); g = pp(:).' - P_fail; s = sign(g);
idx = find(s(1:end-1).*s(2:end) <= 0 & s(1:end-1) ~= 0, 1, 'first');
if isempty(idx)
    if g(1)==0; tcross = 0; else; tcross = NaN; end; return;
end
t1 = tt(idx); t2 = tt(idx+1); g1 = g(idx); g2 = g(idx+1);
if g2==g1; tcross = t1; else; tcross = t1 - g1*(t2-t1)/(g2-g1); end
end
function P = local_ml_predict(model, T, t, rate, cfg)
t = t(:); X = zeros(numel(t), numel(cfg.mlInputs));
for j = 1:numel(cfg.mlInputs)
    switch cfg.mlInputs{j}
        case 'temp_C'; X(:,j) = T;
        case 'days'; X(:,j) = t;
        case 'strain_rate'; X(:,j) = rate;
        otherwise; X(:,j) = 0;
    end
end
P = model.predictFcn(X); P = P(:).';
end

%% ----- service life at an arbitrary temperature (uses fitted Arrhenius) -----
function out = srp_predict_service_life(res, serviceTemp_C)
if ~isfield(res,'arrheniusSlope') || ~isfinite(res.arrheniusSlope)
    error('srp_predict_service_life:noFit', 'res has no valid Arrhenius fit.');
end
serviceTemp_C = serviceTemp_C(:); TsK = serviceTemp_C + 273.15;
days = exp(res.arrheniusIntercept + res.arrheniusSlope ./ TsK);
out = struct('temp_C',serviceTemp_C, 'days',days, 'years',days/365.25);
end

%% ======================================================================
%% PLOTTING
%% ======================================================================
function srp_plot_results(D, A, model, res, cfg)
if nargin < 5 || isempty(cfg); cfg = srp_config(); end
if ~exist(cfg.resultsDir,'dir'); mkdir(cfg.resultsDir); end
prop = cfg.healthProperty;

try
    fig = local_new_fig(); hold on;
    temps = res.temps_C; colors = lines(numel(temps));
    hLeg = zeros(numel(temps),1); labels = cell(numel(temps),1);
    for i = 1:numel(temps)
        T = temps(i);
        m = (A.temp_C==T) & (A.strain_rate==cfg.referenceStrainRate);
        tt = A.days(m); pp = A.mean.(prop)(m); ss = A.std.(prop)(m);
        [tt, ord] = sort(tt); pp = pp(ord); ss = ss(ord);
        local_errorbar(tt, pp, ss, colors(i,:));
        tg = linspace(0, max(tt)*1.1, 100);
        hLeg(i) = plot(tg, res.Pfun(tg, T), '-', 'Color', colors(i,:), 'LineWidth', 1.8);
        labels{i} = sprintf('%g \\circC', T);
    end
    local_yline(res.P_fail, 'k--', 'P_{fail}');
    xlabel('ageing time (days)'); ylabel(strrep(prop,'_','\_'));
    title('Health property vs ageing time (reference strain rate)');
    legend(hLeg, labels); grid on; box on;
    local_save(fig, fullfile(cfg.resultsDir,'degradation_curves.png'));
catch err; warning('srp_plot_results:fig1','%s', err.message);
end

try
    y = D.Y.(cfg.mlTarget); yhat = model.predictFcn(D.X);
    gg = isfinite(y) & isfinite(yhat);
    fig = local_new_fig(); plot(y(gg), yhat(gg), 'o'); hold on;
    lim = [min([y(gg);yhat(gg)]), max([y(gg);yhat(gg)])];
    plot(lim, lim, 'k--'); axis equal; xlim(lim); ylim(lim);
    xlabel('measured'); ylabel('ML predicted');
    title(sprintf('ML "%s": %s (CV-R^2=%.3f)', model.name, strrep(cfg.mlTarget,'_','\_'), model.cvR2));
    grid on; box on;
    local_save(fig, fullfile(cfg.resultsDir,'ml_parity.png'));
catch err; warning('srp_plot_results:fig2','%s', err.message);
end

try
    if isfield(res,'arrheniusSlope') && isfinite(res.arrheniusSlope)
        fig = local_new_fig(); TK = res.temps_C + 273.15;
        x = 1 ./ TK; ylog = log(res.tfail_used);
        plot(x, ylog, 'o', 'MarkerFaceColor','b'); hold on;
        Ts = cfg.serviceTemp_C + 273.15;
        xg = linspace(min([x;1/Ts]), max([x;1/Ts]), 50);
        plot(xg, res.arrheniusIntercept + res.arrheniusSlope*xg, 'r-');
        plot(1/Ts, log(res.serviceLife_days), 'rs', 'MarkerFaceColor','r','MarkerSize',10);
        xlabel('1/T (1/K)'); ylabel('ln(t_{fail} / days)');
        title(sprintf('Arrhenius: E_a=%.1f kJ/mol, life=%.0f d (%.1f yr) @ %g \\circC', ...
            res.Ea_kJmol, res.serviceLife_days, res.serviceLife_years, cfg.serviceTemp_C));
        grid on; box on;
        local_save(fig, fullfile(cfg.resultsDir,'arrhenius.png'));
    end
catch err; warning('srp_plot_results:fig3','%s', err.message);
end
end
function fig = local_new_fig()
try fig = figure('Visible','off'); catch, fig = figure(); end
end
function local_save(fig, fname)
try print(fig, fname, '-dpng', '-r120'); catch
    try saveas(fig, fname); catch; end
end
try close(fig); catch; end
end
function local_errorbar(x, y, e, col)
e(~isfinite(e)) = 0;
try errorbar(x, y, e, 'o', 'Color', col, 'MarkerFaceColor', col);
catch, plot(x, y, 'o', 'Color', col, 'MarkerFaceColor', col); end
end
function local_yline(yv, style, label)
xl = xlim;
try
    plot(xl, [yv yv], style, 'HandleVisibility', 'off');
    text(xl(1), yv, [' ' label], 'VerticalAlignment', 'bottom');
catch
end
end

%% ======================================================================
%% SYNTHETIC DATA GENERATOR (example dataset matching the naming scheme)
%% ======================================================================
function generate_synthetic_data(cfg, opts)
if nargin < 1 || isempty(cfg); cfg = srp_config(); end
if nargin < 2; opts = struct(); end
if ~isfield(opts,'seed'); opts.seed = 1; end
if ~isfield(opts,'noise'); opts.noise = 0.04; end
if ~isfield(opts,'nPointsCurve'); opts.nPointsCurve = 60; end
if ~isfield(opts,'EaTrue_kJmol'); opts.EaTrue_kJmol = 80; end
try rng(opts.seed); catch, rand('state',opts.seed); randn('state',opts.seed); end
if ~exist(cfg.dataDir,'dir'); mkdir(cfg.dataDir); end

Ea = opts.EaTrue_kJmol*1000; R = cfg.R_gas; A_k = 5e9;
eps0=0.40; epsInf=0.10; sig0=0.50; dSig=0.45; E0=3.0; dE=4.0;
vref = cfg.referenceStrainRate; nRate_sig = 0.08; nRate_eps = 0.04;

nWritten = 0;
for T = cfg.temperatures_C
    k = A_k * exp(-Ea/(R*(T+273.15)));
    daysList = cfg.daysByTemp.(sprintf('T%d', T));
    for d = daysList
        decay = exp(-k*d);
        epsM_base = epsInf + (eps0-epsInf)*decay;
        sigM_base = sig0 + dSig*(1-decay);
        for v = cfg.strainRates_mmpmin
            rfac_sig = (v/vref)^nRate_sig; rfac_eps = (vref/v)^nRate_eps;
            for s = 1:cfg.nSamples
                g = @(x) x * (1 + opts.noise*randn());
                epsM = max(0.02, g(epsM_base)*rfac_eps);
                sigM = max(0.05, g(sigM_base)*rfac_sig);
                [disp_mm, load_N, t_min] = local_curve(epsM, sigM, cfg, v, opts.nPointsCurve, opts.noise);
                if strcmpi(local_field(cfg,'syntheticFormat','xlsx'),'csv'); ext='.csv';
                else; ext='.xlsx'; end
                fname = sprintf('T%d_d%d_v%d_s%d%s', T, d, v, s, ext);
                local_write(fullfile(cfg.dataDir, fname), disp_mm, load_N, t_min);
                nWritten = nWritten + 1;
            end
        end
    end
end
fprintf('generate_synthetic_data: wrote %d files to %s\n', nWritten, cfg.dataDir);
fprintf('   (ground-truth Ea = %.0f kJ/mol)\n', opts.EaTrue_kJmol);
end
function [disp_mm, load_N, t_min] = local_curve(epsM, sigM, cfg, v, N, noise)
epsBreak = 1.40*epsM; eps = linspace(0, epsBreak, N)';
r = eps/epsM; sigma = sigM .* r .* exp(1 - r); sigma = max(sigma, 0);
sigma = sigma .* (1 + 0.01*noise/0.04*randn(N,1)); sigma = max(sigma, 0);
disp_mm = eps*cfg.gaugeLength_mm; load_N = sigma*cfg.area_mm2; t_min = disp_mm/v;
end
function local_write(fpath, disp_mm, load_N, t_min)
[~,~,ext] = fileparts(fpath);
header = {'disp_mm','load_N','t_min'}; M = [disp_mm, load_N, t_min];
if any(strcmpi(ext, {'.xlsx','.xls'}))
    C = [header; num2cell(M)]; wrote = false;
    if exist('writecell','file'); try writecell(C, fpath); wrote = true; catch; end; end
    if ~wrote && exist('xlswrite','file')
        try pkg load io; catch; end
        try writecell(fpath, C); wrote = true; catch; end
    end
    if ~wrote
        error('Cannot write xlsx (need MATLAB writecell or Octave io). Set cfg.syntheticFormat=''csv''.');
    end
else
    fid = fopen(fpath,'w'); if fid<0; error('Cannot write %s', fpath); end
    fprintf(fid, '%s,%s,%s\n', header{:});
    fprintf(fid, '%.6f,%.6f,%.6f\n', M'); fclose(fid);
end
end
function v = local_field(s, name, def)
if isfield(s, name); v = s.(name); else; v = def; end
end

%% ======================================================================
%% CONSOLE REPORT + SUMMARY FILE
%% ======================================================================
function local_report(res, cfg)
fprintf('\n--------------------------------------------------------\n');
fprintf(' Service-life prediction\n');
fprintf('--------------------------------------------------------\n');
fprintf(' Health property        : %s (%s)\n', res.property, cfg.healthDirection);
fprintf(' Pristine value P0      : %.4g\n', res.P0);
fprintf(' Failure threshold Pfail: %.4g (%s)\n', res.P_fail, cfg.failureMode);
fprintf(' Kinetic model          : %s\n', res.kineticModel);
fprintf(' t_fail source          : %s\n', res.source);
for i = 1:numel(res.temps_C)
    fprintf(' %2g C : t_fail = %8.1f days (kinetic) ', res.temps_C(i), res.tfail_kinetic(i));
    if isfinite(res.tfail_ml(i)); fprintf('| %8.1f days (ML)', res.tfail_ml(i)); end
    fprintf('\n');
end
fprintf(' Kinetic-fit R^2        : %.4f\n', res.kineticFitR2);
fprintf(' Activation energy Ea   : %.1f kJ/mol\n', res.Ea_kJmol);
fprintf(' Service temperature    : %g C\n', res.serviceTemp_C);
fprintf(' PREDICTED SERVICE LIFE : %.0f days = %.2f years\n', ...
    res.serviceLife_days, res.serviceLife_years);
fprintf('--------------------------------------------------------\n');
end
function local_save_summary(D, A, model, res, cfg)
fpath = fullfile(cfg.resultsDir, 'service_life_summary.txt');
fid = fopen(fpath, 'w'); if fid < 0; warning('Cannot write summary'); return; end
fprintf(fid, 'Solid Rocket Propellant - Service Life Prediction Summary\n');
fprintf(fid, '=========================================================\n\n');
fprintf(fid, 'Files analysed       : %d\n', numel(D.files));
fprintf(fid, 'Ageing conditions    : %d\n', numel(A.days));
fprintf(fid, 'Gauge length / area  : %.2f mm / %.2f mm^2\n', cfg.gaugeLength_mm, cfg.area_mm2);
fprintf(fid, '\nML model           : %s\n', model.name);
fprintf(fid, 'ML target            : %s\n', cfg.mlTarget);
fprintf(fid, 'CV-RMSE / CV-R2      : %.5g / %.4f\n', model.cvRMSE, model.cvR2);
fprintf(fid, '\nHealth property    : %s (%s)\n', res.property, cfg.healthDirection);
fprintf(fid, 'Pristine P0          : %.4g\n', res.P0);
fprintf(fid, 'Failure threshold    : %.4g (%s)\n', res.P_fail, cfg.failureMode);
fprintf(fid, 'Kinetic model        : %s\n', res.kineticModel);
for i = 1:numel(res.temps_C)
    fprintf(fid, ' %2g C : t_fail = %.1f days\n', res.temps_C(i), res.tfail_used(i));
end
fprintf(fid, '\nActivation energy Ea : %.2f kJ/mol\n', res.Ea_kJmol);
fprintf(fid, 'Service temperature  : %g C\n', res.serviceTemp_C);
fprintf(fid, 'PREDICTED SERVICE LIFE : %.0f days = %.2f years\n', ...
    res.serviceLife_days, res.serviceLife_years);
fclose(fid);
fprintf('Summary written to %s\n', fpath);
end

%% ======================================================================
%% OPTION PARSING + FILE COUNT
%% ======================================================================
function p = local_opts(args)
p = struct();
for i = 1:2:numel(args)-1
    if ischar(args{i}) || isstring(args{i}); p.(char(args{i})) = args{i+1}; end
end
end
function n = local_count_files(cfg)
n = 0; if ~exist(cfg.dataDir,'dir'); return; end
for e = 1:numel(cfg.fileExtensions)
    n = n + numel(dir(fullfile(cfg.dataDir, ['*' cfg.fileExtensions{e}])));
end
end

%% ======================================================================
%% BUILT-IN SELF-TEST ( srp_pipeline('test') )
%% ======================================================================
function ok = srp_selftest()
nPass = 0; nFail = 0;
info = srp_parse_filename('T50_d122_v500_s3.xlsx');
[nPass,nFail] = local_check(info.valid && info.temp_C==50 && info.days==122 ...
    && info.strain_rate==500 && info.sample==3, 'parse T50_d122_v500_s3', nPass, nFail);
bad = srp_parse_filename('not_a_valid_file.csv');
[nPass,nFail] = local_check(~bad.valid, 'reject invalid filename', nPass, nFail);

cfg = srp_config();
epsM = 0.30; sigM = 0.8; eps = linspace(0, 1.4*epsM, 80)';
r = eps/epsM; sigma = sigM*r.*exp(1-r);
curve = struct('disp_mm',eps*cfg.gaugeLength_mm,'load_N',sigma*cfg.area_mm2,'t_min',eps*0);
f = srp_extract_features(curve, cfg, 50);
[nPass,nFail] = local_check(abs(f.sigma_max-sigM)<1e-3, ...
    sprintf('sigma_max (%.4f~%.4f)', f.sigma_max, sigM), nPass, nFail);
[nPass,nFail] = local_check(abs(f.eps_at_max-epsM)<0.02, ...
    sprintf('eps_at_max (%.4f~%.4f)', f.eps_at_max, epsM), nPass, nFail);

tmp = tempname(); mkdir(tmp);
cfg2 = srp_config(); cfg2.dataDir = fullfile(tmp,'mini'); cfg2.syntheticFormat='csv';
cfg2.nSamples = 3;
cfg2.daysByTemp = struct('T50',[38 75 122],'T60',[16 31 46],'T70',[7 14 20]);
generate_synthetic_data(cfg2, struct('seed',7));
D = srp_build_dataset(cfg2); A = srp_aggregate(D, cfg2);
model = srp_train_model(D.X, D.Y.(cfg2.mlTarget), cfg2.mlInputs, cfg2, false);
res = srp_service_life(A, cfg2, model);
[nPass,nFail] = local_check(isfinite(res.serviceLife_days) && res.serviceLife_days>0, ...
    sprintf('service life finite (%.0f days)', res.serviceLife_days), nPass, nFail);
[nPass,nFail] = local_check(res.Ea_kJmol>30 && res.Ea_kJmol<200, ...
    sprintf('Ea plausible (%.1f kJ/mol)', res.Ea_kJmol), nPass, nFail);

try pkg load io; catch; end
if exist('writecell','file') || exist('xlswrite','file')
    try
        cfgx = srp_config(); cfgx.syntheticFormat='xlsx';
        cfgx.dataDir = fullfile(tmp,'xlsx'); cfgx.nSamples=1;
        cfgx.daysByTemp = struct('T50',38,'T60',16,'T70',7); cfgx.strainRates_mmpmin=50;
        generate_synthetic_data(cfgx, struct('seed',2));
        dl = dir(fullfile(cfgx.dataDir,'*.xlsx'));
        cx = srp_read_curve(fullfile(cfgx.dataDir, dl(1).name), cfgx);
        [nPass,nFail] = local_check(numel(dl)>=3 && numel(cx.disp_mm)>5 && max(cx.load_N)>0, ...
            'xlsx write+read round-trip', nPass, nFail);
    catch err
        fprintf(' SKIP xlsx round-trip (%s)\n', err.message);
    end
else
    fprintf(' SKIP xlsx round-trip (no xlsx writer)\n');
end
try rmdir(tmp,'s'); catch; end

fprintf('\n==== %d passed, %d failed ====\n', nPass, nFail);
ok = (nFail == 0);
if ~ok; error('srp_pipeline:selftest', '%d test(s) failed', nFail); end
end
function [nPass,nFail] = local_check(cond, name, nPass, nFail)
if cond; fprintf(' PASS %s\n', name); nPass=nPass+1;
else; fprintf(' FAIL %s\n', name); nFail=nFail+1; end
end
