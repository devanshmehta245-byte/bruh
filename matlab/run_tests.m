function run_tests()
%RUN_TESTS  Lightweight self-checks for the SRP service-life pipeline.
%
%   Exercises filename parsing, curve reading, feature extraction and a small
%   end-to-end run.  Works in MATLAB and GNU Octave.  Prints PASS/FAIL and
%   errors out if any assertion fails.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    nPass = 0; nFail = 0;

    % ---------------------------------------------------- 1) filename parsing
    info = srp_parse_filename('T50_d122_v500_s3.csv');
    [nPass, nFail] = check(info.valid && info.temp_C==50 && info.days==122 ...
        && info.strain_rate==500 && info.sample==3, ...
        'parse T50_d122_v500_s3.csv', nPass, nFail);

    info2 = srp_parse_filename('/x/y/t60_d31_v50_s7.txt');
    [nPass, nFail] = check(info2.temp_C==60 && info2.days==31 ...
        && info2.strain_rate==50 && info2.sample==7, ...
        'parse lowercase with path', nPass, nFail);

    bad = srp_parse_filename('not_a_valid_file.csv');
    [nPass, nFail] = check(~bad.valid, 'reject invalid filename', nPass, nFail);

    % ---------------------------------------------- 2) feature extraction
    cfg = srp_config();
    epsM = 0.30; sigM = 0.8;             % known peak
    eps = linspace(0, 1.4*epsM, 80)';
    r = eps / epsM;
    sigma = sigM * r .* exp(1 - r);      % peaks at eps=epsM, value sigM
    curve = struct('disp_mm', eps*cfg.gaugeLength_mm, ...
                   'load_N',  sigma*cfg.area_mm2, ...
                   't_min',   eps*0);
    f = srp_extract_features(curve, cfg, 50);
    [nPass, nFail] = check(abs(f.sigma_max - sigM) < 1e-3, ...
        sprintf('sigma_max (%.4f ~ %.4f)', f.sigma_max, sigM), nPass, nFail);
    [nPass, nFail] = check(abs(f.eps_at_max - epsM) < 0.02, ...
        sprintf('eps_at_max (%.4f ~ %.4f)', f.eps_at_max, epsM), nPass, nFail);
    [nPass, nFail] = check(f.modulus_MPa > 0 && f.toughness > 0, ...
        'modulus & toughness positive', nPass, nFail);

    % ---------------------------------------------- 3) read curve round-trip
    tmp = tempname(); mkdir(tmp);
    fp = fullfile(tmp, 'T70_d7_v5_s1.csv');
    fid = fopen(fp, 'w');
    fprintf(fid, 'disp_mm,load_N,t_min\n0,0,0\n1,10,0.2\n2,18,0.4\n3,5,0.6\n');
    fclose(fid);
    c = srp_read_curve(fp, cfg);
    [nPass, nFail] = check(numel(c.disp_mm)==4 && max(c.load_N)==18, ...
        'read_curve parses CSV with header', nPass, nFail);

    % ---------------------------------------------- 3b) xlsx round-trip
    try, pkg load io; catch; end   % Octave: make xlswrite/xlsread visible
    canXlsx = exist('writecell','file') || exist('xlswrite','file');
    if canXlsx
        try
            cfgx = srp_config(); cfgx.syntheticFormat = 'xlsx';
            cfgx.dataDir = fullfile(tmp, 'xlsx');
            cfgx.nSamples = 1;
            cfgx.daysByTemp = struct('T50',38, 'T60',16, 'T70',7);
            cfgx.strainRates_mmpmin = 50;
            generate_synthetic_data(cfgx, struct('seed',2));
            dl = dir(fullfile(cfgx.dataDir, '*.xlsx'));
            cx = srp_read_curve(fullfile(cfgx.dataDir, dl(1).name), cfgx);
            [nPass, nFail] = check(numel(dl)>=3 && numel(cx.disp_mm)>5 ...
                && max(cx.load_N)>0, 'xlsx write+read round-trip', nPass, nFail);
        catch err
            fprintf('  SKIP  xlsx round-trip (%s)\n', err.message);
        end
    else
        fprintf('  SKIP  xlsx round-trip (no xlsx writer available)\n');
    end

    % ---------------------------------------------- 4) mini end-to-end
    cfg2 = srp_config();
    cfg2.dataDir = fullfile(tmp, 'mini');
    cfg2.syntheticFormat = 'csv';   % keep this test free of the io package
    cfg2.nSamples = 3;
    cfg2.daysByTemp = struct('T50',[38 75 122], 'T60',[16 31 46], 'T70',[7 14 20]);
    generate_synthetic_data(cfg2, struct('seed',7));
    D = srp_build_dataset(cfg2);
    A = srp_aggregate(D, cfg2);
    model = srp_train_model(D.X, D.Y.(cfg2.mlTarget), cfg2.mlInputs, cfg2, false);
    res = srp_service_life(A, cfg2, model);
    [nPass, nFail] = check(isfinite(res.serviceLife_days) && res.serviceLife_days>0, ...
        sprintf('service life finite (%.0f days)', res.serviceLife_days), nPass, nFail);
    [nPass, nFail] = check(res.Ea_kJmol > 30 && res.Ea_kJmol < 200, ...
        sprintf('Ea physically plausible (%.1f kJ/mol)', res.Ea_kJmol), nPass, nFail);

    % cleanup
    try, rmdir(tmp, 's'); catch; end

    fprintf('\n==== %d passed, %d failed ====\n', nPass, nFail);
    if nFail > 0; error('run_tests: %d test(s) failed', nFail); end
end

function [nPass, nFail] = check(cond, name, nPass, nFail)
    if cond
        fprintf('  PASS  %s\n', name); nPass = nPass + 1;
    else
        fprintf('  FAIL  %s\n', name); nFail = nFail + 1;
    end
end
