function cfg = srp_config()
%SRP_CONFIG  Central configuration for the solid-rocket-propellant (SRP)
%            service-life prediction pipeline.
%
%   cfg = SRP_CONFIG() returns a struct with every tunable parameter used by
%   the pipeline.  Edit the values here (or override fields after calling it)
%   instead of hard-coding numbers throughout the code.
%
%   Filenames are expected to follow the scheme:
%       T<temp>_d<days>_v<strainRate>_s<sample>[.csv|.txt|.dat]
%   e.g.  T50_d122_v500_s3.csv
%       temp        : storage/ageing temperature in degrees Celsius
%       days        : number of days the sample was stored (ageing time)
%       strainRate  : UTM cross-head speed in mm/min
%       sample      : sample/replicate number
%
%   Each data file contains (at least) three columns:
%       disp_mm   load_N   t_min
%
%   See also: MAIN, SRP_BUILD_DATASET, SRP_EXTRACT_FEATURES.

    cfg = struct();

    % ----------------------------------------------------------------- paths
    thisDir       = fileparts(mfilename('fullpath'));
    cfg.rootDir   = fileparts(thisDir);             % repository root
    cfg.dataDir   = fullfile(cfg.rootDir, 'data');  % where the data files live
    cfg.resultsDir= fullfile(cfg.rootDir, 'results');

    % ------------------------------------------------ dog-bone specimen geometry
    % Gauge length and cross-sectional area of the UTM dog-bone specimen.
    cfg.gaugeLength_mm = 47.75;   % L0  (mm)
    cfg.area_mm2       = 24.0;    % A0  (mm^2)  -> stress in N/mm^2 == MPa

    % ----------------------------------------------------- file format options
    % Column names as they may appear in a header line (case-insensitive).
    cfg.col.disp = {'disp_mm', 'disp', 'displacement', 'displacement_mm', 'extension_mm'};
    cfg.col.load = {'load_N', 'load', 'force', 'force_n', 'load_n'};
    cfg.col.time = {'t_min', 'time', 'time_min', 't', 'time_s'};
    % If a file has no header, assume this column order:
    cfg.defaultColumnOrder = {'disp_mm', 'load_N', 't_min'};
    % File types scanned in cfg.dataDir.  Real data is .xlsx; .csv/.txt/.dat
    % are also supported.
    cfg.fileExtensions = {'.xlsx', '.xls', '.csv', '.txt', '.dat'};
    % Format written by generate_synthetic_data ('xlsx' or 'csv').
    cfg.syntheticFormat = 'xlsx';

    % --------------------------------------------- feature-extraction settings
    % Fraction of the strain-at-peak used as the upper bound of the initial
    % "linear" region for Young's-modulus estimation.
    cfg.modulusStrainFraction = 0.25;
    cfg.modulusMinPoints      = 5;
    % A specimen is considered fractured when, *after* the load peak, the load
    % falls below this fraction of the peak load.
    cfg.breakLoadFraction     = 0.20;

    % ------------------------------------------------------- ageing conditions
    % Test matrix actually used in the campaign (also used by the synthetic
    % data generator).  Edit to match your real campaign.
    cfg.temperatures_C = [50, 60, 70];
    cfg.daysByTemp = struct( ...
        'T50', [38 75 122 156 190], ...
        'T60', [16 31 46 62 78], ...
        'T70', [7 14 20 27 34]);
    cfg.strainRates_mmpmin = [5, 50, 500];
    cfg.nSamples           = 10;

    % --------------------------------------------- service-life definition
    % Health indicator whose degradation defines end-of-life.  Strain capacity
    % (strain at maximum stress) is the classic embrittlement criterion for
    % composite solid propellants; switch to 'sigma_max' or 'modulus_MPa' if
    % your failure mode is stress/stiffness driven.
    cfg.healthProperty   = 'eps_at_max';   % field name from srp_extract_features
    cfg.healthDirection  = 'decrease';     % 'decrease' or 'increase' with ageing

    % Failure criterion:
    %   'relative' -> end-of-life when property reaches failureFraction * P0
    %   'absolute' -> end-of-life when property reaches failureAbsolute
    cfg.failureMode      = 'relative';
    cfg.failureFraction  = 0.50;           % retain 50% of pristine strain capacity
    cfg.failureAbsolute  = NaN;            % used only if failureMode == 'absolute'

    % Kinetic model used per-temperature to describe property vs ageing time:
    %   'firstorder' -> P(t) = Pinf + (P0 - Pinf)*exp(-k t)
    %   'linear'     -> P(t) = P0 + b*t
    %   'loglinear'  -> ln P(t) = ln P0 + b*t
    cfg.kineticModel     = 'firstorder';

    % Conditions at which we report the predicted service life.
    cfg.serviceTemp_C        = 25;   % in-service / storage temperature
    cfg.referenceStrainRate  = 50;   % mm/min, the rate the criterion refers to

    % --------------------------------------------------------- ML model options
    cfg.mlInputs   = {'temp_C', 'days', 'strain_rate'};  % predictors
    cfg.mlTarget   = cfg.healthProperty;                 % response
    cfg.cvFolds    = 5;
    cfg.rngSeed    = 42;
    % Candidate learners to try (MATLAB Stats & ML Toolbox).  Unavailable ones
    % are skipped automatically; a pure-MATLAB polynomial regression is always
    % available as a fallback so the pipeline runs without any toolbox.
    cfg.mlLearners = {'gpr', 'ensemble', 'svm', 'linear', 'polyfallback'};

    % --------------------------------------------------------------- physical
    cfg.R_gas = 8.314462618;   % J/(mol*K), universal gas constant
end
