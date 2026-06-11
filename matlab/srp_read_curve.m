function curve = srp_read_curve(filepath, cfg)
%SRP_READ_CURVE  Read a single UTM data file into disp/load/time vectors.
%
%   curve = SRP_READ_CURVE(filepath, cfg) reads a delimited text/CSV file and
%   returns a struct with column vectors:
%       .disp_mm   cross-head displacement (mm)
%       .load_N    measured load           (N)
%       .t_min     elapsed time            (min)
%       .file      the source path
%
%   The reader auto-detects:
%       * delimiter (comma, tab, semicolon or whitespace)
%       * presence of a header row and the column order (using cfg.col.*)
%   If no header is found, cfg.defaultColumnOrder is assumed.
%
%   Rows with non-finite displacement or load are dropped.

    if nargin < 2 || isempty(cfg); cfg = srp_config(); end

    NL  = sprintf('\n');
    raw = fileread(filepath);
    raw = strrep(raw, sprintf('\r\n'), NL);
    raw = strrep(raw, sprintf('\r'),   NL);
    lines = strsplit(raw, NL);
    lines = lines(~cellfun(@(s) isempty(strtrim(s)), lines));
    if isempty(lines)
        error('srp_read_curve:empty', 'File is empty: %s', filepath);
    end

    % --- detect delimiter from the first data-ish line
    delim = local_detect_delimiter(lines{1});

    % --- detect header
    firstTokens = local_split(lines{1}, delim);
    hasHeader   = any(cellfun(@(t) isnan(str2double(t)) && ~isempty(strtrim(t)), firstTokens));

    if hasHeader
        headers   = lower(strtrim(firstTokens));
        dataLines = lines(2:end);
        colIdx    = local_match_columns(headers, cfg);
    else
        dataLines = lines;
        colIdx    = local_default_columns(cfg);
    end

    % --- parse numeric matrix
    nCols = max(struct2array_compat(colIdx));
    M = nan(numel(dataLines), max(nCols, 3));
    keep = false(numel(dataLines), 1);
    for i = 1:numel(dataLines)
        tok = local_split(dataLines{i}, delim);
        v   = str2double(tok);
        n   = min(numel(v), size(M, 2));
        if n >= 1
            M(i, 1:n) = v(1:n);
            keep(i) = true;
        end
    end
    M = M(keep, :);

    curve = struct();
    curve.file    = filepath;
    curve.disp_mm = local_get(M, colIdx.disp);
    curve.load_N  = local_get(M, colIdx.load);
    curve.t_min   = local_get(M, colIdx.time);

    % drop rows where displacement or load is not finite
    ok = isfinite(curve.disp_mm) & isfinite(curve.load_N);
    curve.disp_mm = curve.disp_mm(ok);
    curve.load_N  = curve.load_N(ok);
    if numel(curve.t_min) == numel(ok)
        curve.t_min = curve.t_min(ok);
    else
        curve.t_min = nan(sum(ok), 1);
    end
end

% ------------------------------------------------------------------ helpers
function delim = local_detect_delimiter(line)
    candidates = {',', sprintf('\t'), ';'};
    counts = cellfun(@(d) numel(strfind(line, d)), candidates);
    [mx, k] = max(counts);
    if mx > 0
        delim = candidates{k};
    else
        delim = ' ';   % whitespace
    end
end

function parts = local_split(line, delim)
    if strcmp(delim, ' ')
        parts = regexp(strtrim(line), '\s+', 'split');
    else
        parts = strsplit(line, delim);
    end
    parts = strtrim(parts);
end

function colIdx = local_match_columns(headers, cfg)
    colIdx.disp = local_find_col(headers, cfg.col.disp);
    colIdx.load = local_find_col(headers, cfg.col.load);
    colIdx.time = local_find_col(headers, cfg.col.time);
    if isnan(colIdx.disp) || isnan(colIdx.load)
        % fall back to positional if a required column is missing
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
    colIdx.load = find(strcmpi(order, 'load_N'),  1);
    colIdx.time = find(strcmpi(order, 't_min'),   1);
    if isempty(colIdx.disp); colIdx.disp = 1; end
    if isempty(colIdx.load); colIdx.load = 2; end
    if isempty(colIdx.time); colIdx.time = 3; end
end

function v = local_get(M, idx)
    if isnan(idx) || idx < 1 || idx > size(M, 2)
        v = nan(size(M, 1), 1);
    else
        v = M(:, idx);
    end
end

function a = struct2array_compat(s)
    f = fieldnames(s);
    a = zeros(1, numel(f));
    for i = 1:numel(f); a(i) = s.(f{i}); end
    a(isnan(a)) = 0;
end
