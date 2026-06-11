function curve = srp_read_curve(filepath, cfg)
%SRP_READ_CURVE  Read a single UTM data file into disp/load/time vectors.
%
%   curve = SRP_READ_CURVE(filepath, cfg) reads a UTM data file and returns a
%   struct with column vectors:
%       .disp_mm   cross-head displacement (mm)
%       .load_N    measured load           (N)
%       .t_min     elapsed time            (min)
%       .file      the source path
%
%   Supported formats (chosen from the file extension):
%       * .xlsx / .xls          Excel spreadsheets (first worksheet)
%       * .csv / .txt / .dat    delimited text (delimiter auto-detected)
%
%   For every format the reader auto-detects a header row and the column
%   order using the aliases in cfg.col.*  (e.g. disp_mm / displacement,
%   load_N / force, t_min / time).  If no header is found,
%   cfg.defaultColumnOrder is assumed.  Rows with non-finite displacement or
%   load are dropped.
%
%   NOTE (GNU Octave): reading .xlsx requires the "io" package
%   (run `pkg load io`).  MATLAB needs no extra toolbox (uses readcell).

    if nargin < 2 || isempty(cfg); cfg = srp_config(); end

    [~, ~, ext] = fileparts(filepath);
    if any(strcmpi(ext, {'.xlsx', '.xls', '.xlsm', '.ods'}))
        [headers, M] = local_read_spreadsheet(filepath);
    else
        [headers, M] = local_read_text(filepath);
    end

    if isempty(M)
        error('srp_read_curve:empty', 'No numeric data found in: %s', filepath);
    end

    % --- choose columns ---------------------------------------------------
    if ~isempty(headers)
        colIdx = local_match_columns(lower(strtrim(headers)), cfg);
    else
        colIdx = local_default_columns(cfg);
    end

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

% ============================================================ spreadsheet path
function [headers, M] = local_read_spreadsheet(filepath)
%LOCAL_READ_SPREADSHEET  Return header strings + numeric matrix from xlsx/xls.
    raw = [];

    % MATLAB (R2019a+): readcell needs no toolbox.
    if exist('readcell', 'file')
        try
            raw = readcell(filepath);
        catch
            raw = [];
        end
    end

    % Octave (io package) or older MATLAB: xlsread returns [num, txt, raw].
    if isempty(raw) && exist('xlsread', 'file')
        try
            try, pkg load io; catch; end %#ok<*CTCH>
            [~, ~, raw] = xlsread(filepath);
        catch
            raw = [];
        end
    end

    % Last resort (newer MATLAB): readmatrix for the numbers only.
    if isempty(raw) && exist('readtable', 'file')
        try
            Tt = readtable(filepath);
            headers = Tt.Properties.VariableNames;
            M = local_table2num(Tt);
            return;
        catch
            raw = [];
        end
    end

    if isempty(raw)
        error('srp_read_curve:noXlsx', ...
            ['Cannot read spreadsheet "%s".\n' ...
             'In GNU Octave install the io package:  pkg install -forge io\n' ...
             'then it will load automatically.'], filepath);
    end

    [headers, M] = local_cellblock2num(raw);
end

% =================================================================== text path
function [headers, M] = local_read_text(filepath)
    NL  = sprintf('\n');
    raw = fileread(filepath);
    raw = strrep(raw, sprintf('\r\n'), NL);
    raw = strrep(raw, sprintf('\r'),   NL);
    lines = strsplit(raw, NL);
    lines = lines(~cellfun(@(s) isempty(strtrim(s)), lines));
    if isempty(lines)
        headers = {}; M = []; return;
    end

    delim = local_detect_delimiter(lines{1});
    firstTokens = local_split(lines{1}, delim);
    hasHeader   = any(cellfun(@(t) isnan(str2double(t)) && ~isempty(strtrim(t)), firstTokens));

    if hasHeader
        headers   = strtrim(firstTokens);
        dataLines = lines(2:end);
    else
        headers   = {};
        dataLines = lines;
    end

    nc = numel(firstTokens);
    M = nan(numel(dataLines), max(nc, 3));
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
end

% ================================================================ cell helpers
function [headers, M] = local_cellblock2num(raw)
%LOCAL_CELLBLOCK2NUM  Split a raw cell block into header row + numeric matrix.
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
        headers = {};
        dataRows = 1:nRows;
    end

    M = nan(numel(dataRows), nCols);
    for r = 1:numel(dataRows)
        for c = 1:nCols
            M(r, c) = local_cell2num(raw{dataRows(r), c});
        end
    end
    % drop all-NaN trailing/empty rows
    M = M(any(isfinite(M), 2), :);
end

function M = local_table2num(Tt)
    nCols = size(Tt, 2);
    M = nan(height(Tt), nCols);
    for c = 1:nCols
        col = Tt{:, c};
        if isnumeric(col)
            M(:, c) = double(col);
        else
            M(:, c) = str2double(string(col));
        end
    end
    M = M(any(isfinite(M), 2), :);
end

function tf = local_is_text(x)
    tf = ischar(x) || (iscell(x) && ~isempty(x) && ischar(x{1})) || ...
         (isstring(x) && ~ismissing(x) && isnan(str2double(x)));
end

function s = local_cell2str(x)
    if ischar(x); s = x;
    elseif isstring(x); s = char(x);
    elseif isnumeric(x); s = num2str(x);
    else; s = ''; end
end

function v = local_cell2num(x)
    if isnumeric(x) && isscalar(x); v = double(x);
    elseif islogical(x); v = double(x);
    elseif ischar(x); v = str2double(x);
    elseif isstring(x); v = str2double(x);
    else; v = NaN; end
    if isempty(v); v = NaN; end
end

% ------------------------------------------------------------------ shared
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
        d = local_default_columns(cfg);   % positional fallback
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
