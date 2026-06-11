function results = main(varargin)
%MAIN  End-to-end SRP service-life prediction pipeline.
%
%   results = MAIN() runs the full workflow with default configuration:
%       1. (optional) generate a synthetic example dataset
%       2. load every UTM file and parse its ageing conditions
%       3. extract mechanical features (stress-strain analysis)
%       4. aggregate replicates per ageing condition
%       5. train & cross-validate ML models of the health property
%       6. fit accelerated-ageing (Arrhenius) kinetics
%       7. predict the in-service service life
%       8. save plots and a results summary
%
%   results = MAIN('Name', Value, ...) supported options:
%       'GenerateData'  (logical) create synthetic data first. Default: true
%                        only if cfg.dataDir is empty.
%       'DataDir'       (char)    override cfg.dataDir
%       'ServiceTemp'   (double)  override cfg.serviceTemp_C
%       'HealthProperty'(char)    override cfg.healthProperty
%
%   Returns a struct bundling the dataset, aggregated data, ML model and the
%   service-life result.
%
%   Example:
%       r = main();                                  % synthetic demo
%       r = main('DataDir','/path/to/real/data');    % your data
%       r = main('ServiceTemp', 30, 'HealthProperty', 'sigma_max');

    % make sure this folder is on the path
    here = fileparts(mfilename('fullpath'));
    addpath(here);

    cfg = srp_config();

    % ----- parse options
    p = local_opts(varargin);
    if isfield(p, 'DataDir');        cfg.dataDir        = p.DataDir;        end
    if isfield(p, 'ServiceTemp');    cfg.serviceTemp_C  = p.ServiceTemp;    end
    if isfield(p, 'HealthProperty')
        cfg.healthProperty = p.HealthProperty;
        cfg.mlTarget       = p.HealthProperty;
    end
    if ~exist(cfg.resultsDir, 'dir'); mkdir(cfg.resultsDir); end

    % ----- 1. (optional) generate synthetic data
    needData = local_count_files(cfg) == 0;
    genFlag  = needData;
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
    y = D.Y.(cfg.mlTarget);
    model = srp_train_model(D.X, y, cfg.mlInputs, cfg);

    % ----- 6-7. kinetics + service life
    fprintf('\n== Accelerated-ageing kinetics & service life ==\n');
    res = srp_service_life(A, cfg, model);
    local_report(res, cfg);

    % ----- 8. plots + summary file
    srp_plot_results(D, A, model, res, cfg);
    local_save_summary(D, A, model, res, cfg);

    results = struct('cfg', cfg, 'D', D, 'A', A, 'model', model, 'res', res);
end

% ==================================================================== helpers
function p = local_opts(args)
    p = struct();
    for i = 1:2:numel(args)
        p.(args{i}) = args{i+1};
    end
end

function n = local_count_files(cfg)
    n = 0;
    if ~exist(cfg.dataDir, 'dir'); return; end
    for e = 1:numel(cfg.fileExtensions)
        n = n + numel(dir(fullfile(cfg.dataDir, ['*' cfg.fileExtensions{e}])));
    end
end

function local_report(res, cfg)
    fprintf('\n--------------------------------------------------------\n');
    fprintf(' Service-life prediction\n');
    fprintf('--------------------------------------------------------\n');
    fprintf(' Health property        : %s (%s)\n', res.property, cfg.healthDirection);
    fprintf(' Pristine value  P0     : %.4g\n', res.P0);
    fprintf(' Failure threshold Pfail: %.4g  (%s)\n', res.P_fail, cfg.failureMode);
    fprintf(' Kinetic model          : %s\n', res.kineticModel);
    fprintf(' t_fail source          : %s\n', res.source);
    for i = 1:numel(res.temps_C)
        fprintf('   %2g C : t_fail = %8.1f days (kinetic) ', ...
            res.temps_C(i), res.tfail_kinetic(i));
        if isfinite(res.tfail_ml(i))
            fprintf('| %8.1f days (ML)', res.tfail_ml(i));
        end
        fprintf('\n');
    end
    fprintf(' Kinetic-fit R^2        : %.4f\n', res.kineticFitR2);
    fprintf(' Activation energy Ea   : %.1f kJ/mol\n', res.Ea_kJmol);
    fprintf(' Service temperature    : %g C\n', res.serviceTemp_C);
    fprintf(' PREDICTED SERVICE LIFE : %.0f days  =  %.2f years\n', ...
        res.serviceLife_days, res.serviceLife_years);
    fprintf('--------------------------------------------------------\n');
end

function local_save_summary(D, A, model, res, cfg)
    fpath = fullfile(cfg.resultsDir, 'service_life_summary.txt');
    fid = fopen(fpath, 'w');
    if fid < 0; warning('Cannot write summary'); return; end
    fprintf(fid, 'Solid Rocket Propellant - Service Life Prediction Summary\n');
    fprintf(fid, '=========================================================\n\n');
    fprintf(fid, 'Files analysed         : %d\n', numel(D.files));
    fprintf(fid, 'Ageing conditions      : %d\n', numel(A.days));
    fprintf(fid, 'Gauge length / area    : %.2f mm / %.2f mm^2\n', ...
        cfg.gaugeLength_mm, cfg.area_mm2);
    fprintf(fid, '\nML model               : %s\n', model.name);
    fprintf(fid, 'ML target              : %s\n', cfg.mlTarget);
    fprintf(fid, 'CV-RMSE / CV-R2        : %.5g / %.4f\n', model.cvRMSE, model.cvR2);
    fprintf(fid, '\nHealth property        : %s (%s)\n', res.property, cfg.healthDirection);
    fprintf(fid, 'Pristine P0            : %.4g\n', res.P0);
    fprintf(fid, 'Failure threshold      : %.4g (%s)\n', res.P_fail, cfg.failureMode);
    fprintf(fid, 'Kinetic model          : %s\n', res.kineticModel);
    fprintf(fid, 'Time-to-failure source : %s\n', res.source);
    for i = 1:numel(res.temps_C)
        fprintf(fid, '  %2g C : t_fail = %.1f days\n', ...
            res.temps_C(i), res.tfail_used(i));
    end
    fprintf(fid, '\nActivation energy Ea   : %.2f kJ/mol\n', res.Ea_kJmol);
    fprintf(fid, 'Arrhenius R^2          : %.4f\n', res.arrheniusR2);
    fprintf(fid, 'Service temperature    : %g C\n', res.serviceTemp_C);
    fprintf(fid, 'PREDICTED SERVICE LIFE : %.0f days = %.2f years\n', ...
        res.serviceLife_days, res.serviceLife_years);
    fclose(fid);
    fprintf('Summary written to %s\n', fpath);
end
