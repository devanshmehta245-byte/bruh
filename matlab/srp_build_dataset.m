function D = srp_build_dataset(cfg, dataDir)
%SRP_BUILD_DATASET  Scan a folder of UTM files and build a feature dataset.
%
%   D = SRP_BUILD_DATASET(cfg, dataDir) finds every file matching the
%   T..._d..._v..._s... naming scheme in dataDir (default cfg.dataDir),
%   parses the ageing conditions, reads each curve, extracts mechanical
%   features and assembles a dataset.
%
%   D is a struct with fields:
%       .rows        struct array, one element per file (conditions + features)
%       .X           [nFiles x nPredictors] matrix of ML predictors
%       .predictors  cell array of predictor names
%       .featNames   cell array of extracted feature names
%       .Y           struct: Y.(feat) is an [nFiles x 1] response vector
%       .files       cell array of file paths
%
%   This function uses only base-MATLAB / Octave features (struct arrays),
%   so it runs without the Statistics & ML toolbox.

    if nargin < 1 || isempty(cfg);     cfg = srp_config(); end
    if nargin < 2 || isempty(dataDir); dataDir = cfg.dataDir; end

    files = local_list_data_files(dataDir, cfg.fileExtensions);
    if isempty(files)
        error('srp_build_dataset:noFiles', ...
            ['No data files found in "%s".\n' ...
             'Generate the example set with generate_synthetic_data, or ' ...
             'point cfg.dataDir at your data.'], dataDir);
    end

    rows = struct([]);
    n = 0;
    for i = 1:numel(files)
        fp   = files{i};
        info = srp_parse_filename(fp);
        if ~info.valid
            warning('srp_build_dataset:skip', ...
                'Skipping unparseable file: %s', fp);
            continue;
        end
        curve = srp_read_curve(fp, cfg);
        feat  = srp_extract_features(curve, cfg, info.strain_rate);

        n = n + 1;
        r = struct();
        r.file        = fp;
        r.name        = info.name;
        r.temp_C      = info.temp_C;
        r.days        = info.days;
        r.strain_rate = info.strain_rate;
        r.sample      = info.sample;
        ff = fieldnames(feat);
        for k = 1:numel(ff)
            r.(ff{k}) = feat.(ff{k});
        end
        if isempty(rows); rows = r; else; rows(n) = r; end %#ok<AGROW>
    end

    if n == 0
        error('srp_build_dataset:noValid', 'No valid, parseable data files.');
    end

    D = struct();
    D.rows      = rows;
    D.files     = {rows.file};
    D.predictors= cfg.mlInputs;
    D.featNames = fieldnames(srp_extract_features(struct('disp_mm', [], ...
                    'load_N', [], 't_min', []), cfg, NaN));

    % predictor matrix
    D.X = zeros(n, numel(D.predictors));
    for j = 1:numel(D.predictors)
        D.X(:, j) = [rows.(D.predictors{j})]';
    end

    % response vectors for each extracted feature
    D.Y = struct();
    for k = 1:numel(D.featNames)
        fn = D.featNames{k};
        D.Y.(fn) = [rows.(fn)]';
    end

    fprintf('srp_build_dataset: loaded %d files from %s\n', n, dataDir);
end

function files = local_list_data_files(dataDir, exts)
    files = {};
    for e = 1:numel(exts)
        L = dir(fullfile(dataDir, ['*' exts{e}]));
        for i = 1:numel(L)
            if ~L(i).isdir
                files{end+1} = fullfile(dataDir, L(i).name); %#ok<AGROW>
            end
        end
    end
    files = sort(files);
end
